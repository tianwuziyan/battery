#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
eval "$(awk '
    /^function restart_maintenance_daemon\(\)/ { capture = 1 }
    capture { print }
    capture && /^}/ { exit }
' "$repo_root/battery.sh")"

test_dir="$(mktemp -d)"
daemon_path="$test_dir/battery.plist"
calls="$test_dir/launchctl.calls"
print_attempt_file="$test_dir/print-attempts"
launchctl_running_after=3
USER="$(id -un)"
touch "$daemon_path"
printf '0\n' >"$print_attempt_file"

cleanup() {
    rm -rf "$test_dir"
}
trap cleanup EXIT

log() {
    printf '%s\n' "$*" >&2
}

launchctl() {
    printf '%s\n' "$*" >>"$calls"
    if [[ "$1" == "print" ]]; then
        attempt="$(cat "$print_attempt_file")"
        attempt=$((attempt + 1))
        printf '%s\n' "$attempt" >"$print_attempt_file"
        if (( launchctl_running_after > 0 && attempt >= launchctl_running_after )); then
            printf '%s\n' "state = running"
        else
            printf '%s\n' "state = waiting"
        fi
    fi
}

sleep() {
    :
}

restart_maintenance_daemon

uid="$(id -u "$USER")"
expected="bootout gui/$uid/com.battery.app
enable gui/$uid/com.battery.app
bootstrap gui/$uid $daemon_path
kickstart gui/$uid/com.battery.app
print gui/$uid/com.battery.app
print gui/$uid/com.battery.app
print gui/$uid/com.battery.app"

if [[ "$(cat "$calls")" != "$expected" ]]; then
    echo "FAIL: launchd lifecycle did not use bootout/bootstrap/kickstart/verification"
    diff -u <(printf '%s\n' "$expected") "$calls" || true
    exit 1
fi

maintain_block="$(sed -n '/^if \[\[ "$action" == "maintain" \]\]; then/,/^fi$/p' "$repo_root/battery.sh")"
if grep -q "nohup.*maintain_.*synchronous" <<<"$maintain_block"; then
    echo "FAIL: maintain still launches an unmanaged worker"
    exit 1
fi

launchctl_running_after=0
printf '0\n' >"$print_attempt_file"
if restart_maintenance_daemon 2>/dev/null; then
    echo "FAIL: launchd startup verification accepted a stopped worker"
    exit 1
fi

if [[ "$(cat "$print_attempt_file")" != "10" ]]; then
    echo "FAIL: launchd startup verification did not use its bounded retry window"
    exit 1
fi

echo "PASS: launchd owns and verifies the maintenance worker"
