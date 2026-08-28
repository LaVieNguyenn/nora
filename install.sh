#!/bin/bash
# Nora installer.
#
# Default path downloads a prebuilt release: the CLI, the Go collectors and the
# menubar app, all built and signed by CI. A Mac needs nothing but this script.
#
# It used to build everything from source, which made the Swift toolchain a
# hard requirement — and Swift ships with Xcode. A machine with Homebrew and Go
# but no Xcode failed the preflight and got no install at all, not even the CLI
# that Go alone can build. Source builds are still here behind --from-source;
# they are how CI produces the release, not how a user installs it.
#
#   curl -fsSL https://raw.githubusercontent.com/LaVieNguyenn/nora/main/install.sh | bash

set -euo pipefail

REPO="LaVieNguyenn/nora"
BRANCH="${NORA_BRANCH:-main}"
INSTALL_DIR="${NORA_INSTALL_DIR:-$HOME/.nora}"
BIN_DIR="${NORA_BIN_DIR:-$HOME/.local/bin}"
APP_DIR="${NORA_APP_DIR:-/Applications}"
ASSET="nora-macos.tar.gz"
SUMS="SHA256SUMS"

# Empty means "whatever GitHub calls latest". `nora update` passes a tag here.
VERSION_TAG="${NORA_VERSION:-}"
FROM_SOURCE="${NORA_FROM_SOURCE:-0}"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BLUE=$'\033[1;34m'; NC=$'\033[0m'

info()  { echo "${BLUE}==>${NC} $*"; }
ok()    { echo "${GREEN} ok ${NC} $*"; }
warn()  { echo "${YELLOW} !! ${NC} $*"; }
fail()  { echo "${RED}✗${NC} $*" >&2; exit 1; }

usage() {
    cat << 'USAGE'
Cài Nora (CLI + app menubar).

  install.sh [tuỳ chọn]

Tuỳ chọn:
  --version TAG    cài đúng một bản phát hành (mặc định: bản mới nhất)
  --from-source    build từ mã nguồn thay vì tải bản dựng sẵn
                   (cần Go; cần thêm Swift/Xcode nếu muốn có app)
  --prefix DIR     thư mục cài (mặc định ~/.nora)
  --bin-dir DIR    nơi đặt lệnh nora/nr (mặc định ~/.local/bin)
  --help           in trợ giúp này

Biến môi trường tương đương: NORA_VERSION, NORA_FROM_SOURCE=1,
NORA_INSTALL_DIR, NORA_BIN_DIR, NORA_APP_DIR, NORA_BRANCH.
NORA_RELEASE_BASE trỏ tới nơi khác chứa tệp phát hành (bản sao nội bộ).
USAGE
}

# `nora update` invokes this script with --prefix/--config/--update. Unknown
# options warn instead of aborting: a future update flow must never be able to
# brick an install by passing a flag this version has not learned yet.
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION_TAG="${2:-}"
            [[ -n "$VERSION_TAG" ]] || fail "--version cần một tag."
            shift 2
            ;;
        --from-source)
            FROM_SOURCE=1
            shift
            ;;
        --prefix)
            INSTALL_DIR="${2:-}"
            [[ -n "$INSTALL_DIR" ]] || fail "--prefix cần một đường dẫn."
            shift 2
            ;;
        --bin-dir)
            BIN_DIR="${2:-}"
            [[ -n "$BIN_DIR" ]] || fail "--bin-dir cần một đường dẫn."
            shift 2
            ;;
        --config)
            shift 2
            ;;
        --update)
            shift
            ;;
        --help | -h)
            usage
            exit 0
            ;;
        *)
            warn "Bỏ qua tuỳ chọn lạ: $1"
            shift
            ;;
    esac
done

# `nora update --nightly` asks for the branch by name, not a release tag.
if [[ "$VERSION_TAG" == "main" || "$VERSION_TAG" == "nightly" ]]; then
    BRANCH="main"
    VERSION_TAG=""
    FROM_SOURCE=1
fi

# ---------------------------------------------------------------- preflight

# These guards run before anything is downloaded or removed: the install wipes
# $INSTALL_DIR before copying, so reaching that on an unsupported system would
# delete an install it then cannot replace.
[[ "$(uname -s)" == "Darwin" ]] || fail "Nora chỉ chạy trên macOS."

macos_major=$(sw_vers -productVersion | cut -d. -f1)
[[ "$macos_major" -ge 14 ]] || fail "Cần macOS 14 trở lên (máy đang chạy $(sw_vers -productVersion))."

command -v curl > /dev/null 2>&1 || fail "Cần curl."

workdir=$(mktemp -d)
# Keep the trap simple: the only thing to undo is the scratch directory.
trap 'rm -rf "$workdir"' EXIT

# Source tree to install from — a checkout when building, the unpacked release
# payload otherwise. Both have the same layout, so the install step is shared.
src=""
# Bundle to copy into /Applications, empty when there is none to install.
app_bundle=""
# Where the bundle ended up, so the closing hint points at the real path.
installed_app=""

# ---------------------------------------------------------------- helpers

