#!/bin/bash
# Assemble the release payload that install.sh downloads.
#
# One tarball holds everything a Mac needs at runtime: the bash CLI, the Go
# collectors, and the menubar app — all universal, so one asset serves Apple
# Silicon and Intel. Go and the Swift toolchain are paid for here, once, on a
# machine that has them; the people installing Nora then need neither.
#
#   ./scripts/package_release.sh [--version TAG] [--out DIR]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

OUT_DIR="$PROJECT_ROOT/dist"
TAG=""

usage() {
    cat << 'USAGE'
Usage: ./scripts/package_release.sh [--version TAG] [--out DIR]

  --version TAG  release tag being cut, e.g. V0.1.0. Must match VERSION in
                 `nora`; the mismatch is a release blocker, not a warning.
  --out DIR      where the tarball and SHA256SUMS land (default: dist/)
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            TAG="${2:-}"
            [[ -n "$TAG" ]] || { echo "--version needs a tag" >&2; exit 1; }
            shift 2
            ;;
        --out)
            OUT_DIR="${2:-}"
            [[ -n "$OUT_DIR" ]] || { echo "--out needs a path" >&2; exit 1; }
            shift 2
            ;;
        --help | -h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

for tool in go swift lipo codesign ditto shasum; do
    command -v "$tool" > /dev/null 2>&1 || {
        echo "Packaging a release needs $tool" >&2
        exit 1
    }
done

VERSION="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' nora | head -1)"
[[ -n "$VERSION" ]] || { echo "No VERSION in ./nora" >&2; exit 1; }

# The update check compares the installed VERSION against the latest release
# tag, so a tag that disagrees with the shipped VERSION makes every install
# think it is permanently out of date.
if [[ -n "$TAG" && "${TAG#[Vv]}" != "$VERSION" ]]; then
    echo "Tag $TAG does not match VERSION $VERSION in ./nora" >&2
    exit 1
fi

STAGE_ROOT="$OUT_DIR/payload"
STAGE="$STAGE_ROOT/nora-$VERSION"
TARBALL="$OUT_DIR/nora-macos.tar.gz"

echo "==> Packaging Nora $VERSION"
rm -rf "$STAGE_ROOT" "$TARBALL" "$OUT_DIR/SHA256SUMS"
mkdir -p "$STAGE/bin"

# ---------------------------------------------------------------- collectors

echo "==> Building Go collectors (arm64 + amd64)"
make release-arm64 release-amd64 > /dev/null

# Pure-Go builds should carry a low minimum OS; a cgo slip would raise it and
# silently drop older Macs. Cheap to check, expensive to discover in the wild.
./scripts/check_release_minos.sh

for helper in analyze status; do
    lipo -create \
        "bin/$helper-darwin-arm64" "bin/$helper-darwin-amd64" \
        -output "$STAGE/bin/$helper-go"
    chmod +x "$STAGE/bin/$helper-go"
done

# ---------------------------------------------------------------- app

echo "==> Building menubar app (universal)"
(cd app && NORA_APP_ARCHS="arm64 x86_64" ./build_app.sh release > /dev/null)
[[ -d "app/dist/NoraUI.app" ]] || { echo "No app bundle after build" >&2; exit 1; }

# ditto, not cp: it is the copy that keeps bundle metadata intact, and a
# mangled bundle here ships as an app that refuses to launch.
ditto "app/dist/NoraUI.app" "$STAGE/Nora.app"

# ---------------------------------------------------------------- payload

echo "==> Staging payload"
for item in nora nr lib scripts LICENSE NOTICE; do
    [[ -e "$item" ]] && ditto "$item" "$STAGE/$item"
done
# bin/ is the one directory that is part source, part build output: take the
# shell commands from the tree and leave whatever host-only Go binaries a local
# `make build` left behind.
for script in bin/*.sh; do
    ditto "$script" "$STAGE/$script"
done
chmod +x "$STAGE/nora" "$STAGE/nr" "$STAGE"/bin/*.sh
printf '%s\n' "$VERSION" > "$STAGE/VERSION"

# ---------------------------------------------------------------- verify

echo "==> Verifying"
for binary in "$STAGE/bin/analyze-go" "$STAGE/bin/status-go" "$STAGE/Nora.app/Contents/MacOS/NoraUI"; do
    archs="$(lipo -archs "$binary")"
    for want in arm64 x86_64; do
        case " $archs " in
            *" $want "*) ;;
            *)
                echo "$binary is missing the $want slice (has: $archs)" >&2
                exit 1
                ;;
        esac
    done
done

# An unsigned or broken bundle is refused by macOS at launch, which is far too
# late to find out.
codesign --verify --strict "$STAGE/Nora.app" || {
    echo "Nora.app failed signature verification" >&2
    exit 1
}

# ---------------------------------------------------------------- archive

echo "==> Archiving"
# COPYFILE_DISABLE keeps macOS from padding the archive with ._ AppleDouble
# entries, which would land in the user's install as junk files.
COPYFILE_DISABLE=1 tar -czf "$TARBALL" -C "$STAGE_ROOT" "nora-$VERSION"
(cd "$OUT_DIR" && shasum -a 256 "$(basename "$TARBALL")" > SHA256SUMS)

echo
echo "    $TARBALL ($(du -h "$TARBALL" | cut -f1 | tr -d ' '))"
echo "    $OUT_DIR/SHA256SUMS"
