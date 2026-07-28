#!/bin/bash
# Nora installer.
#
# Builds from source rather than downloading a release binary: this is a
# personal fork with no release pipeline, so a checksum-verified artifact does
# not exist and pretending otherwise would be weaker, not stronger.
#
#   curl -fsSL https://raw.githubusercontent.com/LaVieNguyenn/nora/main/install.sh | bash

set -euo pipefail

REPO="LaVieNguyenn/nora"
BRANCH="${NORA_BRANCH:-main}"
INSTALL_DIR="$HOME/.nora"
APP_DIR="/Applications"
BIN_DIR="${NORA_BIN_DIR:-$HOME/.local/bin}"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BLUE=$'\033[1;34m'; NC=$'\033[0m'

info()  { echo "${BLUE}==>${NC} $*"; }
ok()    { echo "${GREEN} ok ${NC} $*"; }
warn()  { echo "${YELLOW} !! ${NC} $*"; }
fail()  { echo "${RED}✗${NC} $*" >&2; exit 1; }

# ---------------------------------------------------------------- preflight

[[ "$(uname -s)" == "Darwin" ]] || fail "Nora chỉ chạy trên macOS."

macos_major=$(sw_vers -productVersion | cut -d. -f1)
[[ "$macos_major" -ge 14 ]] || fail "Cần macOS 14 trở lên (máy đang chạy $(sw_vers -productVersion))."

command -v go > /dev/null 2>&1 || fail "Chưa có Go. Cài bằng: brew install go"
command -v swift > /dev/null 2>&1 || fail "Chưa có Swift. Cài Xcode Command Line Tools: xcode-select --install"

# ---------------------------------------------------------------- fetch

workdir=$(mktemp -d)
# Keep the trap simple: the only thing to undo is the scratch directory.
trap 'rm -rf "$workdir"' EXIT

info "Tải mã nguồn ($BRANCH)"
tarball="https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz"
if ! curl -fsSL "$tarball" | tar -xz -C "$workdir"; then
    fail "Không tải được $tarball"
fi

src="$workdir/nora-$BRANCH"
[[ -d "$src" ]] || src=$(find "$workdir" -maxdepth 1 -type d -name 'nora-*' | head -1)
[[ -d "$src" ]] || fail "Giải nén xong nhưng không tìm thấy thư mục mã nguồn."

# ---------------------------------------------------------------- build CLI

info "Build bộ thu thập (Go)"
(cd "$src" && make build > /dev/null) || fail "Build Go thất bại."

for binary in bin/status-go bin/analyze-go; do
    [[ -x "$src/$binary" ]] || fail "Thiếu $binary sau khi build."
done
ok "Đã build status-go và analyze-go"

# ---------------------------------------------------------------- install CLI

info "Cài CLI vào $INSTALL_DIR"
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
# Only what the CLI needs at runtime; the app and tests stay out of the
# install so `nora remove` has nothing surprising to clean up.
for item in nora nr bin lib internal scripts LICENSE NOTICE; do
    [[ -e "$src/$item" ]] && cp -R "$src/$item" "$INSTALL_DIR/"
done
chmod +x "$INSTALL_DIR/nora" "$INSTALL_DIR/nr"

# Wrappers, not symlinks. The entrypoint derives its library root from
# `dirname "${BASH_SOURCE[0]}"`, which does not resolve symlinks — through a
# symlink it would look for lib/ next to the link and fail to source anything.
mkdir -p "$BIN_DIR"
for name in nora nr; do
    cat > "$BIN_DIR/$name" <<WRAPPER
#!/bin/bash
exec "$INSTALL_DIR/$name" "\$@"
WRAPPER
    chmod +x "$BIN_DIR/$name"
done
ok "Đã cài CLI"

# ---------------------------------------------------------------- build app

info "Build app menubar (Swift) — mất một lúc"
if (cd "$src/app" && ./build_app.sh release > /dev/null 2>&1); then
    rm -rf "$APP_DIR/Nora.app"
    if cp -R "$src/app/dist/NoraUI.app" "$APP_DIR/Nora.app" 2> /dev/null; then
        ok "Đã cài $APP_DIR/Nora.app"
    else
        # /Applications may need admin rights; fall back rather than abort,
        # since the CLI is already usable at this point.
        cp -R "$src/app/dist/NoraUI.app" "$HOME/Applications/Nora.app" 2> /dev/null \
            && ok "Đã cài vào ~/Applications/Nora.app" \
            || warn "Không chép được app; CLI vẫn dùng được."
    fi
else
    warn "Build app thất bại — CLI vẫn dùng được. Chạy lại thủ công: cd app && ./build_app.sh release"
fi

# ---------------------------------------------------------------- PATH

if ! echo ":$PATH:" | grep -q ":$BIN_DIR:"; then
    shell_rc="$HOME/.zshrc"
    [[ "${SHELL:-}" == *bash* ]] && shell_rc="$HOME/.bash_profile"
    warn "$BIN_DIR chưa nằm trong PATH. Thêm dòng này vào $shell_rc:"
    echo "    export PATH=\"$BIN_DIR:\$PATH\""
fi

echo
ok "Xong. Thử: ${BLUE}nora --help${NC}"
echo "   App menubar: mở Nora từ Launchpad, hoặc"
echo "   open \"$APP_DIR/Nora.app\" --args --window"
