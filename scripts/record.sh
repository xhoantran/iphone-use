#!/bin/zsh
# Records the iPhone screen through the running app until Ctrl-C (or `kill`), then writes an MP4.
# Usage: scripts/record.sh demo.mp4 [fps] [device]
set -uo pipefail
zmodload zsh/datetime
OUT="${1:-demo.mp4}"
FPS="${2:-8}"
PORT="${IPHONE_USE_PORT:-7390}"
DEVICE="${3:+&device=$3}"
FRAMES="$(mktemp -d)"
i=0
START=$EPOCHREALTIME

finish() {
  # Play back at the rate frames actually arrived, so the video runs in real time.
  local rate=$(( i / (EPOCHREALTIME - START) ))
  ffmpeg -loglevel error -y -framerate "$rate" -i "$FRAMES/%05d.jpg" \
    -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -pix_fmt yuv420p "$OUT" && echo "wrote $OUT ($i frames)"
  rm -rf "$FRAMES"
  exit 0
}
trap finish INT TERM

while true; do
  if curl -sf "http://127.0.0.1:$PORT/screenshot?maxWidth=590$DEVICE" -o "$FRAMES/$(printf %05d $i).jpg"; then
    i=$((i + 1))
  fi
  sleep $((1.0 / FPS))
done
