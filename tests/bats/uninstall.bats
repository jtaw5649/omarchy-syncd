#!/usr/bin/env bats

load './support/assertions'

setup() {
	PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export PROJECT_ROOT

	TMP_DIR="$(mktemp -d)"
	export TMP_DIR

	export HOME="$TMP_DIR/home"
	mkdir -p "$HOME/.config/omarchy-syncd"
	echo '{}' >"$HOME/.config/omarchy-syncd/symlinks.json"

	export OMARCHY_SYNCD_ROOT="$PROJECT_ROOT"
	export OMARCHY_SYNCD_INSTALL_PREFIX="$TMP_DIR/bin"
	export OMARCHY_SYNCD_CONFIG_PATH="$TMP_DIR/config.toml"
	export OMARCHY_SYNCD_STATE_DIR="$TMP_DIR/state"
	export OMARCHY_SYNCD_LOG_PATH="$TMP_DIR/activity.log"
	export OMARCHY_SYNCD_ICON_DIR="$TMP_DIR/icons"

	mkdir -p "$OMARCHY_SYNCD_STATE_DIR/runtime/bin"
	mkdir -p "$OMARCHY_SYNCD_ICON_DIR"
	printf 'icon' >"$OMARCHY_SYNCD_ICON_DIR/omarchy-syncd.png"

	mkdir -p "$HOME/.config/elephant/menus"
	printf '# Managed by omarchy-syncd' >"$HOME/.config/elephant/menus/omarchy-syncd.toml"

	mkdir -p "$OMARCHY_SYNCD_INSTALL_PREFIX"
	cp "$PROJECT_ROOT/bin/omarchy-syncd" "$OMARCHY_SYNCD_INSTALL_PREFIX/omarchy-syncd"
	touch "$OMARCHY_SYNCD_INSTALL_PREFIX/omarchy-syncd-backup"
	touch "$OMARCHY_SYNCD_INSTALL_PREFIX/omarchy-syncd-backup.sh"

	cat <<'EOF_CFG' >"$OMARCHY_SYNCD_CONFIG_PATH"
[repo]
url = "git@example.com/repo.git"
branch = "main"

[files]
paths = []
bundles = []
EOF_CFG

	STUB_DIR="$TMP_DIR/stub"
	mkdir -p "$STUB_DIR"

	cat >"$STUB_DIR/pgrep" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"elephant"* ]]; then
	exit 0
fi
command -p pgrep "$@"
EOF

	cat >"$STUB_DIR/pkill" <<EOF
#!/usr/bin/env bash
echo "\$@" >>"$TMP_DIR/pkill.log"
exit 0
EOF

	cat >"$STUB_DIR/hyprctl" <<EOF
#!/usr/bin/env bash
echo "\$@" >>"$TMP_DIR/hyprctl.log"
exit 0
EOF

	chmod +x "$STUB_DIR/pgrep" "$STUB_DIR/pkill" "$STUB_DIR/hyprctl"

	PATH="$STUB_DIR:$PROJECT_ROOT/bin:$PATH"
}

teardown() {
	rm -rf "$TMP_DIR"
}

@test "uninstall performs full cleanup" {
	run omarchy-syncd uninstall --yes

	[ "$status" -eq 0 ]
	assert_output_contains "has been uninstalled"
	assert_file_not_exists "$OMARCHY_SYNCD_INSTALL_PREFIX/omarchy-syncd"
	assert_file_not_exists "$OMARCHY_SYNCD_INSTALL_PREFIX/omarchy-syncd-backup"
	assert_file_not_exists "$OMARCHY_SYNCD_CONFIG_PATH"
	assert_file_not_exists "$HOME/.config/omarchy-syncd"
	assert_file_not_exists "$HOME/.config/elephant/menus/omarchy-syncd.toml"
	assert_file_not_exists "$OMARCHY_SYNCD_ICON_DIR/omarchy-syncd.png"
	assert_file_not_exists "$OMARCHY_SYNCD_STATE_DIR"

	assert_file_exists "$TMP_DIR/pkill.log"
	run cat "$TMP_DIR/pkill.log"
	[ "$status" -eq 0 ]
	assert_output_contains "-x elephant"

	assert_file_exists "$TMP_DIR/hyprctl.log"
	run cat "$TMP_DIR/hyprctl.log"
	[ "$status" -eq 0 ]
	assert_output_contains "reload"
}

@test "uninstall cancels without --yes" {
	run omarchy-syncd uninstall <<<"n"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Uninstall cancelled"* ]]
}
