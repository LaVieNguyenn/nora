#!/usr/bin/env bats

setup_file() {
	PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
	export PROJECT_ROOT
}

setup() {
	HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-update-home.XXXXXX")"
	TEST_ROOT="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-update-case.XXXXXX")"
	export HOME TEST_ROOT
}

teardown() {
	case "${HOME:-}" in
		"${BATS_TEST_DIRNAME}/tmp-update-home."*) rm -rf "$HOME" ;;
	esac
	case "${TEST_ROOT:-}" in
		"${BATS_TEST_DIRNAME}/tmp-update-case."*) rm -rf "$TEST_ROOT" ;;
	esac
}

make_manual_nora_install() {
	local install_dir="$1"
	local config_dir="$2"
	local version="$3"
	mkdir -p "$install_dir" "$config_dir/bin"
	sed \
		-e "s|^SCRIPT_DIR=.*|SCRIPT_DIR=\"$config_dir\"|" \
		-e "s/^VERSION=\".*\"$/VERSION=\"$version\"/" \
		"$PROJECT_ROOT/nora" > "$install_dir/nora"
	cp "$PROJECT_ROOT/nr" "$install_dir/nr"
	cp -R "$PROJECT_ROOT/lib" "$config_dir/lib"
	printf '#!/bin/bash\nexit 0\n' > "$config_dir/bin/analyze-go"
	printf '#!/bin/bash\nexit 0\n' > "$config_dir/bin/status-go"
	chmod +x "$install_dir/nora" "$install_dir/nr" "$config_dir/bin/analyze-go" "$config_dir/bin/status-go"
}

make_homebrew_shadow() {
	local bin_dir="$1"
	local cellar_nora="$2"
	mkdir -p "$bin_dir" "$(dirname "$cellar_nora")"
	cp "$PROJECT_ROOT/nora" "$cellar_nora"
	cp -R "$PROJECT_ROOT/lib" "$bin_dir/lib"
	chmod +x "$cellar_nora"
	ln -sf "$cellar_nora" "$bin_dir/nora"
	ln -sf "$cellar_nora" "$bin_dir/nr"

	cat > "$bin_dir/brew" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BREW_LOG"
case "${1:-}" in
	list)
		if [[ "${2:-}" == "--versions" ]]; then
			printf 'nora 9.9.9\n'
		fi
		exit 0
		;;
	update)
		exit 0
		;;
	upgrade)
		if [[ -n "${BREW_UPGRADE_OUTPUT:-}" ]]; then
			printf '%s\n' "$BREW_UPGRADE_OUTPUT"
		fi
		exit "${BREW_UPGRADE_STATUS:-0}"
		;;
esac
exit 0
SCRIPT
	chmod +x "$bin_dir/brew"
}

make_update_curl_stub() {
	local bin_dir="$1"
	local latest_version="$2"
	cat > "$bin_dir/curl" <<SCRIPT
#!/usr/bin/env bash
out=""
url=""
while [[ \$# -gt 0 ]]; do
	case "\$1" in
		-o)
			out="\$2"
			shift 2
			;;
		http*://*)
			url="\$1"
			shift
			;;
		*)
			shift
			;;
	esac
done
[[ -n "\$url" ]] && printf '%s\n' "\$url" >> "\$CURL_URL_LOG"

if [[ -n "\$out" ]]; then
	if [[ -n "\${CURL_TRANSIENT_FAILURES:-}" && -n "\${CURL_ATTEMPT_LOG:-}" ]]; then
		attempt=0
		[[ -f "\$CURL_ATTEMPT_LOG" ]] && attempt=\$(cat "\$CURL_ATTEMPT_LOG")
		attempt=\$((attempt + 1))
		printf '%s\n' "\$attempt" > "\$CURL_ATTEMPT_LOG"
		if [[ "\$attempt" -le "\$CURL_TRANSIENT_FAILURES" ]]; then
			exit "\${CURL_TRANSIENT_STATUS:-35}"
		fi
	fi
	cat > "\$out" <<'INSTALLER'
#!/usr/bin/env bash
printf '%s\n' "\$*" > "\$INSTALLER_ARGS_LOG"
printf '%s\n' "\${NORA_VERSION:-}" > "\$INSTALLER_VERSION_LOG"
if [[ -n "\${INSTALLER_SUDO_AUTH_LOG:-}" ]]; then
	printf '%s\n' "\${NORA_ASSUME_SUDO_AUTH:-}" > "\$INSTALLER_SUDO_AUTH_LOG"
fi
echo "Updated to latest version, \${NORA_VERSION#V}"
INSTALLER
	exit 0
fi

if [[ "\$url" == *"api.github.com"* ]]; then
	printf '{"tag_name":"%s"}\n' "$latest_version"
	exit 0
fi

printf 'VERSION="%s"\n' "$latest_version"
SCRIPT
	chmod +x "$bin_dir/curl"
}

