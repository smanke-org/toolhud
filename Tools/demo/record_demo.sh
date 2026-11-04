#!/bin/zsh
# Records the ToolHUD demo video (Debug scenario "demo", Sources/ToolHUD/DemoStage.swift).
#
# Plays the scripted demo in a staged Debug copy on the built-in display and records only that
# copy's windows with ScreenCaptureKit, so nothing else on screen gets in. Buttons are dry runs and
# nothing is saved. The installed ToolHUD is stopped during the take and reopened afterwards.
#
# Needs: a Release app at .build/app/ToolHUD.app, a Debug build (swift build -c debug), ffmpeg,
# Screen Recording permission for the terminal, and the sandbox off.
#
# usage: Tools/demo/record_demo.sh [out.mp4]     (default: ../ToolHUD-demo/ToolHUD-demo.mp4)
set -u
HERE=${0:A:h}
SRC=${HERE:h:h}
WORK="${TMPDIR:-/tmp}/toolhud-demo"
APP="$WORK/ToolHUDDemo.app"
TRACE="$WORK/trace.txt"
RAW="$WORK/raw.mov"
OUT="${1:-${SRC:h}/ToolHUD-demo/ToolHUD-demo.mp4}"
IDENTITY="Developer ID Application: Steve Manke (32CWL275JJ)"
DEBUG_BIN="$(cd "$SRC" && swift build -c debug --show-bin-path)/ToolHUD"

mkdir -p "$WORK" "${OUT:h}"
[ -f "$DEBUG_BIN" ] || { echo "no Debug build at $DEBUG_BIN"; exit 1; }
[ -d "$SRC/.build/app/ToolHUD.app" ] || { echo "no app bundle at .build/app/ToolHUD.app"; exit 1; }

# The recorder: rebuilt when its source changes.
REC="$WORK/recorder"
if [ ! -x "$REC" ] || [ "$HERE/recorder.swift" -nt "$REC" ]; then
  swiftc -O -o "$REC" "$HERE/recorder.swift" || exit 1
fi

# A fresh staged copy (a new path each time would serve a stale Info.plist; this one is deleted).
rm -rf "$APP" "$TRACE" "$TRACE.crop" "$RAW"
cp -R "$SRC/.build/app/ToolHUD.app" "$APP"
cp "$DEBUG_BIN" "$APP/Contents/MacOS/ToolHUD"
codesign -d --entitlements :- "$SRC/.build/app/ToolHUD.app" > "$WORK/ent.plist" 2>/dev/null
codesign --force --options runtime --entitlements "$WORK/ent.plist" --sign "$IDENTITY" "$APP" || exit 1

# Stop the installed app with SIGTERM (AppleScript quit would ask "Ask before quitting").
INSTALLED=0
if pgrep -f "/Applications/ToolHUD.app/Contents/MacOS/ToolHUD" >/dev/null; then
  INSTALLED=1; pkill -TERM -f "/Applications/ToolHUD.app/Contents/MacOS/ToolHUD"; sleep 1.5
fi

open -n -g --env TOOLHUD_DEBUG_SCENARIO=demo --env TOOLHUD_DEBUG_DRY_RUN=1 --env TOOLHUD_DEBUG_TRACE="$TRACE" \
  --env TOOLHUD_DEBUG_APPEARANCE=dark --env TOOLHUD_DEBUG_DEMO_LEAD=1.5 "$APP"
for i in {1..100}; do /usr/bin/grep -q "stage ready" "$TRACE" 2>/dev/null && break; sleep 0.2; done
PID=$(pgrep -f "$APP/Contents/MacOS/ToolHUD" | head -1)
echo "pid=$PID crop=$(cat "$TRACE.crop" 2>/dev/null)"
OK=0
if [ -n "$PID" ] && [ -f "$TRACE.crop" ]; then
  "$REC" "$PID" ${=$(cat "$TRACE.crop")} "$RAW" && OK=1
else
  echo "stage never came up"; [ -n "$PID" ] && kill "$PID"
fi

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null
rm -rf "$APP"
[ $INSTALLED = 1 ] && open -g /Applications/ToolHUD.app
tail -5 "$TRACE"
[ $OK = 1 ] || exit 1

# Edit: constant 60 fps, trim the lead-in and the tail, 1080p, fades, no audio.
ffmpeg -y -loglevel error -i "$RAW" -ss 1.0 -to 90.6 \
  -vf "fps=60,scale=1920:1080:flags=lanczos,fade=t=in:st=0:d=0.4,fade=t=out:st=88.9:d=0.7" \
  -an -c:v libx264 -preset slow -crf 19 -pix_fmt yuv420p -movflags +faststart "$OUT" || exit 1
ffmpeg -y -loglevel error -ss 12 -i "$OUT" -frames:v 1 -q:v 2 "${OUT:r}-poster.jpg"
echo "wrote $OUT"
