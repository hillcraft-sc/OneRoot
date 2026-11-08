#!/bin/zsh
# Runs the Linux GTK app headless (Xvfb) against a throwaway fixture home,
# drives it with a small scenario script, and saves PNG screenshots to
# build/shots/<scenario>-<shot>.png. Never touches the real home folder.
#
#   Scripts/linux-ui-check.sh [scenario] [--dark] [--size 1400x900] [--no-build] [--keep-home] [--machine trixie]
#
# A scenario is Scripts/ui-scenarios/<scenario>.txt, one command per line:
#   shot <name>      screenshot the whole screen
#   key <keys>       xdotool key (e.g. ctrl+t, Return, alt+Left)
#   type <text>      type text
#   click <x> <y>    click at screen coordinates
#   dblclick <x> <y>
#   rclick <x> <y>   right-click
#   drag <x1> <y1> <x2> <y2>   press at 1, move in steps, release at 2
#   sleep <seconds>
#   cd <path>        navigate: focus the path bar (ctrl+l), type, Return
#   env VAR=VALUE    (before launch) set an environment variable for the app, e.g. ONEROOT_TEST_COPY_DELAY_MS=2
#   size <w> <h>     resize the app window (a narrow-window check)
#   sh <command>     run a shell command with HOME at the fixture (set up files, e.g. a big one)
#   # comment
# With no scenario it starts the app and takes one "start" shot.
#
# --keep-home reuses the fixture from the last run (settings written by it stay),
# to check that a choice survives a restart.
# The fixture home (Documents, Pictures, Downloads with 400 files, Projects,
# a PNG, text and a zip) is rebuilt on every run under /tmp in the machine.
set -euo pipefail
ROOT=${0:A:h:h}
SCEN=start; KEEP=0; DARK=0; SIZE=1400x900; BUILD=1; MACHINE=trixie
while (( $# )); do
    case $1 in
        --dark) DARK=1 ;;
        --size) SIZE=$2; shift ;;
        --no-build) BUILD=0 ;;
        --keep-home) KEEP=1 ;;
        --machine) MACHINE=$2; shift ;;
        *) SCEN=$1 ;;
    esac
    shift
done
FILE=$ROOT/Scripts/ui-scenarios/$SCEN.txt
[[ $SCEN == start || -f $FILE ]] || { echo "No scenario $FILE"; exit 1 }
mkdir -p "$ROOT/build/shots"
(( BUILD )) && "$ROOT/Scripts/linux-build.sh" $MACHINE --no-test

LC_ALL=C orb -m oneroot-$MACHINE bash -s -- "$ROOT" "$SCEN" "$DARK" "$SIZE" "$KEEP" <<'REMOTE' 2>&1 | grep -v setlocale
set -uo pipefail
ROOT=$1; SCEN=$2; DARK=$3; SIZE=$4; KEEP=$5
BIN=/tmp/oneroot-linux-debug/debug/OneRootLinux
OUT=$ROOT/build/shots
H=/tmp/oneroot-ui-home
if [ "$KEEP" != 1 ]; then rm -rf $H; fi
mkdir -p $H/{Documents,Pictures,Downloads,Projects/alpha/src,Projects/beta,Desktop,.config,.cache,.local/share}
for i in $(seq 1 400); do echo "file $i" > $H/Downloads/download-$(printf %03d $i).txt; done
printf 'Hello from the OneRoot fixture.\nSecond line.\n' > $H/Documents/notes.txt
printf '# Plan\n\n- one\n- two\n' > $H/Documents/plan.md
head -c 300000 /dev/urandom > $H/Documents/random.bin
convert -size 640x400 gradient:'#2a6df4'-'#e8f0ff' $H/Pictures/photo-blue.png 2>/dev/null
convert -size 800x500 plasma:fractal $H/Pictures/photo-plasma.png 2>/dev/null
convert -size 420x560 xc:white -pointsize 40 -fill '#2a6df4' -annotate +40+90 'Hello PDF' -pointsize 22 -fill black -annotate +40+160 'OneRoot fixture page' $H/Documents/sample.pdf 2>/dev/null
echo 'print("hi")' > $H/Projects/alpha/src/main.py
echo 'readme' > $H/Projects/beta/README.md
(cd $H/Projects && tar czf $H/Documents/projects.tar.gz alpha beta)
[ -f $BIN ] || { echo "no debug binary at $BIN (build failed?)"; exit 1; }