make_nightly_update_curl_stub() {
	local bin_dir="$1"
	local latest_commit="$2"
	cat > "$bin_dir/curl" <<SCRIPT
#!/usr/bin/env bash
out=""
url=""
while [[ \$# -gt 0 ]]; do
	case "\$1" in
		-o)
			out="\$2"
			shift 2
			;;
		http*://*)
			url="\$1"
			shift
			;;
		*)
			shift
			;;
	esac
done
[[ -n "\$url" ]] && printf '%s\n' "\$url" >> "\$CURL_URL_LOG"

if [[ -n "\$out" ]]; then
	cat > "\$out" <<'INSTALLER'
#!/usr/bin/env bash
printf '%s\n' "\$*" > "\$INSTALLER_ARGS_LOG"
printf '%s\n' "\${NORA_VERSION:-}" > "\$INSTALLER_VERSION_LOG"
if [[ -n "\${INSTALLER_SUDO_AUTH_LOG:-}" ]]; then
	printf '%s\n' "\${NORA_ASSUME_SUDO_AUTH:-}" > "\$INSTALLER_SUDO_AUTH_LOG"
fi
echo "Updated to latest version, \${NORA_VERSION#V}"
INSTALLER
	exit 0
fi

if [[ "\$url" == *"api.github.com/repos/LaVieNguyenn/nora/commits/main"* ]]; then
	printf '{"sha":"%s"}\n' "$latest_commit"
	exit 0
fi

exit 1
SCRIPT
	chmod +x "$bin_dir/curl"
}

@test "nr update repairs missing helpers at the current stable version (#1193)" {
	local manual_bin="$TEST_ROOT/manual/bin"
	local manual_config="$TEST_ROOT/manual/config"
	local fake_bin="$TEST_ROOT/fake-bin"
	local installer_args_log="$TEST_ROOT/installer.args"
	local installer_version_log="$TEST_ROOT/installer.version"
	local curl_url_log="$TEST_ROOT/curl.urls"
	local current_version

	current_version="$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' "$PROJECT_ROOT/nora" | head -1)"
	mkdir -p "$fake_bin"
	make_manual_nora_install "$manual_bin" "$manual_config" "$current_version"
	make_update_curl_stub "$fake_bin" "$current_version"
	rm -f "$manual_config/bin/analyze-go"
	touch "$manual_config/.helper_install_incomplete"
	: > "$curl_url_log"

	run env \
		HOME="$HOME" \
		PATH="$fake_bin:/usr/bin:/bin" \
		CURL_URL_LOG="$curl_url_log" \
		INSTALLER_ARGS_LOG="$installer_args_log" \
		INSTALLER_VERSION_LOG="$installer_version_log" \
		"$manual_bin/nr" update

	[ "$status" -eq 0 ]
	[[ "$output" == *"Nora installation needs repair"* ]] || return 1
	[[ "$output" == *"missing analyze-go"* ]] || return 1
	[ -f "$installer_args_log" ]
	if grep -q -- "--update" "$installer_args_log"; then
		return 1
	fi
	[ "$(cat "$installer_version_log")" = "V$current_version" ]
}

