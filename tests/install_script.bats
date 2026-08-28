#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    # The installer falls back to $HOME/Applications and writes wrappers under
    # $HOME; a sandboxed home keeps a mistake here away from the real one.
    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-install-home.XXXXXX")"
    export HOME
}

teardown_file() {
    if [[ "$HOME" == "${BATS_TEST_DIRNAME}/tmp-"* ]]; then
        rm -rf "$HOME"
    fi
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

setup() {
    if [[ "$HOME" != "${BATS_TEST_DIRNAME}/tmp-"* ]]; then
        printf 'FATAL: HOME is not a test temp dir: %s\n' "$HOME" >&2
        return 1
    fi
    export TERM="dumb"

    WORK="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-install.XXXXXX")"
    RELEASE_DIR="$WORK/release"
    INSTALL_DIR="$WORK/nora"
    BIN_DIR="$WORK/bin"
    APP_DIR="$WORK/Applications"
    mkdir -p "$RELEASE_DIR"
    make_fake_release
}

teardown() {
    if [[ "$WORK" == "${BATS_TEST_DIRNAME}/tmp-"* ]]; then
        rm -rf "$WORK"
    fi
}

# A payload shaped exactly like scripts/package_release.sh produces, so the
# installer is exercised end to end without a network or a toolchain.
make_fake_release() {
    local stage="$WORK/payload/nora-9.9.9"
    mkdir -p "$stage/bin" "$stage/lib/core" "$stage/Nora.app/Contents/MacOS"

    printf '#!/bin/bash\necho nora\n' > "$stage/nora"
    printf '#!/bin/bash\necho nr\n' > "$stage/nr"
    printf '#!/bin/bash\necho status\n' > "$stage/bin/status-go"
    printf '#!/bin/bash\necho analyze\n' > "$stage/bin/analyze-go"
    printf '#!/bin/bash\n:\n' > "$stage/bin/clean.sh"
    printf 'true\n' > "$stage/lib/core/common.sh"
    printf 'mach-o\n' > "$stage/Nora.app/Contents/MacOS/NoraUI"
    printf '9.9.9\n' > "$stage/VERSION"
    chmod +x "$stage/nora" "$stage/nr" "$stage/bin/status-go" \
        "$stage/bin/analyze-go" "$stage/Nora.app/Contents/MacOS/NoraUI"

    COPYFILE_DISABLE=1 tar -czf "$RELEASE_DIR/nora-macos.tar.gz" \
        -C "$WORK/payload" "nora-9.9.9"
    (cd "$RELEASE_DIR" && shasum -a 256 nora-macos.tar.gz > SHA256SUMS)
}

run_installer() {
    run env \
        NORA_RELEASE_BASE="file://$RELEASE_DIR" \
        NORA_INSTALL_DIR="$INSTALL_DIR" \
        NORA_BIN_DIR="$BIN_DIR" \
        NORA_APP_DIR="$APP_DIR" \
        bash "$PROJECT_ROOT/install.sh" "$@"
}

@test "install.sh is syntactically valid" {
    run bash -n "$PROJECT_ROOT/install.sh"
    [ "$status" -eq 0 ]
}

@test "install.sh refuses non-macOS and old macOS before touching anything" {
    # The guards have to come first: the script removes ~/.nora before copying,
    # so reaching that point on an unsupported system would delete an install
    # it then cannot replace.
    local body
    body=$(cat "$PROJECT_ROOT/install.sh")

    local darwin_line macos_line remove_line
    darwin_line=$(grep -n 'uname -s' <<< "$body" | head -1 | cut -d: -f1)
    macos_line=$(grep -n 'productVersion | cut' <<< "$body" | head -1 | cut -d: -f1)
    remove_line=$(grep -n 'rm -rf "\$INSTALL_DIR"' <<< "$body" | head -1 | cut -d: -f1)

    [ -n "$darwin_line" ] || return 1
    [ -n "$macos_line" ] || return 1
    [ -n "$remove_line" ] || return 1
    [ "$darwin_line" -lt "$remove_line" ] || return 1
    [ "$macos_line" -lt "$remove_line" ] || return 1
}

@test "install.sh needs no toolchain on the default path" {
    # The whole point of shipping a prebuilt release: a Mac with neither Go nor
    # Xcode installs the CLI *and* the app. Both toolchain checks must sit
    # inside the source builder, not in the preflight everyone runs.
    local source_line
    source_line=$(grep -n '^install_from_source()' "$PROJECT_ROOT/install.sh" | head -1 | cut -d: -f1)
    [ -n "$source_line" ] || return 1

    local tool line
    for tool in go swift; do
        line=$(grep -n "command -v $tool" "$PROJECT_ROOT/install.sh" | head -1 | cut -d: -f1)
        [ -n "$line" ] || return 1
        [ "$line" -gt "$source_line" ] || {
            echo "install.sh requires $tool before the source path starts" >&2
            return 1
        }
    done
}

