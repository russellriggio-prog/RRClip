#!/usr/bin/env bash
# GTA 6 Clipper setup for Linux (e.g. a Claude Code cloud session).
# Installs what's missing and says when it's ready. Safe to re-run any time.
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENV="$SKILL_DIR/.venv"
MODELS="$SKILL_DIR/models"
BIN="$SKILL_DIR/.bin"
mkdir -p "$MODELS" "$BIN"
ok()   { printf "  [ok]      %s\n" "$1"; }
inst() { printf "  [install] %s\n" "$1"; }
fail() { printf "  [MISSING] %s\n" "$1"; FAILED=1; }
FAILED=0

echo "GTA 6 Clipper setup (Linux)"

# 1. System tools: ffmpeg, plus a compiler and cmake to build whisper.cpp
need=()
command -v ffmpeg >/dev/null 2>&1 || need+=(ffmpeg)
command -v cmake  >/dev/null 2>&1 || need+=(cmake)
command -v g++    >/dev/null 2>&1 || need+=(build-essential)
command -v git    >/dev/null 2>&1 || need+=(git)
if (( ${#need[@]} )); then
  inst "${need[*]}"
  SUDO=""; [[ $(id -u) -ne 0 ]] && SUDO="sudo"
  $SUDO apt-get update -qq >/dev/null 2>&1; $SUDO apt-get install -y -qq "${need[@]}" >/dev/null 2>&1
fi
for b in ffmpeg cmake g++ git; do command -v $b >/dev/null 2>&1 && ok "$b" || fail "$b"; done

# 2. whisper.cpp (speech -> text), built from source into the skill folder
if [[ -x "$BIN/whisper-cli" ]] || command -v whisper-cli >/dev/null 2>&1; then ok "whisper-cli"; else
  inst "whisper.cpp (building, takes a few minutes)"
  SRC="$SKILL_DIR/.whisper-src"
  rm -rf "$SRC"
  if git clone -q --depth 1 https://github.com/ggml-org/whisper.cpp "$SRC" \
     && cmake -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_TESTS=OFF >/dev/null \
     && cmake --build "$SRC/build" -j"$(nproc)" --target whisper-cli >/dev/null; then
    cp "$SRC/build/bin/whisper-cli" "$BIN/whisper-cli" && rm -rf "$SRC" && ok "whisper-cli"
  else fail "whisper.cpp build"; fi
fi

# 3. Python environment: yt-dlp (always latest), OpenCV (facecam finder), Pillow (captions)
UV="$(command -v uv || echo "$HOME/.local/bin/uv")"
if [[ ! -x "$UV" ]]; then inst "uv"; python3 -m pip install -q uv >/dev/null 2>&1; UV="$(command -v uv || echo "$HOME/.local/bin/uv")"; fi
if [[ ! -x "$VENV/bin/python" ]]; then inst "Python environment"; "$UV" venv -q --python 3.12 "$VENV" >/dev/null 2>&1 || "$UV" venv -q "$VENV" >/dev/null 2>&1; fi
"$UV" pip install --python "$VENV/bin/python" -q -U "yt-dlp[default]" opencv-python-headless pillow numpy >/dev/null 2>&1 \
  && ok "Python packages (yt-dlp, opencv, pillow, numpy)" || fail "Python packages"

# 4. Whisper model (~465 MB)
WHISPER_MODEL="$MODELS/ggml-small.en.bin"
if [[ ! -s "$WHISPER_MODEL" ]]; then
  inst "Whisper small.en model (~465 MB)"
  curl -fL -s -o "$WHISPER_MODEL" https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin || { rm -f "$WHISPER_MODEL"; fail "whisper model"; }
fi
[[ -s "$WHISPER_MODEL" ]] && ok "Whisper model"

# 5. Face detector (YuNet, ~230 KB) used to find the facecam box
YUNET="$MODELS/face_detection_yunet_2023mar.onnx"
if [[ ! -s "$YUNET" ]]; then
  inst "YuNet face detector"
  curl -fL -s -o "$YUNET" https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx \
    || curl -fL -s -o "$YUNET" https://huggingface.co/opencv/face_detection_yunet/resolve/main/face_detection_yunet_2023mar.onnx \
    || rm -f "$YUNET"
fi
[[ -s "$YUNET" ]] && ok "Face detector" || fail "Face detector"

# 6. Caption font: a heavy sans font
FONT=""
for f in /usr/share/fonts/opentype/inter/Inter-Black.otf /usr/share/fonts/opentype/inter/Inter-ExtraBold.otf \
         /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf /usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf; do
  [[ -f "$f" ]] && FONT="$f" && break; done
if [[ -z "$FONT" ]]; then
  inst "fonts-dejavu-core"; SUDO=""; [[ $(id -u) -ne 0 ]] && SUDO="sudo"
  $SUDO apt-get install -y -qq fonts-dejavu-core >/dev/null 2>&1
  [[ -f /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf ]] && FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf
fi
[[ -n "$FONT" ]] && ok "Caption font ($(basename "$FONT"))" || fail "Caption font"

cat > "$SKILL_DIR/config.json" <<EOF
{"whisper_model": "$WHISPER_MODEL", "yunet_model": "$YUNET", "whisper_cli": "$BIN/whisper-cli", "font": "$FONT"}
EOF

if [[ $FAILED -eq 0 ]]; then
  date > "$SKILL_DIR/.ready"
  echo; echo "READY. Say: clip this stream <kick link>"
else
  rm -f "$SKILL_DIR/.ready"; echo; echo "NOT READY: fix the [MISSING] items above and re-run setup."; exit 1
fi