@test "nr update retries transient installer download failures" {
	local manual_bin="$TEST_ROOT/manual/bin"
	local manual_config="$TEST_ROOT/manual/config"
	local fake_bin="$TEST_ROOT/fake-bin"
	local installer_args_log="$TEST_ROOT/installer.args"
	local installer_version_log="$TEST_ROOT/installer.version"
	local curl_url_log="$TEST_ROOT/curl.urls"
	local curl_attempt_log="$TEST_ROOT/curl.attempts"
	local current_version

	current_version="$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' "$PROJECT_ROOT/nora" | head -1)"
	mkdir -p "$fake_bin"
	make_manual_nora_install "$manual_bin" "$manual_config" "0.0.1"
	make_update_curl_stub "$fake_bin" "$current_version"
	printf '#!/bin/bash\nexit 0\n' > "$fake_bin/sleep"
	chmod +x "$fake_bin/sleep"
	: > "$curl_url_log"

	run env \
		HOME="$HOME" \
		PATH="$fake_bin:/usr/bin:/bin" \
		CURL_URL_LOG="$curl_url_log" \
		CURL_ATTEMPT_LOG="$curl_attempt_log" \
		CURL_TRANSIENT_FAILURES=2 \
		CURL_TRANSIENT_STATUS=35 \
		INSTALLER_ARGS_LOG="$installer_args_log" \
		INSTALLER_VERSION_LOG="$installer_version_log" \
		"$manual_bin/nr" update

	[ "$status" -eq 0 ] || return 1
	[ -f "$installer_args_log" ] || return 1
	[ "$(cat "$curl_attempt_log")" -eq 3 ] || return 1
	[ "$(cat "$installer_version_log")" = "V$current_version" ]
}

@test "nr update reports unreachable version discovery instead of exiting silently" {
	local manual_bin="$TEST_ROOT/manual/bin"
	local manual_config="$TEST_ROOT/manual/config"
	local fake_bin="$TEST_ROOT/fake-bin"
	local curl_attempt_log="$TEST_ROOT/discovery.attempts"

	mkdir -p "$fake_bin"
	make_manual_nora_install "$manual_bin" "$manual_config" "0.0.1"

	# Every request fails the way a flaky local proxy fails. Version discovery
	# runs inside `latest=$(...)`, so before the fix the nonzero pipeline tripped
	# errexit and killed `nr update` with an empty screen and no diagnosis.
	cat > "$fake_bin/curl" <<'SCRIPT'
#!/usr/bin/env bash
printf 'x\n' >> "$CURL_ATTEMPT_LOG"
exit 28
SCRIPT
	printf '#!/bin/bash\nexit 0\n' > "$fake_bin/sleep"
	chmod +x "$fake_bin/curl" "$fake_bin/sleep"

	run env \
		HOME="$HOME" \
		PATH="$fake_bin:/usr/bin:/bin" \
		CURL_ATTEMPT_LOG="$curl_attempt_log" \
		"$manual_bin/nr" update

	[ "$status" -eq 1 ] || return 1
	[[ "$output" == *"Unable to check for updates"* ]] || return 1
	[[ "$output" == *"https://github.com"* ]] || return 1
	# The bounded retry must not run behind a blank screen.
	[[ "$output" == *"Checking for updates"* ]] || return 1
	# Two endpoints per round, three bounded rounds.
	[ "$(wc -l < "$curl_attempt_log" | tr -d ' ')" -eq 6 ]
}

@test "nr update announces the check before the bounded retry, not after it" {
	local manual_bin="$TEST_ROOT/manual/bin"
	local manual_config="$TEST_ROOT/manual/config"
	local fake_bin="$TEST_ROOT/fake-bin"
	local curl_attempt_log="$TEST_ROOT/announce.attempts"
	local out_file="$TEST_ROOT/announce.out"

	mkdir -p "$fake_bin"
	make_manual_nora_install "$manual_bin" "$manual_config" "0.0.1"
	cat > "$fake_bin/curl" <<'SCRIPT'
#!/usr/bin/env bash
printf 'x\n' >> "$CURL_ATTEMPT_LOG"
exit 28
SCRIPT
	chmod +x "$fake_bin/curl"
	: > "$out_file"
	: > "$curl_attempt_log"

	# Sampled mid-flight on purpose. Asserting the final output cannot tell an
	# announcement before the retry loop from one after it, which is the whole
	# point: three rounds of failing requests behind a blank screen is the
	# "looks hung" report this retry was added for. `sleep` is deliberately not
	# stubbed here, so the resolver's real 1s pause between rounds leaves a wide
	# sampling window.
	env HOME="$HOME" PATH="$fake_bin:/usr/bin:/bin" \
		CURL_ATTEMPT_LOG="$curl_attempt_log" \
		"$manual_bin/nr" update > "$out_file" 2>&1 &
	local update_pid=$!

	local waited=0
	while [[ "$(wc -l < "$curl_attempt_log" 2> /dev/null || echo 0)" -lt 2 ]]; do
		sleep 0.05
		waited=$((waited + 1))
		if [[ "$waited" -gt 200 ]]; then
			break
		fi
	done

	local mid_output
	mid_output=$(cat "$out_file")
	wait "$update_pid" || true

	# Round one is done but the resolver has not finished: the label must already
	# be visible, and the final verdict must not be.
	[[ "$mid_output" == *"Checking for updates"* ]] || return 1
	[[ "$mid_output" != *"Unable to check for updates"* ]]
}

