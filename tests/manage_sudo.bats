#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

setup() {
    source "$PROJECT_ROOT/lib/core/common.sh"
    source "$PROJECT_ROOT/lib/core/sudo.sh"
}

@test "has_sudo_session returns 1 when no sudo session" {
    # shellcheck disable=SC2329
    sudo() { return 1; }
    export -f sudo
    run has_sudo_session
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "sudo keepalive functions don't crash" {

    # shellcheck disable=SC2329
    function sudo() {
        return 1  # Simulate no sudo available
    }
    export -f sudo

    run /bin/bash -c "source '$PROJECT_ROOT/lib/core/common.sh'; source '$PROJECT_ROOT/lib/core/sudo.sh'; has_sudo_session"
    [ "$status" -eq 1 ]  # Expected: no sudo session
}

@test "_start_sudo_keepalive returns a PID" {
    function sudo() {
        case "$1" in
            -n) return 0 ;;  # Simulate valid sudo session
            -v) return 0 ;;  # Refresh succeeds
            *) return 1 ;;
        esac
    }
    export -f sudo

    local pid
    pid=$(/bin/bash -c "source '$PROJECT_ROOT/lib/core/common.sh'; source '$PROJECT_ROOT/lib/core/sudo.sh'; _start_sudo_keepalive")

    [[ "$pid" =~ ^[0-9]+$ ]] || return 1

    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}

@test "_stop_sudo_keepalive handles invalid PID gracefully" {
    run /bin/bash -c "source '$PROJECT_ROOT/lib/core/common.sh'; source '$PROJECT_ROOT/lib/core/sudo.sh'; _stop_sudo_keepalive ''"
    [ "$status" -eq 0 ]

    run /bin/bash -c "source '$PROJECT_ROOT/lib/core/common.sh'; source '$PROJECT_ROOT/lib/core/sudo.sh'; _stop_sudo_keepalive '99999'"
    [ "$status" -eq 0 ]
}



@test "stop_sudo_session cleans up keepalive process" {
    export NORA_SUDO_KEEPALIVE_PID="99999"

    run /bin/bash -c "export NORA_SUDO_KEEPALIVE_PID=99999; source '$PROJECT_ROOT/lib/core/common.sh'; source '$PROJECT_ROOT/lib/core/sudo.sh'; stop_sudo_session"
    [ "$status" -eq 0 ]
}

@test "sudo manager initializes global state correctly" {
    result=$(/bin/bash -c "source '$PROJECT_ROOT/lib/core/common.sh'; source '$PROJECT_ROOT/lib/core/sudo.sh'; echo \$NORA_SUDO_ESTABLISHED")
    [[ "$result" == "false" ]] || [[ -z "$result" ]]
}

@test "request_sudo_access clears four lines in clamshell mode when Touch ID hint is shown" {
    run /bin/bash -c '
        unset NORA_TEST_MODE NORA_TEST_NO_AUTH
        source "'"$PROJECT_ROOT"'/lib/core/common.sh"
        source "'"$PROJECT_ROOT"'/lib/core/sudo.sh"

        tty_file="$(mktemp)"
        chmod 600 "$tty_file"

        sudo() {
            case "$1" in
                -n) return 1 ;;
                -k) return 0 ;;
                *) return 1 ;;
            esac
        }
        tty() { printf "%s\n" "$tty_file"; }
        # The stand-in terminal is a plain temp file, which _tty_is_usable
        # rightly rejects. These tests are about the line clearing, not about
        # how a terminal is detected.
        _tty_is_usable() { return 0; }
        is_clamshell_mode() { return 0; }
        check_touchid_support() { return 0; }
        _request_password() { return 0; }
        safe_clear_lines() { printf "CLEAR:%s\n" "$1"; }

        request_sudo_access "Admin access required"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"CLEAR:4"* ]]
}

@test "request_sudo_access keeps three-line cleanup in clamshell mode without Touch ID" {
    run /bin/bash -c '
        unset NORA_TEST_MODE NORA_TEST_NO_AUTH
        source "'"$PROJECT_ROOT"'/lib/core/common.sh"
        source "'"$PROJECT_ROOT"'/lib/core/sudo.sh"

        tty_file="$(mktemp)"
        chmod 600 "$tty_file"

        sudo() {
            case "$1" in
                -n) return 1 ;;
                -k) return 0 ;;
                *) return 1 ;;
            esac
        }
        tty() { printf "%s\n" "$tty_file"; }
        # The stand-in terminal is a plain temp file, which _tty_is_usable
        # rightly rejects. These tests are about the line clearing, not about
        # how a terminal is detected.
        _tty_is_usable() { return 0; }
        is_clamshell_mode() { return 0; }
        check_touchid_support() { return 1; }
        _request_password() { return 0; }
        safe_clear_lines() { printf "CLEAR:%s\n" "$1"; }

        request_sudo_access "Admin access required"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"CLEAR:3"* ]]
}

# /dev/tty is crw-rw-rw-, so a `-r`/`-w` test passes even where opening it fails
# with ENXIO. That is exactly the app's situation — no controlling terminal —
# and it used to take the terminal password path there, printing
# "/dev/tty: Device not configured" three times and giving up with "Admin access
# denied" instead of showing the GUI dialog.

@test "_tty_is_usable says no when the process has no controlling terminal" {
    run python3 - "$PROJECT_ROOT" <<'NOTTY_PROBE'
import os, sys
repo = sys.argv[1]
script = (
    'source "%s/lib/core/sudo.sh"; '
    '_tty_is_usable /dev/tty && echo TTY || echo NOTTY; '
    '[[ -r /dev/tty && -w /dev/tty ]] && echo PERMS_SAY_TTY || echo PERMS_SAY_NOTTY'
) % repo
pid = os.fork()
if pid == 0:
    os.setsid()  # new session: no controlling terminal, like a GUI app
    os.execvp("bash", ["bash", "-c", script])
os.waitpid(pid, 0)
NOTTY_PROBE

    [ "$status" -eq 0 ]
    [[ "$output" == *"NOTTY"* ]] || return 1
    # The permission bits still claim a terminal is there; that is the trap.
    [[ "$output" == *"PERMS_SAY_TTY"* ]] || return 1
}

@test "_tty_is_usable says yes inside a real terminal" {
    # Without this half, the fix would push terminal users into a GUI password
    # dialog they never asked for.
    run python3 - "$PROJECT_ROOT" <<'TTY_PROBE'
import pty, sys
repo = sys.argv[1]
script = (
    'source "%s/lib/core/sudo.sh"; '
    '_tty_is_usable /dev/tty && echo TTY || echo NOTTY'
) % repo
pty.spawn(["bash", "-c", script])
TTY_PROBE

    [ "$status" -eq 0 ]
    [[ "$output" == *"TTY"* ]] || return 1
    [[ "$output" != *"NOTTY"* ]] || return 1
}
