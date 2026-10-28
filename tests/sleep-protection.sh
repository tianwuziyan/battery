#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

extract_function() {
    sed -n "/^function $1()/,/^}/p" "$repo_root/battery.sh"
}

eval "$(extract_function valid_percentage)"
eval "$(extract_function valid_percentage_range)"
eval "$(extract_function handle_sleep_event)"
eval "$(extract_function create_sleep_daemon)"

test_dir="$(mktemp -d)"
sleep_protection_file="$test_dir/enabled"
sleep_pending_file="$test_dir/pending"
maintain_percentage_tracker_file="$test_dir/maintain.percentage"
disabled=0
enabled=0
disable_should_fail=0
battery_level=70
charging_status=enabled
battery_binary=/usr/local/co.palokaj.battery/battery
sleep_watcher_binary=/usr/local/co.palokaj.battery/battery-sleep
sleep_daemon_path="$test_dir/battery-sleep.plist"
logfile="$test_dir/battery.log"

cleanup() {
    rm -rf "$test_dir"
}
trap cleanup EXIT

log() { :; }
disable_charging() {
    (( disable_should_fail == 0 )) || return 1
    disabled=$((disabled + 1))
    charging_status=disabled
}
enable_charging() {
    enabled=$((enabled + 1))
    charging_status=enabled
}
get_battery_percentage() { printf '%s\n' "$battery_level"; }
get_smc_charging_status() { printf '%s\n' "$charging_status"; }
pgrep() { return 0; }
restart_sleep_daemon() { :; }

printf '75\n' >"$maintain_percentage_tracker_file"
handle_sleep_event prepare
[[ "$disabled" == 0 && ! -e "$sleep_pending_file" ]] || {
    echo "FAIL: disabled charging while sleep protection was off"
    exit 1
}

touch "$sleep_protection_file"
handle_sleep_event prepare
[[ "$disabled" == 1 && -e "$sleep_pending_file" ]] || {
    echo "FAIL: did not disable charging before sleep"
    exit 1
}

handle_sleep_event wake
[[ "$enabled" == 1 && ! -e "$sleep_pending_file" ]] || {
    echo "FAIL: did not restore charging below the limit after wake"
    exit 1
}

charging_status=enabled
disable_should_fail=1
if handle_sleep_event prepare; then
    echo "FAIL: accepted a failed pre-sleep charging write"
    exit 1
fi
[[ ! -e "$sleep_pending_file" ]] || {
    echo "FAIL: marked failed sleep protection as applied"
    exit 1
}

create_sleep_daemon
plutil -lint "$sleep_daemon_path" >/dev/null
grep -q '<key>KeepAlive</key>' "$sleep_daemon_path"

rg -q 'kIOMessageSystemWillSleep' "$repo_root/src/battery-sleep.c"
rg -q 'run_battery_event\("prepare"\)' "$repo_root/src/battery-sleep.c"
rg -q 'install .*battery-sleep' "$repo_root/setup.sh"
rg -q 'dist/battery-sleep' "$repo_root/update.sh"

echo "PASS: sleep protection pauses charging and restores maintenance after wake"