@test "nr update targets the invoked manual install, not another Homebrew nora in PATH" {
	local manual_bin="$TEST_ROOT/manual/bin"
	local manual_config="$TEST_ROOT/manual/config"
	local fake_brew_bin="$TEST_ROOT/homebrew/bin"
	local fake_brew_nora="$TEST_ROOT/homebrew/Cellar/nora/9.9.9/bin/nora"
	local brew_log="$TEST_ROOT/brew.log"
	local installer_args_log="$TEST_ROOT/installer.args"
	local installer_version_log="$TEST_ROOT/installer.version"
	local curl_url_log="$TEST_ROOT/curl.urls"
	local current_version
	local stale_version="0.0.1"

	current_version="$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' "$PROJECT_ROOT/nora" | head -1)"
	make_manual_nora_install "$manual_bin" "$manual_config" "$stale_version"
	make_homebrew_shadow "$fake_brew_bin" "$fake_brew_nora"
	make_update_curl_stub "$fake_brew_bin" "$current_version"
	: > "$brew_log"
	: > "$curl_url_log"

	run env \
		HOME="$HOME" \
		PATH="$fake_brew_bin:/usr/bin:/bin" \
		BREW_LOG="$brew_log" \
		CURL_URL_LOG="$curl_url_log" \
		INSTALLER_ARGS_LOG="$installer_args_log" \
		INSTALLER_VERSION_LOG="$installer_version_log" \
		"$manual_bin/nr" update

	[ "$status" -eq 0 ]
	[ -f "$installer_args_log" ]
	grep -q -- "--prefix" "$installer_args_log"
	grep -q -- "$manual_bin" "$installer_args_log"
	[ "$(cat "$installer_version_log")" = "V$current_version" ]
	grep -q "raw.githubusercontent.com/LaVieNguyenn/nora/V${current_version#V}/install.sh" "$curl_url_log"
	if grep -q "raw.githubusercontent.com/LaVieNguyenn/nora/main/install.sh" "$curl_url_log"; then
		return 1
	fi
	if grep -q '^upgrade nora$' "$brew_log"; then
		return 1
	fi
}

@test "nr update --nightly skips reinstall when the installed commit is current" {
	local manual_bin="$TEST_ROOT/manual/bin"
	local manual_config="$TEST_ROOT/manual/config"
	local fake_bin="$TEST_ROOT/fake-bin"
	local installer_args_log="$TEST_ROOT/installer.args"
	local installer_version_log="$TEST_ROOT/installer.version"
	local curl_url_log="$TEST_ROOT/curl.urls"
	local latest_commit="e31d46faaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

	mkdir -p "$fake_bin"
	make_manual_nora_install "$manual_bin" "$manual_config" "1.41.0"
	make_nightly_update_curl_stub "$fake_bin" "$latest_commit"
	printf 'CHANNEL=nightly\nCOMMIT_HASH=e31d46f\n' > "$manual_config/install_channel"
	: > "$curl_url_log"

	run env \
		HOME="$HOME" \
		PATH="$fake_bin:/usr/bin:/bin" \
		CURL_URL_LOG="$curl_url_log" \
		INSTALLER_ARGS_LOG="$installer_args_log" \
		INSTALLER_VERSION_LOG="$installer_version_log" \
		"$manual_bin/nr" update --nightly

	[ "$status" -eq 0 ]
	[[ "$output" == *"Already on latest nightly, e31d46f"* ]] || return 1
	[ ! -e "$installer_args_log" ]
	grep -q "api.github.com/repos/LaVieNguyenn/nora/commits/main" "$curl_url_log"
	if grep -q "raw.githubusercontent.com/LaVieNguyenn/nora/main/install.sh" "$curl_url_log"; then
		return 1
	fi
}

