#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-history-home.XXXXXX")"
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
    rm -rf "$HOME/Library"
    mkdir -p "$HOME/Library/Logs/nora"
}

write_history_logs() {
    cat > "$HOME/Library/Logs/nora/operations.log" <<'EOF'
# ========== clean session started at 2026-05-24 10:00:00 ==========
[2026-05-24 10:00:01] [clean] REMOVED /tmp/cache one (2KB)
[2026-05-24 10:00:02] [clean] TRASHED /tmp/Old App.app (4KB)
[2026-05-24 10:00:03] [clean] SKIPPED /tmp/protected (whitelist)
[2026-05-24 10:00:04] [clean] FAILED /tmp/fail (permission denied)
# ========== clean session ended at 2026-05-24 10:00:05, 2 items, 6KB ==========
# ========== purge session started at 2026-05-24 11:00:00 ==========
[2026-05-24 11:00:01] [purge] REMOVED /tmp/build (10KB)
# ========== purge session ended at 2026-05-24 11:00:02, 1 items, 10KB ==========
EOF

    printf '2026-05-24T10:00:02+0000\ttrash\t4\tok\t/tmp/Old App.app\n' > "$HOME/Library/Logs/nora/deletions.log"
    printf '2026-05-24T11:00:01+0000\tpermanent\t10\tdry-run\t/tmp/build\n' >> "$HOME/Library/Logs/nora/deletions.log"
}

@test "nr history summarizes operation sessions and deletion audit" {
    write_history_logs

    run env HOME="$HOME" "$PROJECT_ROOT/nora" history
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nora History"* ]] || return 1
    [[ "$output" == *"purge"* ]] || return 1
    [[ "$output" == *"1 items, 10KB"* ]] || return 1
    [[ "$output" == *"clean"* ]] || return 1
    [[ "$output" == *"removed 1, trashed 1, skipped 1, failed 1"* ]] || return 1
    [[ "$output" == *"/tmp/Old App.app"* ]]
}

@test "nr history --json returns stable parseable fields" {
    write_history_logs

    run env HOME="$HOME" "$PROJECT_ROOT/nora" history --json
    [ "$status" -eq 0 ]

    printf '%s\n' "$output" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
assert data["limit"] == 20
assert data["sessions"][0]["command"] == "purge"
assert data["sessions"][1]["command"] == "clean"
assert data["sessions"][1]["actions"]["trashed"] == 1
assert data["sessions"][1]["actions"]["failed"] == 1
assert data["deletions"][0]["mode"] == "permanent"
assert data["deletions"][0]["size_kb"] == 10
assert data["deletions"][1]["path"] == "/tmp/Old App.app"
'
}

@test "nr history --json escapes unusual path characters" {
    : > "$HOME/Library/Logs/nora/operations.log"
    weird_path=$'/tmp/unicode-\xe9\x9b\xaa-quote"slash\\tab\tbackspace\bformfeed\fend'
    printf '2026-05-24T10:00:02+0000\ttrash\t4\tok\t%s\n' "$weird_path" > "$HOME/Library/Logs/nora/deletions.log"

    run env HOME="$HOME" "$PROJECT_ROOT/nora" history --json
    [ "$status" -eq 0 ]

    printf '%s\n' "$output" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
assert data["deletions"][0]["path"] == "/tmp/unicode-\u96ea-quote\"slash\\tab\tbackspace\bformfeed\fend"
'
}

@test "nr history --limit caps sessions and deletion entries" {
    write_history_logs

    run env HOME="$HOME" "$PROJECT_ROOT/nora" history --limit 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"purge"* ]] || return 1
    [[ "$output" != *"clean      2026-05-24 10:00:00"* ]] || return 1
    [[ "$output" == *"/tmp/build"* ]] || return 1
    [[ "$output" != *"/tmp/Old App.app"* ]]
}

@test "nr history --limit accepts decimal values with leading zeros" {
    write_history_logs

    run env HOME="$HOME" "$PROJECT_ROOT/nora" history --limit 0001
    [ "$status" -eq 0 ]
    [[ "$output" == *"purge"* ]] || return 1
    [[ "$output" != *"clean      2026-05-24 10:00:00"* ]] || return 1
    [[ "$output" != *"value too great for base"* ]]
}

@test "nr history handles empty logs" {
    : > "$HOME/Library/Logs/nora/operations.log"

    run env HOME="$HOME" "$PROJECT_ROOT/nora" history
    [ "$status" -eq 0 ]
    [[ "$output" == *"No operation history yet"* ]] || return 1
    [[ "$output" == *"No deletion audit entries yet"* ]]
}

@test "nr history tolerates malformed session summaries" {
    cat > "$HOME/Library/Logs/nora/operations.log" <<'EOF'
# ========== clean session started at 2026-05-24 10:00:00 ==========
[2026-05-24 10:00:01] [clean] REMOVED /tmp/cache (2KB)
# ========== clean session ended at malformed summary ==========
EOF

    run env HOME="$HOME" "$PROJECT_ROOT/nora" history
    [ "$status" -eq 0 ]
    [[ "$output" == *"clean      2026-05-24 10:00:00, 0 items, 0B"* ]] || return 1
    [[ "$output" == *"removed 1, ended malformed summary"* ]] || return 1
    [[ "$output" != *"malformed summary items"* ]]
}

@test "nr history does not create logs when none exist" {
    rm -rf "$HOME/Library"

    run env HOME="$HOME" "$PROJECT_ROOT/nora" history
    [ "$status" -eq 0 ]
    [[ "$output" == *"No operation history yet"* ]] || return 1
    [ ! -e "$HOME/Library/Logs/nora/operations.log" ]
    [ ! -e "$HOME/Library/Logs/nora/nora.log" ]
}

@test "nr history early dispatch respects source guard" {
    # shellcheck disable=SC2016
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc -c '
set -euo pipefail
set -- history
NORA_TEST_MODE=1
NORA_SKIP_MAIN=1
source "$PROJECT_ROOT/nora"
echo sourced
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"sourced"* ]] || return 1
    [[ "$output" != *"Nora History"* ]]
}

@test "nr history early dispatch keeps global debug flag behavior" {
    run env HOME="$HOME" "$PROJECT_ROOT/nora" --debug history --limit 0001
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nora History"* ]] || return 1
    [[ "$output" != *"Unknown option"* ]] || return 1

    run env HOME="$HOME" "$PROJECT_ROOT/nora" history --debug --limit 0001
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nora History"* ]] || return 1
    [[ "$output" != *"Unknown option"* ]]
}

@test "nr history rejects unknown options" {
    run env HOME="$HOME" "$PROJECT_ROOT/nora" history --bad-option
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option for nr history"* ]]
}

@test "nr history rejects invalid limit values" {
    run env HOME="$HOME" "$PROJECT_ROOT/nora" history --limit nope
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid value for --limit"* ]] || return 1

    run env HOME="$HOME" "$PROJECT_ROOT/nora" history --limit 500
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid value for --limit"* ]] || return 1

    run env HOME="$HOME" "$PROJECT_ROOT/nora" history --limit 999999999999999999999999
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid value for --limit"* ]] || return 1
    [[ "$output" != *"value too great for base"* ]]
}
