#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    TEST_DATA_DIR="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-perf.XXXXXX")"
    export TEST_DATA_DIR
}

teardown_file() {
    rm -rf "$TEST_DATA_DIR"
}

setup() {
    source "$PROJECT_ROOT/lib/core/base.sh"
}

@test "bytes_to_human handles large values efficiently" {
    local start end elapsed
    local limit_ms="${NORA_PERF_BYTES_TO_HUMAN_LIMIT_MS:-4000}"

    bytes_to_human 1073741824 > /dev/null

    start=$(date +%s%N)
    for i in {1..1000}; do
        bytes_to_human 1073741824 > /dev/null
    done
    end=$(date +%s%N)

    elapsed=$(( (end - start) / 1000000 ))

    [ "$elapsed" -lt "$limit_ms" ]
}

@test "bytes_to_human produces correct output for GB range" {
    result=$(bytes_to_human 1000000000)
    [ "$result" = "1.00GB" ]

    result=$(bytes_to_human 5000000000)
    [ "$result" = "5.00GB" ]
}

@test "bytes_to_human produces correct output for MB range" {
    result=$(bytes_to_human 1000000)
    [ "$result" = "1.0MB" ]

    result=$(bytes_to_human 100000000)
    [ "$result" = "100.0MB" ]
}

@test "bytes_to_human produces correct output for KB range" {
    result=$(bytes_to_human 1000)
    [ "$result" = "1KB" ]

    result=$(bytes_to_human 10000)
    [ "$result" = "10KB" ]
}

@test "bytes_to_human handles edge cases" {
    result=$(bytes_to_human 0)
    [ "$result" = "0B" ]

    run bytes_to_human "invalid"
    [ "$status" -eq 1 ]
    [ "$output" = "0B" ]

    run bytes_to_human "-100"
    [ "$status" -eq 1 ]
    [ "$output" = "0B" ]
}

@test "get_file_size is faster than multiple stat calls" {
    local test_file="$TEST_DATA_DIR/size_test.txt"
    dd if=/dev/zero of="$test_file" bs=1024 count=100 2> /dev/null

    local start end elapsed
    local limit_ms="${NORA_PERF_GET_FILE_SIZE_LIMIT_MS:-2000}"
    start=$(date +%s%N)
    for i in {1..50}; do
        get_file_size "$test_file" > /dev/null
    done
    end=$(date +%s%N)

    elapsed=$(( (end - start) / 1000000 ))

    [ "$elapsed" -lt "$limit_ms" ]
}

@test "get_file_mtime returns valid timestamp" {
    local test_file="$TEST_DATA_DIR/mtime_test.txt"
    touch "$test_file"

    result=$(get_file_mtime "$test_file")

    [[ "$result" =~ ^[0-9]{10,}$ ]]
}

@test "get_file_owner returns current user for owned files" {
    local test_file="$TEST_DATA_DIR/owner_test.txt"
    touch "$test_file"

    result=$(get_file_owner "$test_file")
    current_user=$(whoami)

    [ "$result" = "$current_user" ]
}

@test "create_temp_file and cleanup_temp_files work efficiently" {
    local start end elapsed
    local limit_ms="${NORA_PERF_CREATE_TEMP_FILE_LIMIT_MS:-3000}"

    declare -a NORA_TEMP_DIRS=()

    start=$(date +%s%N)
    for i in {1..50}; do
        create_temp_file > /dev/null
    done
    end=$(date +%s%N)

    elapsed=$(( (end - start) / 1000000 ))

    [ "$elapsed" -lt "$limit_ms" ]

    [ "${#NORA_TEMP_FILES[@]}" -eq 50 ]

    start=$(date +%s%N)
    cleanup_temp_files
    end=$(date +%s%N)

    elapsed=$(( (end - start) / 1000000 ))
    [ "$elapsed" -lt "$limit_ms" ]

    [ "${#NORA_TEMP_FILES[@]}" -eq 0 ]
}

@test "mktemp_file creates files with correct prefix" {
    local temp_file
    temp_file=$(mktemp_file "test_prefix")

    [[ "$temp_file" =~ test_prefix ]] || return 1

    [ -f "$temp_file" ]

    rm -f "$temp_file"
}

@test "get_optimal_parallel_jobs returns sensible values" {
    local result

    result=$(get_optimal_parallel_jobs)
    [[ "$result" =~ ^[0-9]+$ ]] || return 1
    [ "$result" -gt 0 ]
    [ "$result" -le 128 ]

    local scan_jobs
    scan_jobs=$(get_optimal_parallel_jobs "scan")
    [ "$scan_jobs" -gt "$result" ]

    local compute_jobs
    compute_jobs=$(get_optimal_parallel_jobs "compute")
    [ "$compute_jobs" -le "$scan_jobs" ]
}