@test "nr update --nightly --force reinstalls even when the installed commit is current" {
	local manual_bin="$TEST_ROOT/manual/bin"
	local manual_config="$TEST_ROOT/manual/config"
	local fake_bin="$TEST_ROOT/fake-bin"
	local installer_args_log="$TEST_ROOT/installer.args"
	local installer_version_log="$TEST_ROOT/installer.version"
	local curl_url_log="$TEST_ROOT/curl.urls"
	local latest_commit="e31d46faaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

	mkdir -p "$fake_bin"
	make_manual_nora_install "$manual_bin" "$manual_config" "1.41.0"
	make_nightly_update_curl_stub "$fake_bin" "$latest_commit"
	printf 'CHANNEL=nightly\nCOMMIT_HASH=e31d46f\n' > "$manual_config/install_channel"
	: > "$curl_url_log"

	run env \
		HOME="$HOME" \
		PATH="$fake_bin:/usr/bin:/bin" \
		CURL_URL_LOG="$curl_url_log" \
		INSTALLER_ARGS_LOG="$installer_args_log" \
		INSTALLER_VERSION_LOG="$installer_version_log" \
		"$manual_bin/nr" update --nightly --force

	[ "$status" -eq 0 ]
	[ -f "$installer_args_log" ]
	grep -q -- "--prefix" "$installer_args_log"
	[ "$(cat "$installer_version_log")" = "main" ]
	grep -q "raw.githubusercontent.com/LaVieNguyenn/nora/main/install.sh" "$curl_url_log"
}

@test "nr update tells installer to reuse sudo after parent authentication" {
	local manual_bin="$TEST_ROOT/manual/bin"
	local manual_config="$TEST_ROOT/manual/config"
	local fake_bin="$TEST_ROOT/fake-bin"
	local installer_args_log="$TEST_ROOT/installer.args"
	local installer_version_log="$TEST_ROOT/installer.version"
	local installer_sudo_auth_log="$TEST_ROOT/installer.sudo-auth"
	local curl_url_log="$TEST_ROOT/curl.urls"
	local sudo_log="$TEST_ROOT/sudo.log"
	local current_version

	current_version="$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' "$PROJECT_ROOT/nora" | head -1)"
	mkdir -p "$fake_bin"
	make_manual_nora_install "$manual_bin" "$manual_config" "1.41.0"
	make_update_curl_stub "$fake_bin" "$current_version"
	chmod a-w "$manual_bin/nora"
	cat > "$fake_bin/sudo" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SUDO_LOG"
exit 0
SCRIPT
	chmod +x "$fake_bin/sudo"
	: > "$curl_url_log"
	: > "$sudo_log"

	run env \
		HOME="$HOME" \
		NORA_TEST_MODE=0 \
		NORA_TEST_NO_AUTH=0 \
		PATH="$fake_bin:/usr/bin:/bin" \
		CURL_URL_LOG="$curl_url_log" \
		INSTALLER_ARGS_LOG="$installer_args_log" \
		INSTALLER_VERSION_LOG="$installer_version_log" \
		INSTALLER_SUDO_AUTH_LOG="$installer_sudo_auth_log" \
		SUDO_LOG="$sudo_log" \
		"$manual_bin/nr" update --force

	chmod u+w "$manual_bin/nora"

	[ "$status" -eq 0 ]
	[ -f "$installer_sudo_auth_log" ]
	[ "$(cat "$installer_sudo_auth_log")" = "1" ]
	grep -q -- "-n true" "$sudo_log"
	grep -q "raw.githubusercontent.com/LaVieNguyenn/nora/V${current_version#V}/install.sh" "$curl_url_log"
}


@test "nr update keeps Homebrew installs on the Homebrew update path" {
	local fake_brew_bin="$TEST_ROOT/homebrew/bin"
	local fake_brew_nora="$TEST_ROOT/homebrew/Cellar/nora/9.9.9/bin/nora"
	local brew_log="$TEST_ROOT/brew.log"

	make_homebrew_shadow "$fake_brew_bin" "$fake_brew_nora"
	: > "$brew_log"

	run env \
		HOME="$HOME" \
		PATH="$fake_brew_bin:/usr/bin:/bin" \
		BREW_LOG="$brew_log" \
		"$fake_brew_bin/nr" update

	[ "$status" -eq 0 ]
	grep -q '^update$' "$brew_log"
	grep -q '^upgrade nora$' "$brew_log"
}

