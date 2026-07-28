#!/bin/bash
# Shared purge configuration and helpers (side-effect free).

set -euo pipefail

if [[ -n "${NORA_PURGE_SHARED_LOADED:-}" ]]; then
    return 0
fi
readonly NORA_PURGE_SHARED_LOADED=1

NORA_PURGE_PHYSICAL_HOME="$HOME"
if [[ -d "$HOME" ]]; then
    NORA_PURGE_PHYSICAL_HOME=$(cd "$HOME" 2> /dev/null && pwd -P) || NORA_PURGE_PHYSICAL_HOME="$HOME"
fi
readonly NORA_PURGE_PHYSICAL_HOME

# Canonical purge targets (heavy project build artifacts).
readonly NORA_PURGE_TARGETS=(
    "node_modules"
    "target"            # Rust, Maven
    "build"             # Gradle, various
    "dist"              # JS builds
    "venv"              # Python
    ".venv"             # Python
    ".pytest_cache"     # Python (pytest)
    ".mypy_cache"       # Python (mypy)
    ".tox"              # Python (tox virtualenvs)
    ".nox"              # Python (nox virtualenvs)
    ".ruff_cache"       # Python (ruff)
    ".gradle"           # Gradle local
    ".terragrunt-cache" # Terragrunt downloaded modules/providers
    "__pycache__"       # Python
    ".next"             # Next.js
    ".nuxt"             # Nuxt.js
    ".output"           # Nuxt.js
    "vendor"            # PHP Composer
    "bin"               # .NET build output (guarded; see is_protected_purge_artifact)
    "obj"               # C# / Unity
    ".turbo"            # Turborepo cache
    ".parcel-cache"     # Parcel bundler
    ".dart_tool"        # Flutter/Dart build cache
    ".zig-cache"        # Zig
    "zig-out"           # Zig
    ".angular"          # Angular
    ".svelte-kit"       # SvelteKit
    ".astro"            # Astro
    "coverage"          # Code coverage reports
    "DerivedData"       # Xcode
    "Pods"              # CocoaPods
    ".cxx"              # React Native Android NDK build cache
    ".expo"             # Expo
    ".build"            # Swift Package Manager
)

readonly NORA_PURGE_DEFAULT_SEARCH_PATHS=(
    "$HOME/www"
    "$HOME/dev"
    "$HOME/Projects"
    "$HOME/GitHub"
    "$HOME/Code"
    "$HOME/Workspace"
    "$HOME/Repos"
    "$HOME/Development"
    "$HOME/Library/CloudStorage"
    # AI agent worktree containers. These sit under dot directories, which
    # discover_project_dirs cannot reach: it globs "$HOME"/*/ and
    # is_project_container rejects any basename starting with a dot. Listing
    # the exact containers keeps the checkouts inside them in scope for
    # rebuildable-artifact cleanup without widening discovery to dot
    # directories in general. The worktrees themselves are never removed.
    "$HOME/.codex/worktrees"
    "$HOME/.claude/worktrees"
)

readonly NORA_PURGE_MONOREPO_INDICATORS=(
    "lerna.json"
    "pnpm-workspace.yaml"
    "nx.json"
    "rush.json"
)

readonly NORA_PURGE_PROJECT_INDICATORS=(
    "package.json"
    "Cargo.toml"
    "go.mod"
    "pyproject.toml"
    "requirements.txt"
    "pom.xml"
    "build.gradle"
    "terragrunt.hcl"
    "Gemfile"
    "composer.json"
    "pubspec.yaml"
    "Package.swift" # Swift Package Manager
    "Makefile"
    "build.zig"
    "build.zig.zon"
    ".git"
)

readonly NORA_CACHEDIR_TAG_NAME="CACHEDIR.TAG"
readonly NORA_CACHEDIR_TAG_SIGNATURE="Signature: 8a477f597d28d172789f06886806bc55"

# High-noise targets intentionally excluded from quick hint scans in nr clean.
readonly NORA_PURGE_QUICK_HINT_EXCLUDED_TARGETS=(
    "bin"
    "vendor"
)

nora_purge_is_cloud_synced_path() {
    local path="${1:-}"
    [[ -n "$path" ]] || return 1

    case "$path" in
        "$HOME/Library/CloudStorage" | "$HOME/Library/CloudStorage/"* | "$HOME/Library/Mobile Documents" | "$HOME/Library/Mobile Documents/"* | \
            "$NORA_PURGE_PHYSICAL_HOME/Library/CloudStorage" | "$NORA_PURGE_PHYSICAL_HOME/Library/CloudStorage/"* | "$NORA_PURGE_PHYSICAL_HOME/Library/Mobile Documents" | "$NORA_PURGE_PHYSICAL_HOME/Library/Mobile Documents/"*)
            return 0
            ;;
    esac

    return 1
}

nora_purge_is_project_root() {
    local dir="$1"
    local indicator

    for indicator in "${NORA_PURGE_MONOREPO_INDICATORS[@]}"; do
        if [[ -e "$dir/$indicator" ]]; then
            return 0
        fi
    done

    for indicator in "${NORA_PURGE_PROJECT_INDICATORS[@]}"; do
        if [[ -e "$dir/$indicator" ]]; then
            return 0
        fi
    done

    return 1
}

nora_dir_has_cachedir_tag() {
    local dir="$1"
    local tag="$dir/$NORA_CACHEDIR_TAG_NAME"
    [[ -f "$tag" && ! -L "$tag" ]] || return 1

    local signature
    signature=$(LC_ALL=C dd bs=${#NORA_CACHEDIR_TAG_SIGNATURE} count=1 < "$tag" 2> /dev/null || true)
    [[ "$signature" == "$NORA_CACHEDIR_TAG_SIGNATURE" ]]
}

nora_purge_quick_hint_target_names() {
    local target
    local excluded
    local is_excluded

    for target in "${NORA_PURGE_TARGETS[@]}"; do
        is_excluded=false
        for excluded in "${NORA_PURGE_QUICK_HINT_EXCLUDED_TARGETS[@]}"; do
            if [[ "$target" == "$excluded" ]]; then
                is_excluded=true
                break
            fi
        done
        [[ "$is_excluded" == "true" ]] && continue
        printf '%s\n' "$target"
    done
}

# Resolve a directory path to its canonical filesystem casing.
# On case-insensitive macOS (APFS), ~/Code and ~/code point to the same
# directory but with different display names.  This function returns the
# real (on-disk) path so that string comparisons work correctly for dedup.
nora_purge_resolve_path_case() {
    local path="$1"
    if [[ -d "$path" ]]; then
        (cd "$path" 2> /dev/null && pwd -P) || printf '%s\n' "$path"
    else
        printf '%s\n' "$path"
    fi
}

nora_purge_read_paths_config() {
    local config_file="${1:-$HOME/.config/nora/purge_paths}"
    [[ -f "$config_file" ]] || return 0

    local line
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        line="${line/#\~/$HOME}"
        line=$(nora_purge_resolve_path_case "$line")
        printf '%s\n' "$line"
    done < "$config_file"
}