@test "section tracking has minimal overhead" {
    local start end elapsed

    if ! declare -f note_activity > /dev/null 2>&1; then
        TRACK_SECTION=0
        SECTION_ACTIVITY=0
        note_activity() {
            if [[ $TRACK_SECTION -eq 1 ]]; then
                SECTION_ACTIVITY=1
            fi
        }
    fi

    note_activity

    start=$(date +%s%N)
    for i in {1..1000}; do
        note_activity
    done
    end=$(date +%s%N)

    elapsed=$(( (end - start) / 1000000 ))

    local limit_ms="${NORA_PERF_SECTION_LIMIT_MS:-2000}"
    [ "$elapsed" -lt "$limit_ms" ]
}

@test "run_with_timeout does not round short commands up to the poll interval" {
    # macOS has no timeout(1), so every run_with_timeout call takes the perl
    # fallback. A fixed poll there charged every wrapped command a full tick:
    # a 2ms `du` cost 125ms, and get_path_size_kb runs one per sized directory.
    source "$PROJECT_ROOT/lib/core/timeout.sh"

    local start end elapsed
    start=$(date +%s%N)
    for _ in 1 2 3 4 5; do
        run_with_timeout 30 true > /dev/null 2>&1
    done
    end=$(date +%s%N)

    elapsed=$(((end - start) / 1000000 / 5))

    # The floor is perl interpreter startup (~5ms); the old fixed 0.1s poll put
    # this at 100ms+. Anything at or above the old tick means the backoff was
    # lost.
    local limit_ms="${NORA_PERF_TIMEOUT_LIMIT_MS:-60}"
    [ "$elapsed" -lt "$limit_ms" ] || {
        echo "run_with_timeout averaged ${elapsed}ms per call (limit ${limit_ms}ms)" >&2
        return 1
    }
}

@test "perl timeout fallback polls with backoff, not a fixed tick" {
    # Source invariant: pins the class rather than one measurement, so a future
    # edit that reinstates `sleep 0.1` in the wait loop fails here even on a
    # machine fast enough to pass the timing test above.
    local perl_block
    perl_block=$(sed -n '/my \$deadline = time() + \$duration;/,/^            }/p' \
        "$PROJECT_ROOT/lib/core/timeout.sh")

    [ -n "$perl_block" ] || {
        echo "could not locate the perl wait loop" >&2
        return 1
    }

    echo "$perl_block" | grep -q 'sleep \$nap' || {
        echo "wait loop no longer sleeps on the backoff variable" >&2
        return 1
    }

    echo "$perl_block" | grep -q '\$nap = \$nap \* 2' || {
        echo "wait loop lost its backoff growth" >&2
        return 1
    }
}

@test "entrypoint dispatches exec-only subcommands before sourcing libraries" {
    # `nora` exec's into bin/<cmd>.sh, and that target re-sources the same
    # library set in its own process. Sourcing first cost ~35ms on every
    # `nr clean`, `nr status`, and friends for libraries the router then threw
    # away by exec'ing.
    #
    # Source invariant rather than a timing check: it pins the ordering, which
    # is the thing that regresses when someone moves the dispatch back into
    # `main`.
    local entry="$PROJECT_ROOT/nora"

    local dispatch_line source_line
    dispatch_line=$(grep -n '^nora_dispatch_exec_early "\$@"' "$entry" | head -1 | cut -d: -f1)
    source_line=$(grep -n '^source .*lib/core/common.sh' "$entry" | head -1 | cut -d: -f1)

    [ -n "$dispatch_line" ] || {
        echo "early exec dispatch is gone" >&2
        return 1
    }
    [ -n "$source_line" ] || {
        echo "could not find the common.sh source line" >&2
        return 1
    }
    [ "$dispatch_line" -lt "$source_line" ] || {
        echo "dispatch (line $dispatch_line) must run before sourcing (line $source_line)" >&2
        return 1
    }
}

@test "early exec dispatch covers every subcommand main only exec's" {
    # If a subcommand is added to main's case as a bare exec but not to the
    # early dispatch, it silently keeps paying the sourcing cost.
    local entry="$PROJECT_ROOT/nora"
    local cmd missing=""

    for cmd in optimize clean uninstall analyze status purge installer touchid completion; do
        grep -q "^        $cmd[)| ]" "$entry" || continue
        awk '/^nora_dispatch_exec_early\(\)/,/^}/' "$entry" | grep -q "$cmd" || missing="$missing $cmd"
    done

    [ -z "$missing" ] || {
        echo "missing from early dispatch:$missing" >&2
        return 1
    }
}