@test "nr update preserves actionable Homebrew diagnostics on failure (#1247)" {
	local fake_brew_bin="$TEST_ROOT/homebrew/bin"
	local fake_brew_nora="$TEST_ROOT/homebrew/Cellar/nora/9.9.9/bin/nora"
	local brew_log="$TEST_ROOT/brew.log"
	local brew_upgrade_output
	brew_upgrade_output=$'Error: Your Xcode (26.0.1) at /Applications/Xcode.app is too outdated.\nPlease update to Xcode 27.0 (or delete it).\nXcode can be updated from:\n  https://developer.apple.com/download/all/'

	make_homebrew_shadow "$fake_brew_bin" "$fake_brew_nora"
	: > "$brew_log"

	run env \
		HOME="$HOME" \
		PATH="$fake_brew_bin:/usr/bin:/bin" \
		BREW_LOG="$brew_log" \
		BREW_UPGRADE_OUTPUT="$brew_upgrade_output" \
		BREW_UPGRADE_STATUS=1 \
		"$fake_brew_bin/nr" update

	[ "$status" -ne 0 ]
	[[ "$output" == *"Homebrew upgrade failed"* ]] || return 1
	[[ "$output" == *"Please update to Xcode 27.0 (or delete it)."* ]] || return 1
	[[ "$output" == *"https://developer.apple.com/download/all/"* ]]
}

@test "nr update trusts a nonzero Homebrew exit without Error text (#1247)" {
	local fake_brew_bin="$TEST_ROOT/homebrew/bin"
	local fake_brew_nora="$TEST_ROOT/homebrew/Cellar/nora/9.9.9/bin/nora"
	local brew_log="$TEST_ROOT/brew.log"

	make_homebrew_shadow "$fake_brew_bin" "$fake_brew_nora"
	: > "$brew_log"

	run env \
		HOME="$HOME" \
		PATH="$fake_brew_bin:/usr/bin:/bin" \
		BREW_LOG="$brew_log" \
		BREW_UPGRADE_OUTPUT="The upgrade command was interrupted" \
		BREW_UPGRADE_STATUS=124 \
		"$fake_brew_bin/nr" update

	[ "$status" -ne 0 ]
	[[ "$output" == *"Homebrew upgrade failed"* ]] || return 1
	[[ "$output" == *"The upgrade command was interrupted"* ]] || return 1
	[[ "$output" != *"Updated to latest version"* ]]
}

@test "nr update never treats mixed failure output as already installed" {
	local fake_brew_bin="$TEST_ROOT/homebrew/bin"
	local fake_brew_nora="$TEST_ROOT/homebrew/Cellar/nora/9.9.9/bin/nora"
	local brew_log="$TEST_ROOT/brew.log"
	local brew_upgrade_output
	brew_upgrade_output=$'nora 1.48.0 already installed\nError: simulated upgrade failure'

	make_homebrew_shadow "$fake_brew_bin" "$fake_brew_nora"
	: > "$brew_log"

	run env \
		HOME="$HOME" \
		PATH="$fake_brew_bin:/usr/bin:/bin" \
		BREW_LOG="$brew_log" \
		BREW_UPGRADE_OUTPUT="$brew_upgrade_output" \
		BREW_UPGRADE_STATUS=1 \
		"$fake_brew_bin/nr" update

	[ "$status" -ne 0 ]
	[[ "$output" == *"Homebrew upgrade failed"* ]] || return 1
	[[ "$output" == *"Error: simulated upgrade failure"* ]] || return 1
	[[ "$output" != *"Already on latest version"* ]]
}