download() {
    local url="$1" out="$2" attempt=1
    while true; do
        if curl -fsSL --connect-timeout 10 --max-time 300 "$url" -o "$out"; then
            return 0
        fi
        rm -f "$out" 2> /dev/null || true
        [[ "$attempt" -ge 3 ]] && return 1
        sleep 1
        attempt=$((attempt + 1))
    done
}

# Tags in this repo are V-prefixed (`nora update` builds that name itself), but
# a plain `v0.1.0` is the more common habit. Try what was asked for first, then
# the other spelling, rather than 404 on a tag that exists.
tag_variants() {
    local tag="$1" bare="${1#[Vv]}"
    printf '%s\n' "$tag"
    [[ "$tag" != "V$bare" ]] && printf '%s\n' "V$bare"
    [[ "$tag" != "v$bare" ]] && printf '%s\n' "v$bare"
}

release_bases() {
    # A mirror, or a local directory of assets for a machine that cannot
    # reach GitHub. Also what the installer tests point at.
    if [[ -n "${NORA_RELEASE_BASE:-}" ]]; then
        printf '%s\n' "${NORA_RELEASE_BASE%/}"
    elif [[ -n "$VERSION_TAG" ]]; then
        local tag
        while IFS= read -r tag; do
            printf 'https://github.com/%s/releases/download/%s\n' "$REPO" "$tag"
        done < <(tag_variants "$VERSION_TAG")
    else
        printf 'https://github.com/%s/releases/latest/download\n' "$REPO"
    fi
}

# ---------------------------------------------------------------- release

fetch_release() {
    local base
    while IFS= read -r base; do
        download "$base/$ASSET" "$workdir/$ASSET" || continue
        download "$base/$SUMS" "$workdir/$SUMS" || {
            # An asset without its checksum file is not something to install.
            rm -f "$workdir/$ASSET"
            continue
        }
        return 0
    done < <(release_bases)
    return 1
}

# The checksum catches a truncated or corrupted download; it is not a signature
# and does not attest to who built the asset. HTTPS to GitHub is the trust
# anchor, same as for the script you are reading.
verify_release() {
    local expected actual
    expected=$(awk -v f="$ASSET" '{ name = $2; sub(/^\*/, "", name); if (name == f) { print $1; exit } }' "$workdir/$SUMS")
    [[ -n "$expected" ]] || return 1
    actual=$(shasum -a 256 "$workdir/$ASSET" | awk '{print $1}')
    [[ "$expected" == "$actual" ]]
}

install_from_release() {
    info "Tải bản dựng sẵn"
    fetch_release || return 1

    if ! verify_release; then
        fail "Checksum không khớp — không cài bản tải về. Thử lại, hoặc dùng --from-source."
    fi

    mkdir -p "$workdir/payload"
    tar -xzf "$workdir/$ASSET" -C "$workdir/payload" || fail "Không giải nén được $ASSET."

    local root
    root=$(find "$workdir/payload" -maxdepth 1 -mindepth 1 -type d | head -1 || true)
    [[ -n "$root" ]] || fail "Gói tải về không có thư mục mã nguồn."

    [[ -x "$root/nora" && -x "$root/bin/status-go" ]] ||
        fail "Gói tải về thiếu tệp — không cài."

    src="$root"
    [[ -d "$root/Nora.app" ]] && app_bundle="$root/Nora.app"

    local version="unknown"
    [[ -f "$root/VERSION" ]] && version=$(cat "$root/VERSION")
    ok "Đã tải và kiểm tra bản $version"
}

# ---------------------------------------------------------------- source

install_from_source() {
    command -v go > /dev/null 2>&1 ||
        fail "Build từ nguồn cần Go. Cài bằng: brew install go — hoặc bỏ --from-source để tải bản dựng sẵn."

    info "Tải mã nguồn ($BRANCH)"
    local tarball="https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz"
    if ! curl -fsSL "$tarball" | tar -xz -C "$workdir"; then
        fail "Không tải được $tarball"
    fi

    local root="$workdir/nora-$BRANCH"
    [[ -d "$root" ]] || root=$(find "$workdir" -maxdepth 1 -type d -name 'nora-*' | head -1 || true)
    [[ -d "$root" ]] || fail "Giải nén xong nhưng không tìm thấy thư mục mã nguồn."

    info "Build bộ thu thập (Go)"
    (cd "$root" && make build > /dev/null) || fail "Build Go thất bại."

    local binary
    for binary in bin/status-go bin/analyze-go; do
        [[ -x "$root/$binary" ]] || fail "Thiếu $binary sau khi build."
    done
    ok "Đã build status-go và analyze-go"

    src="$root"

    # The app is optional. Without Swift there is no way to build it here, and
    # that is not a reason to withhold a working CLI.
    if ! command -v swift > /dev/null 2>&1; then
        warn "Không có Swift nên bỏ qua app menubar. Cài Xcode Command Line Tools (xcode-select --install), hoặc bỏ --from-source để lấy app dựng sẵn."
        return 0
    fi

    info "Build app menubar (Swift) — mất một lúc"
    if (cd "$root/app" && ./build_app.sh release > /dev/null 2>&1); then
        app_bundle="$root/app/dist/NoraUI.app"
    else
        warn "Build app thất bại — CLI vẫn dùng được. Chạy lại thủ công: cd app && ./build_app.sh release"
    fi
}

