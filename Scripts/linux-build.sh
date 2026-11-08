#!/bin/zsh
# Incremental debug build (and the Linux UI-logic tests) of the GTK app in an
# OrbStack machine. Fast loop for Linux UI work.
#
#   Scripts/linux-build.sh [machine-suffix] [--no-test]     default: trixie
#
# Prints only errors, warnings of interest and the result. The scratch path is
# kept between runs so builds are incremental. For the shared core's tests on
# every distro use Scripts/test-linux.sh.
set -euo pipefail
SUFFIX=trixie; NOTEST=
for arg in "$@"; do
    case $arg in
        --no-test) NOTEST=1 ;;
        *) SUFFIX=$arg ;;
    esac
done
MACHINE=oneroot-$SUFFIX
ROOT=${0:A:h:h}
SWIFT_BUILD_EXTRA=${SWIFT_BUILD_EXTRA:-}

LC_ALL=C orb -m $MACHINE bash -lc ". ~/.local/share/swiftly/env.sh 2>/dev/null; set -o pipefail
cd '$ROOT/Linux'
swift build $SWIFT_BUILD_EXTRA --scratch-path /tmp/oneroot-linux-debug 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'error:|warning: (var|unused|unre)|Build complete|Compiling.*(failed)' | sort -u | head -40
if [ -z '$NOTEST' ]; then
  swift test $SWIFT_BUILD_EXTRA --scratch-path /tmp/oneroot-linux-debug 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'error:|Executed|failed' | sort -u | tail -6
fi" 2>&1 | grep -v setlocale
