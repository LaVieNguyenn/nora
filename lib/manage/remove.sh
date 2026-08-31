#!/bin/bash
# Nora self-removal: Homebrew formula, manual binaries, config/cache/logs.
# Extracted from the `nora` dispatcher, which now only routes.

set -euo pipefail

if [[ -n "${NORA_MANAGE_REMOVE_LOADED:-}" ]]; then
    return 0
fi
readonly NORA_MANAGE_REMOVE_LOADED=1

# The PATH wrapper execs the install root, so it names where a --prefix install
# put the tree. The default location is a candidate either way.
_nora_install_root_candidates() {
    local wrapper
    for wrapper in "$@"; do
        [[ -f "$wrapper" ]] || continue
        sed -n 's|^exec "\(.*\)/nora" .*|\1|p' "$wrapper" 2> /dev/null | head -1
    done
    printf '%s\n' "$HOME/.nora"
}

# Only a directory that is actually an install: the entrypoint plus the library
# it sources. A source checkout is not one — `nora remove` run from a clone must
# never delete the clone.
_nora_is_install_root() {
    local root="$1"
    [[ -n "$root" && -d "$root" ]] || return 1
    [[ -x "$root/nora" && -f "$root/lib/core/common.sh" ]] || return 1

    local marker
    for marker in .git Makefile tests cmd app; do
        [[ -e "$root/$marker" ]] && return 1
    done
    return 0
}

# Nora's own bundle, identified by its bundle id rather than by being named
# Nora.app — somebody else's app of that name is not ours to delete.
_nora_is_own_app_bundle() {
    local bundle="$1"
    [[ -n "$bundle" && -d "$bundle" ]] || return 1

    local plist="$bundle/Contents/Info.plist"
    [[ -f "$plist" ]] || return 1
    [[ "$(plutil -extract CFBundleIdentifier raw "$plist" 2> /dev/null || true)" == "com.nora.ui" ]]
}

