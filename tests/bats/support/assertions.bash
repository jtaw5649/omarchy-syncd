assert_output_contains() {
	local needle="$1"
	local actual="${output:-}"
	[[ "$actual" == *"$needle"* ]] || {
		echo "expected output to contain: $needle" >&2
		echo "actual output: $actual" >&2
		return 1
	}
}

assert_file_exists() {
	local path="$1"
	[[ -e "$path" ]] || {
		echo "expected file to exist: $path" >&2
		return 1
	}
}

assert_dir_exists() {
	local path="$1"
	[[ -d "$path" ]] || {
		echo "expected directory to exist: $path" >&2
		return 1
	}
}

assert_file_contains() {
	local path="$1"
	local needle="$2"
	[[ -f "$path" ]] || {
		echo "expected file to exist: $path" >&2
		return 1
	}
	if ! grep -Fq "$needle" "$path"; then
		echo "expected $path to contain: $needle" >&2
		return 1
	fi
}

assert_file_not_exists() {
	local path="$1"
	[[ ! -e "$path" ]] || {
		echo "expected file to be absent: $path" >&2
		return 1
	}
}
