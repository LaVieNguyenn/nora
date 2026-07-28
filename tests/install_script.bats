#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
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

@test "install.sh checks for Go and Swift before building" {
    run grep -q 'command -v go' "$PROJECT_ROOT/install.sh"
    [ "$status" -eq 0 ]
    run grep -q 'command -v swift' "$PROJECT_ROOT/install.sh"
    [ "$status" -eq 0 ]
}

@test "install.sh aborts when the Go build fails" {
    # A partial install is worse than none: without these binaries the CLI
    # reports "missing collector" on every run.
    run grep -q 'make build > /dev/null) || fail' "$PROJECT_ROOT/install.sh"
    [ "$status" -eq 0 ]
    run grep -q 'Thiếu \$binary sau khi build' "$PROJECT_ROOT/install.sh"
    [ "$status" -eq 0 ]
}

@test "install.sh does not install the app over a failed build" {
    # The app is optional; a failed Swift build must warn and leave the working
    # CLI in place rather than abort the whole install.
    run grep -q 'CLI vẫn dùng được' "$PROJECT_ROOT/install.sh"
    [ "$status" -eq 0 ]
}

@test "install.sh installs only runtime files, not tests or app sources" {
    local copied
    copied=$(grep -o 'for item in [^;]*' "$PROJECT_ROOT/install.sh" | head -1)
    [[ "$copied" == *"nora"* ]] || return 1
    [[ "$copied" != *"tests"* ]] || return 1
    [[ "$copied" != *" app"* ]] || return 1
}

@test "install.sh writes wrappers, not symlinks, into PATH" {
    # The entrypoint resolves its library root from `dirname "${BASH_SOURCE[0]}"`,
    # which does not follow symlinks: through a symlink it looks for lib/ beside
    # the link and dies with "common.sh: No such file or directory" on every
    # invocation. Caught by an end-to-end install, not by any unit test.
    run grep -q 'ln -sf "\$INSTALL_DIR' "$PROJECT_ROOT/install.sh"
    [ "$status" -ne 0 ] || {
        echo "install.sh symlinks the entrypoint into PATH; use a wrapper" >&2
        return 1
    }

    run grep -q 'exec "\$INSTALL_DIR/\$name"' "$PROJECT_ROOT/install.sh"
    [ "$status" -eq 0 ]
}
