#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
eval "$(awk '
    /^function smc_read_hex\(\)/ { capture = 1 }
    capture { print }
    capture && /^}/ { functions += 1; if (functions == 2) exit }
    /^function smc_write_hex\(\)/ { capture = 1 }
' "$repo_root/battery.sh")"
eval "$(sed -n '/^function disable_charging()/,/^}/p' "$repo_root/battery.sh")"

test_dir="$(mktemp -d)"
smc_binary="$test_dir/fake-smc"
state_file="$test_dir/state"
ignore_writes_file="$test_dir/ignore-writes"
printf '00000000\n' >"$state_file"

cleanup() {
    rm -rf "$test_dir"
}
trap cleanup EXIT

cat >"$smc_binary" <<'SCRIPT'
#!/bin/bash
if [[ "$3" == "-w" ]]; then
    if [[ ! -e "$IGNORE_WRITES_FILE" ]]; then
        printf '%s\n' "$4" >"$SMC_STATE_FILE"
    fi
    exit 0
fi
value="$(cat "$SMC_STATE_FILE")"
printf '  %s  [ui32]  0 (bytes %s)\n' "$2" "$value"
SCRIPT
chmod +x "$smc_binary"

export SMC_STATE_FILE="$state_file"
export IGNORE_WRITES_FILE="$ignore_writes_file"

sudo() {
    [[ "${1:-}" == "-n" ]] && shift
    "$@"
}

log() {
    printf '%s\n' "$*" >&2
}

smc_write_hex CHTE 01000000

touch "$ignore_writes_file"
if smc_write_hex CHTE 00000000 2>/dev/null; then
    echo "FAIL: accepted an SMC write whose readback did not change"
    exit 1
fi

smc_supports_tahoe=true
smc_supports_legacy=false
printf '00000000\n' >"$state_file"
if disable_charging 2>/dev/null; then
    echo "FAIL: charging controller swallowed an SMC readback failure"
    exit 1
fi

echo "PASS: SMC writes require matching readback"
