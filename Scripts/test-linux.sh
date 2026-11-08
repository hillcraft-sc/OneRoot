#!/bin/zsh
# Runs OneRootCore's tests (Package.swift: the shared, platform-neutral
# code) on Linux, in the OrbStack machines set up for the Linux port
# (#60): Ubuntu 24.04, Debian 12, Debian 13, and Arch. Each needs Swift
# installed with swiftly (see issue #77 for the setup, including Arch's
# libncurses/libxml2-legacy workarounds). Machines that don't exist are
# skipped.
#
#   Scripts/test-linux.sh            all machines
#   Scripts/test-linux.sh ubuntu     just one (ubuntu, debian, trixie, arch)
set -uo pipefail
ROOT=${0:A:h:h}
MACHINES=("$@")
(( ${#MACHINES} )) || MACHINES=(ubuntu debian trixie arch)
FAILED=0
for name in $MACHINES; do
    machine=oneroot-$name
    if ! orb list 2>/dev/null | awk "{print \$1}" | grep -qx "$machine"; then
        echo "– $machine: not set up, skipped"
        continue
    fi
    out=$(LC_ALL=C orb -m $machine bash -lc ". ~/.local/share/swiftly/env.sh 2>/dev/null; cd '$ROOT' && swift test --scratch-path /tmp/oneroot-core 2>&1" 2>/dev/null | grep -v setlocale | sed 's/\x1b\[[0-9;]*m//g')
    summary=$(echo "$out" | grep -E "Executed [0-9]+ tests" | tail -1 | sed 's/^[[:space:]]*//')
    if echo "$out" | grep -qE "with [1-9][0-9]* failures?|error:"; then
        echo "✗ $machine: ${summary:-build failed}"
        echo "$out" | grep -E "error:|failed" | head -10
        FAILED=1
    else
        echo "✓ $machine: $summary"
    fi
done
exit $FAILED
