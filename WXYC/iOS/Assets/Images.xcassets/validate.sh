#!/usr/bin/env bash
set -euo pipefail

# Configurable limits
MAX_DIMENSION=4096        # Max width or height in pixels
MAX_BYTES=$((10 * 1024 * 1024))  # 10 MB

# Prefer `magick identify`, fall back to `identify`
if command -v magick >/dev/null 2>&1; then
  ID_CMD="magick identify"
elif command -v identify >/dev/null 2>&1; then
  ID_CMD="identify"
else
  echo "Error: ImageMagick (magick/identify) is required." >&2
  exit 1
fi

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 file1.png [file2.png ...]"
  exit 1
fi

# Cross-platform stat (macOS + Linux)
file_size() {
  local f="$1"
  if stat -f%z "$f" >/dev/null 2>&1; then
    stat -f%z "$f"
  else
    stat -c%s "$f"
  fi
}

for f in "$@"; do
  if [ ! -f "$f" ]; then
    echo "SKIP: $f (not a file)"
    continue
  fi

  echo "Checking: $f"

  # Basic properties
  props=$($ID_CMD -format '%m %w %h %[depth] %[colorspace]\n' "$f") || {
    echo "  FAIL: Could not read image (corrupt or unsupported)."
    continue
  }

  format=$(echo "$props" | awk '{print $1}')
  width=$(echo "$props" | awk '{print $2}')
  height=$(echo "$props" | awk '{print $3}')
  depth=$(echo "$props" | awk '{print $4}')
  colorspace=$(echo "$props" | awk '{print $5}')

  size_bytes=$(file_size "$f")

  issues=()

  # 1. Must be PNG
  if [ "$format" != "PNG" ]; then
    issues+=("Not a PNG (format = $format)")
  fi

  # 2. Dimensions
  if [ "$width" -gt "$MAX_DIMENSION" ] || [ "$height" -gt "$MAX_DIMENSION" ]; then
    issues+=("Dimensions ${width}x${height} exceed max ${MAX_DIMENSION}px")
  fi

  # 3. Bit depth
  if [ "$depth" -ne 8 ]; then
    issues+=("Bit depth is ${depth}, expected 8")
  fi

  # 4. Colorspace
  cs_lower=$(echo "$colorspace" | tr 'A-Z' 'a-z')
  if [ "$cs_lower" != "srgb" ]; then
    issues+=("Colorspace is '${colorspace}', expected sRGB")
  fi

  # 5. File size
  if [ "$size_bytes" -gt "$MAX_BYTES" ]; then
    issues+=("File size is ${size_bytes} bytes (> ${MAX_BYTES})")
  fi

  # 6. ICC profile / XMP chunks
  verbose=$($ID_CMD -verbose "$f" 2>/dev/null || true)

  if echo "$verbose" | grep -q 'Profile-icc'; then
    issues+=("Has embedded ICC profile")
  fi

  if echo "$verbose" | grep -qi 'xmp:'; then
    issues+=("Contains XMP metadata")
  fi

  # (Optional) Alpha channel warning
  if echo "$verbose" | grep -q 'matte: true'; then
    issues+=("Has alpha channel (may be fine, but check your design)")
  fi

  if [ "${#issues[@]}" -eq 0 ]; then
    echo "  OK: Looks launch-screen safe ✅"
  else
    echo "  FAIL:"
    for issue in "${issues[@]}"; do
      echo "    - $issue"
    done
  fi

  echo
done