export DISPLAY=:77
Xvfb :77 -screen 0 ${SIZE}x24 >/dev/null 2>&1 & XPID=$!
sleep 1
export HOME=$H XDG_CONFIG_HOME=$H/.config XDG_CACHE_HOME=$H/.cache XDG_DATA_HOME=$H/.local/share
export GSK_RENDERER=cairo GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 NO_AT_BRIDGE=1 ONEROOT_TRACE=${ONEROOT_TRACE:-0}
[ "$DARK" = 1 ] && export ADW_DEBUG_COLOR_SCHEME=prefer-dark
if [ "$SCEN" != start ]; then
  while IFS= read -r line; do case $line in 'env '*) export "${line#env }" ;; 'pre '*) (cd $H && eval "${line#pre }") ;; esac; done < $ROOT/Scripts/ui-scenarios/$SCEN.txt
fi
dbus-run-session -- $BIN > /tmp/oneroot-ui.log 2>&1 & APID=$!
for i in $(seq 1 40); do xdotool search --onlyvisible --name . >/dev/null 2>&1 && break; sleep 0.5; done
sleep 2
WID=$(xdotool search --onlyvisible --class OneRoot 2>/dev/null | head -1 || true)
[ -n "$WID" ] && xdotool windowfocus "$WID" 2>/dev/null
shot() { import -window root "$OUT/$SCEN-$1.png"; echo "shot: build/shots/$SCEN-$1.png"; }
if [ "$SCEN" = start ]; then shot start; else
while IFS= read -r line || [ -n "$line" ]; do
  cmd=${line%% *}; arg=${line#* }
  case $cmd in
    ''|'#'*) ;;
    shot) shot "$arg" ;;
    key) xdotool key --delay 80 $arg; sleep 0.6 ;;
    type) xdotool type --delay 40 -- "$arg"; sleep 0.4 ;;
    click) xdotool mousemove ${arg% *} ${arg#* } click 1; sleep 0.6 ;;
    dblclick) xdotool mousemove ${arg% *} ${arg#* } click --repeat 2 --delay 120 1; sleep 0.8 ;;
    rclick) xdotool mousemove ${arg% *} ${arg#* } click 3; sleep 0.6 ;;
    drag) read -r x1 y1 x2 y2 hold <<< "$arg"; xdotool mousemove $x1 $y1 mousedown 1; sleep ${hold:-0}; for s in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do xdotool mousemove $((x1 + (x2 - x1) * s / 20)) $((y1 + (y2 - y1) * s / 20)); sleep 0.03; done; xdotool mouseup 1; sleep 0.8 ;;
    sleep) sleep "$arg" ;;
    env|pre) ;;
    size) xdotool windowsize "$WID" ${arg% *} ${arg#* }; sleep 1 ;;
    sh) (cd $H && eval "$arg") ;;
    cd) xdotool key ctrl+l; sleep 0.3; xdotool type --delay 30 -- "$arg"; xdotool key Return; sleep 1 ;;
    *) echo "unknown command: $line" ;;
  esac
done < $ROOT/Scripts/ui-scenarios/$SCEN.txt
fi
if kill -0 $APID 2>/dev/null; then echo "app: still running"; else echo "app: EXITED (crash?)"; fi
grep -i -E 'critical|assert|fatal|segfault|error|warning' /tmp/oneroot-ui.log | grep -v -E 'xdg-desktop-portal|fuse init|RealtimeKit|Failed to load icon' | head -8
kill $APID 2>/dev/null; kill $XPID 2>/dev/null; wait 2>/dev/null; true
REMOTE
