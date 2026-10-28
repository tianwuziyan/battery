#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
eval "$(awk '
    /^function stop_maintenance_processes\(\)/ { capture = 1 }
    capture { print }
    capture && /^}/ { exit }
' "$repo_root/battery.sh")"

test_dir="$(mktemp -d)"
battery_binary="$test_dir/fake.battery"
legacy_pidfile="$test_dir/battery.pid"
cp "$repo_root/tests/fixtures/maintenance-worker.sh" "$battery_binary"
chmod +x "$battery_binary"

/bin/bash "$battery_binary" maintain_synchronous 70 &
first_pid=$!
/bin/bash "$battery_binary" maintain_voltage_synchronous recover &
second_pid=$!
/bin/bash "$battery_binary" status &
unrelated_pid=$!
printf '%s\n' "$second_pid" >"$legacy_pidfile"

cleanup() {
    kill "$first_pid" "$second_pid" "$unrelated_pid" 2>/dev/null || true
    rm -rf "$test_dir"
}
trap cleanup EXIT

stop_maintenance_processes
wait "$first_pid" "$second_pid" 2>/dev/null || true

if kill -0 "$first_pid" 2>/dev/null || kill -0 "$second_pid" 2>/dev/null; then
    echo "FAIL: stale maintenance process survived"
    exit 1
fi

if ! kill -0 "$unrelated_pid" 2>/dev/null; then
    echo "FAIL: unrelated battery process was stopped"
    exit 1
fi

if [[ -e "$legacy_pidfile" ]]; then
    echo "FAIL: stale PID file survived"
    exit 1
fi

echo "PASS: all maintenance processes stopped"