make_self_heal_curl_stub() {
	local bin_dir="$1"
	local latest_version="$2"
	local heal_mode="$3"
	cat > "$bin_dir/curl" <<SCRIPT
#!/usr/bin/env bash
out=""
url=""
while [[ \$# -gt 0 ]]; do
	case "\$1" in
		-o)
			out="\$2"
			shift 2
			;;
		http*://*)
			url="\$1"
			shift
			;;
		*)
			shift
			;;
	esac
done
[[ -n "\$url" ]] && printf '%s\n' "\$url" >> "\$CURL_URL_LOG"

if [[ -n "\$out" ]]; then
	cat > "\$out" <<'INSTALLER'
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\$INSTALLER_ARGS_LOG"
exit 1
INSTALLER
	exit 0
fi

if [[ "\$url" == *"/main/install.sh"* ]]; then
	if [[ "$heal_mode" == "fail" ]]; then
		exit 22
	fi
	cat <<'HEAL'
#!/usr/bin/env bash
prefix=""
while [[ \$# -gt 0 ]]; do
	case "\$1" in
		--prefix)
			prefix="\$2"
			shift 2
			;;
		*)
			shift
			;;
	esac
done
printf '%s %s\n' "\${NORA_VERSION:-}" "\$prefix" >> "\$HEAL_LOG"
printf '#!/bin/bash\necho "Nora version %s"\n' "\${NORA_VERSION#V}" > "\$prefix/nora.healed"
chmod +x "\$prefix/nora.healed"
mv "\$prefix/nora.healed" "\$prefix/nora"
HEAL
	exit 0
fi

if [[ "\$url" == *"api.github.com"* ]]; then
	printf '{"tag_name":"%s"}\n' "$latest_version"
	exit 0
fi

printf 'VERSION="%s"\n' "$latest_version"
SCRIPT
	chmod +x "$bin_dir/curl"
}

@test "nr update self-heals with a direct reinstall when the staged installer fails (#1297)" {
	local manual_bin="$TEST_ROOT/manual/bin"
	local manual_config="$TEST_ROOT/manual/config"
	local fake_bin="$TEST_ROOT/fake-bin"
	local installer_args_log="$TEST_ROOT/installer.args"
	local heal_log="$TEST_ROOT/heal.log"
	local curl_url_log="$TEST_ROOT/curl.urls"
	local current_version

	current_version="$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' "$PROJECT_ROOT/nora" | head -1)"
	mkdir -p "$fake_bin"
	make_manual_nora_install "$manual_bin" "$manual_config" "0.0.1"
	make_self_heal_curl_stub "$fake_bin" "$current_version" "heal"
	: > "$curl_url_log"
	: > "$installer_args_log"
	: > "$heal_log"

	run env \
		HOME="$HOME" \
		PATH="$fake_bin:/usr/bin:/bin" \
		CURL_URL_LOG="$curl_url_log" \
		INSTALLER_ARGS_LOG="$installer_args_log" \
		HEAL_LOG="$heal_log" \
		"$manual_bin/nr" update

	[ "$status" -eq 0 ] || return 1
	grep -q -- "--update" "$installer_args_log" || return 1
	[[ "$output" == *"Retrying with a direct reinstall"* ]] || return 1
	[[ "$output" == *"Updated to latest version, $current_version"* ]] || return 1
	[ "$(cat "$heal_log")" = "V$current_version $manual_bin" ]
}

@test "nr update prints the manual reinstall command when self-heal fails too" {
	local manual_bin="$TEST_ROOT/manual/bin"
	local manual_config="$TEST_ROOT/manual/config"
	local fake_bin="$TEST_ROOT/fake-bin"
	local installer_args_log="$TEST_ROOT/installer.args"
	local heal_log="$TEST_ROOT/heal.log"
	local curl_url_log="$TEST_ROOT/curl.urls"
	local current_version

	current_version="$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' "$PROJECT_ROOT/nora" | head -1)"
	mkdir -p "$fake_bin"
	make_manual_nora_install "$manual_bin" "$manual_config" "0.0.1"
	make_self_heal_curl_stub "$fake_bin" "$current_version" "fail"
	: > "$curl_url_log"
	: > "$installer_args_log"
	: > "$heal_log"

	run env \
		HOME="$HOME" \
		PATH="$fake_bin:/usr/bin:/bin" \
		CURL_URL_LOG="$curl_url_log" \
		INSTALLER_ARGS_LOG="$installer_args_log" \
		HEAL_LOG="$heal_log" \
		"$manual_bin/nr" update

	[ "$status" -ne 0 ] || return 1
	[[ "$output" == *"Retrying with a direct reinstall"* ]] || return 1
	[[ "$output" == *"Update failed"* ]] || return 1
	[[ "$output" == *"install.sh | bash"* ]]
}