@test "install.sh installs the CLI and the app from a release" {
    run_installer
    [ "$status" -eq 0 ]

    [ -x "$INSTALL_DIR/nora" ] || return 1
    [ -x "$INSTALL_DIR/bin/status-go" ] || return 1
    [ -f "$INSTALL_DIR/lib/core/common.sh" ] || return 1
    [ -x "$BIN_DIR/nora" ] || return 1
    [ -x "$BIN_DIR/nr" ] || return 1
    [ -x "$APP_DIR/Nora.app/Contents/MacOS/NoraUI" ] || return 1
}

@test "install.sh writes wrappers, not symlinks, into PATH" {
    # The entrypoint resolves its library root from `dirname "${BASH_SOURCE[0]}"`,
    # which does not follow symlinks: through a symlink it looks for lib/ beside
    # the link and dies with "common.sh: No such file or directory" on every
    # invocation. Caught by an end-to-end install, not by any unit test.
    run_installer
    [ "$status" -eq 0 ]

    [ ! -L "$BIN_DIR/nora" ] || return 1
    run grep -q "exec \"$INSTALL_DIR/nora\"" "$BIN_DIR/nora"
    [ "$status" -eq 0 ]
}

@test "install.sh leaves the app payload out of the CLI install" {
    run_installer
    [ "$status" -eq 0 ]
    [ ! -e "$INSTALL_DIR/Nora.app" ] || return 1
}

@test "install.sh refuses a download whose checksum does not match" {
    printf '%s  nora-macos.tar.gz\n' \
        "0000000000000000000000000000000000000000000000000000000000000000" \
        > "$RELEASE_DIR/SHA256SUMS"

    # A previous install must survive a bad download: verification happens
    # before the install directory is wiped.
    mkdir -p "$INSTALL_DIR"
    printf 'keep me\n' > "$INSTALL_DIR/sentinel"

    run_installer
    [ "$status" -ne 0 ]
    [[ "$output" == *"Checksum"* ]] || return 1
    [ -f "$INSTALL_DIR/sentinel" ] || return 1
    [ ! -e "$APP_DIR/Nora.app" ] || return 1
}

@test "install.sh refuses a release asset with no checksum file" {
    rm -f "$RELEASE_DIR/SHA256SUMS"

    run_installer
    [ "$status" -ne 0 ]
    [ ! -e "$INSTALL_DIR/nora" ] || return 1
}

@test "install.sh does not silently build from source when a base is set" {
    # An explicit NORA_RELEASE_BASE names where the release comes from; falling
    # back to a GitHub source build would ignore that and need a toolchain.
    rm -rf "$RELEASE_DIR"
    mkdir -p "$RELEASE_DIR"

    run_installer
    [ "$status" -ne 0 ]
    [[ "$output" == *"$RELEASE_DIR"* ]] || return 1
    [[ "$output" != *"Build bộ thu thập"* ]] || return 1
}

@test "install.sh refuses to install over a source checkout" {
    # `nora update` passes --prefix from wherever the running nora lives. For
    # someone working on Nora that is the checkout, and the install starts by
    # deleting the prefix — this guard is what keeps a working tree.
    mkdir -p "$INSTALL_DIR/tests"
    printf 'all:\n' > "$INSTALL_DIR/Makefile"

    run_installer --prefix "$INSTALL_DIR"
    [ "$status" -ne 0 ]
    [ -f "$INSTALL_DIR/Makefile" ] || return 1
    [ -d "$INSTALL_DIR/tests" ] || return 1
}

@test "install.sh refuses a prefix that is the home directory" {
    run_installer --prefix "$HOME"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Từ chối"* ]] || return 1
}

@test "install.sh ignores options it does not know instead of aborting" {
    # `nora update` calls the installer with flags from whichever version is
    # installed; an unknown one must not be able to brick the update.
    run_installer --config "$WORK/config" --update --not-a-real-flag
    [ "$status" -eq 0 ]
    [ -x "$BIN_DIR/nora" ] || return 1
}

@test "install.sh --help explains itself without installing" {
    run_installer --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--from-source"* ]] || return 1
    [ ! -e "$INSTALL_DIR" ] || return 1
}

@test "install.sh installs only runtime files, not tests or app sources" {
    local copied
    copied=$(grep -o 'for item in [^;]*' "$PROJECT_ROOT/install.sh" | head -1)
    [[ "$copied" == *"nora"* ]] || return 1
    [[ "$copied" != *"tests"* ]] || return 1
    [[ "$copied" != *" app"* ]] || return 1
}

@test "install.sh aborts when the Go build fails" {
    # A partial install is worse than none: without these binaries the CLI
    # reports "missing collector" on every run.
    run grep -q 'make build > /dev/null) || fail' "$PROJECT_ROOT/install.sh"
    [ "$status" -eq 0 ]
    run grep -q 'Thiếu \$binary sau khi build' "$PROJECT_ROOT/install.sh"
    [ "$status" -eq 0 ]
}

@test "install.sh keeps the CLI when the app cannot be built" {
    # The app is optional; a missing Swift toolchain or a failed build must warn
    # and leave the working CLI in place rather than abort the whole install.
    run grep -c 'CLI vẫn dùng được' "$PROJECT_ROOT/install.sh"
    [ "$status" -eq 0 ]
    run grep -q 'bỏ qua app menubar' "$PROJECT_ROOT/install.sh"
    [ "$status" -eq 0 ]
}
