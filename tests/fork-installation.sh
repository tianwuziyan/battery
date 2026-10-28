#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

if rg -n 'raw\.githubusercontent\.com/actuallymentor/battery|github\.com/actuallymentor/battery/archive' \
    "$repo_root/battery.sh" "$repo_root/setup.sh" "$repo_root/update.sh" \
    "$repo_root/app/modules/battery.js" "$repo_root/README.md"; then
    echo "FAIL: an install or update path still downloads the upstream fork"
    exit 1
fi

if ! rg -q 'sudo -u "\$calling_user" -H "\$binfolder/battery" maintain stop' "$repo_root/setup.sh"; then
	echo "FAIL: setup does not stop workers as the login user with the trusted installed CLI"
    exit 1
fi

if rg -q 'batteryfolder/battery\.sh" maintain stop' "$repo_root/setup.sh"; then
	echo "FAIL: setup executes the uninstalled downloaded CLI"
	exit 1
fi

if ! rg -q 'sudo -u "\$calling_user" -H "\$binfolder/battery" maintain recover' "$repo_root/setup.sh"; then
	echo "FAIL: setup does not restore saved maintenance as the login user"
    exit 1
fi

if ! rg -q "pkill -f '\^/bin/bash /usr/local/co\\\\.palokaj\\\\.battery/battery maintain_" "$repo_root/setup.sh"; then
	echo "FAIL: setup does not remove workers left by older CLI releases"
	exit 1
fi

echo "PASS: fork install/update sources and maintenance handoff are consistent"
