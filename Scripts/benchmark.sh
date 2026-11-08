#!/bin/zsh
# The large-folder performance check (#72): times listing, opening,
# sorting, and filtering a 50,000-file folder, the flat view, Compare
# Panes, and Find Duplicates on 20,000-file trees, each against a generous
# budget, and adds the timings to Benchmarks/history.csv so a slowdown
# shows up release to release.
#
#   Scripts/benchmark.sh
#
# Run by Scripts/release.sh before archiving (SKIP_BENCHMARK=1 to skip).
set -euo pipefail
ROOT=${0:A:h:h}
cd "$ROOT"
OUT=$(mktemp -t oneroot-benchmark).json
DD=$(mktemp -d)
trap 'rm -rf "$DD" "$OUT"' EXIT

echo "▸ Running the large-folder benchmark (a minute or two)"
if ! TEST_RUNNER_ONEROOT_BENCHMARK=1 TEST_RUNNER_ONEROOT_BENCHMARK_OUT="$OUT" \
    xcodebuild -project OneRoot.xcodeproj -scheme OneRoot -configuration Debug -derivedDataPath "$DD" \
    test -only-testing:OneRootTests/LargeFolderBenchmarkTests 2>&1 | tee "$DD/log" | grep -E "^BENCH" ; then
    :
fi
if ! grep -q "TEST SUCCEEDED" "$DD/log"; then
    grep -E "error:|failed" "$DD/log" | head -20
    echo "✗ Benchmark failed: something is slower than its budget (or the test didn't run)."
    exit 1
fi

VERSION=$(xcodebuild -project OneRoot.xcodeproj -scheme OneRoot -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ MARKETING_VERSION =/ { print $2; exit }')
HISTORY=$ROOT/Benchmarks/history.csv
python3 -I - "$OUT" "$HISTORY" "$VERSION" "$(git rev-parse --short HEAD)" "$(sysctl -n hw.model)" <<'PY'
import csv, json, os, sys, datetime
out, history, version, sha, model = sys.argv[1:6]
results = json.load(open(out))
names = [r["name"] for r in results]
exists = os.path.exists(history)
with open(history, "a", newline="") as f:
    w = csv.writer(f)
    if not exists:
        w.writerow(["date", "version", "commit", "mac"] + names)
    w.writerow([datetime.date.today().isoformat(), version, sha, model] + [f'{r["seconds"]:.3f}' for r in results])
print(f"✓ All within budget; added to {os.path.relpath(history)}")
PY