# ---------------------------------------------------------------- install

# $INSTALL_DIR is about to be deleted, and `nora update` fills it in from
# wherever the running `nora` lives — for someone working on Nora that is the
# checkout itself. Nothing here is worth a wiped working tree.
guard_install_dir() {
    case "$INSTALL_DIR" in
        "" | "/" | "$HOME" | "$HOME/")
            fail "Từ chối cài vào $INSTALL_DIR."
            ;;
    esac

    local marker
    for marker in .git Makefile tests cmd; do
        if [[ -e "$INSTALL_DIR/$marker" ]]; then
            fail "$INSTALL_DIR trông như thư mục mã nguồn (có $marker), không phải nơi cài. Dừng lại để không xoá nhầm."
        fi
    done
}

install_cli() {
    guard_install_dir

    info "Cài CLI vào $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    # Only what the CLI needs at runtime; the app and tests stay out of the
    # install so `nora remove` has nothing surprising to clean up.
    local item
    for item in nora nr bin lib scripts LICENSE NOTICE; do
        [[ -e "$src/$item" ]] && cp -R "$src/$item" "$INSTALL_DIR/"
    done
    chmod +x "$INSTALL_DIR/nora" "$INSTALL_DIR/nr"

    # Wrappers, not symlinks. The entrypoint derives its library root from
    # `dirname "${BASH_SOURCE[0]}"`, which does not resolve symlinks — through a
    # symlink it would look for lib/ next to the link and fail to source anything.
    mkdir -p "$BIN_DIR"
    local name
    for name in nora nr; do
        cat > "$BIN_DIR/$name" <<WRAPPER
#!/bin/bash
exec "$INSTALL_DIR/$name" "\$@"
WRAPPER
        chmod +x "$BIN_DIR/$name"
    done
    ok "Đã cài CLI"
}

install_app() {
    [[ -n "$app_bundle" ]] || return 0

    local dest="$APP_DIR/Nora.app"
    mkdir -p "$APP_DIR" 2> /dev/null || true
    if [[ ! -w "$APP_DIR" ]]; then
        # /Applications may need admin rights; fall back rather than abort,
        # since the CLI is already usable at this point.
        dest="$HOME/Applications/Nora.app"
        mkdir -p "$HOME/Applications"
    fi

    info "Cài app menubar vào $dest"

    # Replacing a bundle out from under a running app leaves it running against
    # files that no longer exist. Quit it first — but only the copy being
    # replaced: a Nora launched from somewhere else is not ours to close.
    local pid
    for pid in $(pgrep -x NoraUI 2> /dev/null || true); do
        case "$(ps -p "$pid" -o comm= 2> /dev/null)" in
            "$dest"/*) kill "$pid" 2> /dev/null || true ;;
        esac
    done

    rm -rf "$dest"
    if ! cp -R "$app_bundle" "$dest" 2> /dev/null; then
        warn "Không chép được app; CLI vẫn dùng được."
        return 0
    fi

    # curl does not quarantine what it downloads, but a browser download or a
    # copy through one would, and a quarantined ad-hoc signed app will not open.
    xattr -dr com.apple.quarantine "$dest" 2> /dev/null || true
    installed_app="$dest"
    ok "Đã cài $dest"
}

# ---------------------------------------------------------------- run

# Checked again next to the `rm -rf` it protects; checked here so a refusal
# costs nothing more than the time to read it.
guard_install_dir

if [[ "$FROM_SOURCE" == "1" ]]; then
    install_from_source
elif ! install_from_release; then
    # An explicit base is a deliberate choice of where the release comes from.
    # Quietly building from GitHub instead would ignore that choice.
    [[ -n "${NORA_RELEASE_BASE:-}" ]] &&
        fail "Không lấy được bản phát hành từ ${NORA_RELEASE_BASE}."
    warn "Không lấy được bản dựng sẵn (chưa có bản phát hành, hoặc mạng chặn GitHub)."
    if command -v go > /dev/null 2>&1; then
        warn "Chuyển sang build từ nguồn."
        install_from_source
    else
        fail "Không tải được bản dựng sẵn và máy chưa có Go để build. Kiểm tra mạng, hoặc cài Go: brew install go"
    fi
fi

install_cli
install_app

# ---------------------------------------------------------------- PATH

if ! echo ":$PATH:" | grep -q ":$BIN_DIR:"; then
    shell_rc="$HOME/.zshrc"
    [[ "${SHELL:-}" == *bash* ]] && shell_rc="$HOME/.bash_profile"
    warn "$BIN_DIR chưa nằm trong PATH. Thêm dòng này vào $shell_rc:"
    echo "    export PATH=\"$BIN_DIR:\$PATH\""
fi

echo
ok "Xong. Thử: ${BLUE}nora --help${NC}"
if [[ -n "$installed_app" ]]; then
    echo "   App menubar: mở Nora từ Launchpad, hoặc"
    echo "   open \"$installed_app\" --args --window"
fi