# Quit the app before its bundle goes away, and only the copy being removed:
# a Nora launched from somewhere else is not part of this uninstall.
_nora_quit_app_bundle() {
    local bundle="$1" pid
    for pid in $(pgrep -x NoraUI 2> /dev/null || true); do
        case "$(ps -p "$pid" -o comm= 2> /dev/null)" in
            "$bundle"/*) kill "$pid" 2> /dev/null || true ;;
        esac
    done
}

# Remove flow (Homebrew + manual + config/cache).
remove_nora() {
    local dry_run_mode="${1:-false}"
    local test_mode=false
    if [[ "${NORA_TEST_MODE:-0}" == "1" ]]; then
        test_mode=true
    fi

    if [[ -t 1 ]]; then
        start_inline_spinner "Detecting Nora installations..."
    else
        echo "Detecting installations..."
    fi

    local is_homebrew=false
    local brew_cmd=""
    local brew_has_nora="false"
    local -a manual_installs=()
    local -a alias_installs=()

    if [[ "$test_mode" != "true" ]]; then
        if command -v brew > /dev/null 2>&1; then
            brew_cmd="brew"
        elif [[ -x "/opt/homebrew/bin/brew" ]]; then
            brew_cmd="/opt/homebrew/bin/brew"
        elif [[ -x "/usr/local/bin/brew" ]]; then
            brew_cmd="/usr/local/bin/brew"
        fi

        if [[ -n "$brew_cmd" ]]; then
            if brew_nora_formula_installed "$brew_cmd"; then
                brew_has_nora="true"
            fi
        fi

        if [[ "$brew_has_nora" == "true" ]] || is_homebrew_install; then
            is_homebrew=true
        fi
    fi

    local found_nora
    found_nora=""
    if [[ "$test_mode" != "true" ]]; then
        found_nora=$(command -v nora 2> /dev/null || true)
        if [[ -n "$found_nora" && -f "$found_nora" ]]; then
            if [[ ! -L "$found_nora" ]] || ! readlink "$found_nora" | grep -q "Cellar/nora"; then
                manual_installs+=("$found_nora")
            fi
        fi
    fi

    local -a fallback_paths=()
    if [[ "$test_mode" == "true" ]]; then
        fallback_paths=("$HOME/.local/bin/nora")
    else
        fallback_paths=(
            "/usr/local/bin/nora"
            "$HOME/.local/bin/nora"
            "/opt/local/bin/nora"
        )
    fi

    for path in "${fallback_paths[@]}"; do
        if [[ -f "$path" && "$path" != "$found_nora" ]]; then
            if [[ ! -L "$path" ]] || ! readlink "$path" | grep -q "Cellar/nora"; then
                manual_installs+=("$path")
            fi
        fi
    done

    local found_mo
    found_mo=""
    if [[ "$test_mode" != "true" ]]; then
        found_mo=$(command -v nr 2> /dev/null || true)
        if [[ -n "$found_mo" && -f "$found_mo" ]]; then
            if [[ ! -L "$found_mo" ]] || ! readlink "$found_mo" | grep -q "Cellar/nora"; then
                alias_installs+=("$found_mo")
            fi
        fi
    fi

    local -a alias_fallback=()
    if [[ "$test_mode" == "true" ]]; then
        alias_fallback=("$HOME/.local/bin/nr")
    else
        alias_fallback=(
            "/usr/local/bin/nr"
            "$HOME/.local/bin/nr"
            "/opt/local/bin/nr"
        )
    fi

    for alias in "${alias_fallback[@]}"; do
        if [[ -f "$alias" && "$alias" != "$found_mo" ]]; then
            if [[ ! -L "$alias" ]] || ! readlink "$alias" | grep -q "Cellar/nora"; then
                alias_installs+=("$alias")
            fi
        fi
    done

    # The install tree and the app bundle install.sh writes. Neither was ever
    # removed here: `nora remove` left ~/.nora — the entire CLI it claims to
    # have removed — and /Applications/Nora.app behind.
    local -a install_roots=()
    local -a app_bundles=()
    local candidate
    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        _nora_is_install_root "$candidate" || continue
        local known=false root
        for root in ${install_roots[@]+"${install_roots[@]}"}; do
            [[ "$root" == "$candidate" ]] && known=true
        done
        [[ "$known" == "true" ]] || install_roots+=("$candidate")
    done < <(
        if [[ "$test_mode" == "true" ]]; then
            printf '%s\n' "$HOME/.nora"
        else
            _nora_install_root_candidates \
                ${manual_installs[@]+"${manual_installs[@]}"} \
                ${alias_installs[@]+"${alias_installs[@]}"}
        fi
    )

    local -a app_candidates=("$HOME/Applications/Nora.app")
    [[ "$test_mode" == "true" ]] || app_candidates+=("/Applications/Nora.app")
    for candidate in "${app_candidates[@]}"; do
        _nora_is_own_app_bundle "$candidate" && app_bundles+=("$candidate")
    done

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    printf '\n'

    local install_root_count=${#install_roots[@]}
    local app_bundle_count=${#app_bundles[@]}
    local manual_count=${#manual_installs[@]}
    local alias_count=${#alias_installs[@]}
    if [[ "$is_homebrew" == "false" && ${manual_count:-0} -eq 0 && ${alias_count:-0} -eq 0 &&
        ${install_root_count:-0} -eq 0 && ${app_bundle_count:-0} -eq 0 ]]; then
        printf '%s\n\n' "${YELLOW}No Nora installation detected${NC}"
        exit 0
    fi

    # Dry-run mode: show preview and exit without confirmation
    if [[ "$dry_run_mode" == "true" ]]; then
        echo -e "${YELLOW}${ICON_DRY_RUN} DRY RUN MODE${NC}, no files will be removed"
        echo ""
        echo -e "${YELLOW}Remove Nora${NC}, would delete the following:"
        if [[ "$is_homebrew" == "true" ]]; then
            echo -e "  ${GRAY}${ICON_LIST} Would run: brew uninstall --force nora${NC}"
        fi
        if [[ ${manual_count:-0} -gt 0 ]]; then
            for install in "${manual_installs[@]}"; do
                [[ -f "$install" ]] && echo -e "  ${GRAY}${ICON_LIST} Would remove: ${install}${NC}"
            done
        fi
        if [[ ${alias_count:-0} -gt 0 ]]; then
            for alias in "${alias_installs[@]}"; do
                [[ -f "$alias" ]] && echo -e "  ${GRAY}${ICON_LIST} Would remove: ${alias}${NC}"
            done
        fi
        if [[ ${install_root_count:-0} -gt 0 ]]; then
            for root in "${install_roots[@]}"; do
                echo -e "  ${GRAY}${ICON_LIST} Would remove: ${root}${NC}"
            done
        fi
        if [[ ${app_bundle_count:-0} -gt 0 ]]; then
            for bundle in "${app_bundles[@]}"; do
                echo -e "  ${GRAY}${ICON_LIST} Would remove: ${bundle}${NC}"
            done
        fi
        [[ -d "$HOME/.cache/nora" ]] && echo -e "  ${GRAY}${ICON_LIST} Would remove: $HOME/.cache/nora${NC}"
        [[ -d "$HOME/.config/nora" ]] && echo -e "  ${GRAY}${ICON_LIST} Would remove: $HOME/.config/nora${NC}"
        [[ -d "$HOME/Library/Logs/nora" ]] && echo -e "  ${GRAY}${ICON_LIST} Would remove: $HOME/Library/Logs/nora${NC}"

        printf '\n%s\n\n' "${GREEN}${ICON_SUCCESS}${NC} Dry run complete, no changes made"
        exit 0
    fi

    echo -e "${YELLOW}Remove Nora${NC}, will delete the following:"
    if [[ "$is_homebrew" == "true" ]]; then
        echo "  ${ICON_LIST} Nora via Homebrew"
    fi
    for install in ${manual_installs[@]+"${manual_installs[@]}"} ${alias_installs[@]+"${alias_installs[@]}"} \
        ${install_roots[@]+"${install_roots[@]}"} ${app_bundles[@]+"${app_bundles[@]}"}; do
        echo "  ${ICON_LIST} $install"
    done
    echo "  ${ICON_LIST} ~/.config/nora"
    echo "  ${ICON_LIST} ~/.cache/nora"
    echo "  ${ICON_LIST} ~/Library/Logs/nora"
    echo -ne "${PURPLE}${ICON_ARROW}${NC} Press ${GREEN}Enter${NC} to confirm, ${GRAY}ESC${NC} to cancel: "

    IFS= read -r -s -n1 key || key=""
    drain_pending_input # Clean up any escape sequence remnants
    case "$key" in
        $'\e')
            exit 0
            ;;
        "" | $'\n' | $'\r')
            printf "\r\033[K" # Clear the prompt line
            ;;
        *)
            exit 0
            ;;
    esac

    local has_error=false
    if [[ "$is_homebrew" == "true" ]]; then
        if [[ -z "$brew_cmd" ]]; then
            log_error "Homebrew command not found. Please ensure Homebrew is installed and in your PATH."
            log_warning "Manual step: brew uninstall --force nora"
            exit 1
        fi

        log_info "Attempting to uninstall Nora via Homebrew..."
        local brew_uninstall_output
        if ! brew_uninstall_output=$("$brew_cmd" uninstall --force nora 2>&1); then
            has_error=true
            log_error "Homebrew uninstallation failed:"
            printf "%s\n" "$brew_uninstall_output" | sed "s/^/${RED}  | ${NC}/" >&2
            log_warning "Manual step: ${YELLOW}brew uninstall --force nora${NC}"
            echo "" # Add a blank line for readability
        else
            log_success "Nora uninstalled via Homebrew."
        fi
    fi
    if [[ ${manual_count:-0} -gt 0 ]]; then
        for install in "${manual_installs[@]}"; do
            if [[ -f "$install" ]]; then
                if [[ ! -w "$(dirname "$install")" ]]; then
                    if [[ "${NORA_TEST_MODE:-0}" == "1" || "${NORA_TEST_NO_AUTH:-0}" == "1" ]] || ! sudo rm -f "$install" 2> /dev/null; then
                        has_error=true
                    fi
                else
                    if ! rm -f "$install" 2> /dev/null; then
                        has_error=true
                    fi
                fi
            fi
        done
    fi
    if [[ ${alias_count:-0} -gt 0 ]]; then
        for alias in "${alias_installs[@]}"; do
            if [[ -f "$alias" ]]; then
                if [[ ! -w "$(dirname "$alias")" ]]; then
                    if [[ "${NORA_TEST_MODE:-0}" == "1" || "${NORA_TEST_NO_AUTH:-0}" == "1" ]] || ! sudo rm -f "$alias" 2> /dev/null; then
                        has_error=true
                    fi
                else
                    if ! rm -f "$alias" 2> /dev/null; then
                        has_error=true
                    fi
                fi
            fi
        done
    fi
    if [[ ${app_bundle_count:-0} -gt 0 ]]; then
        for bundle in "${app_bundles[@]}"; do
            _nora_quit_app_bundle "$bundle"
            if [[ -w "$(dirname "$bundle")" ]]; then
                rm -rf "$bundle" 2> /dev/null || has_error=true # SAFE: bundle id checked above
            elif [[ "${NORA_TEST_MODE:-0}" == "1" || "${NORA_TEST_NO_AUTH:-0}" == "1" ]] ||
                ! sudo rm -rf "$bundle" 2> /dev/null; then
                has_error=true
            fi
        done
    fi
    if [[ -d "$HOME/.cache/nora" ]]; then
        rm -rf "$HOME/.cache/nora" 2> /dev/null || true # SAFE: hardcoded Nora-owned dir, -d guarded
    fi
    if [[ -d "$HOME/.config/nora" ]]; then
        rm -rf "$HOME/.config/nora" 2> /dev/null || true # SAFE: hardcoded Nora-owned dir, -d guarded
    fi
    if [[ -d "$HOME/Library/Logs/nora" ]]; then
        rm -rf "$HOME/Library/Logs/nora" 2> /dev/null || true # SAFE: hardcoded Nora-owned dir, -d guarded
    fi

    # Last, because this is the tree the running script lives in. Unlinking an
    # open file leaves the inode alive for the fd bash is reading from, so the
    # rest of this function still runs; truncating it would not.
    if [[ ${install_root_count:-0} -gt 0 ]]; then
        for root in "${install_roots[@]}"; do
            rm -rf "$root" 2> /dev/null || has_error=true # SAFE: verified install root above
        done
    fi

    local final_message
    if [[ "$has_error" == "true" ]]; then
        final_message="${YELLOW}${ICON_ERROR} Nora uninstalled with some errors, thank you for using Nora!${NC}"
    else
        final_message="${GREEN}${ICON_SUCCESS} Nora uninstalled successfully, thank you for using Nora!${NC}"
    fi
    printf '\n%s\n\n' "$final_message"

    exit 0
}
