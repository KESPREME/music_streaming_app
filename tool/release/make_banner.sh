#!/usr/bin/env bash
# Draws the release banner when the repo does not ship its own
# (release/images/banner.png).
#
#   tool/release/make_banner.sh <version> <output.png>
#
# 1600x800: a deep violet-to-black gradient (reads well on the app's pure-black
# theme), the app mark, the name, and the version. Uses ImageMagick, which is on
# GitHub's ubuntu runners; exits non-zero (and the workflow carries on without a
# banner) if it is not.
set -euo pipefail

version="${1:?version}"
out="${2:?output}"
mark="assets/images/mine_music_mark.png"

if command -v magick >/dev/null 2>&1; then IM=(magick); else IM=(convert); fi
command -v "${IM[0]}" >/dev/null 2>&1 || { echo "ImageMagick not found" >&2; exit 1; }

font_args=()
for f in "DejaVu-Sans-Bold" "Liberation-Sans-Bold" "Helvetica-Bold"; do
  if "${IM[@]}" -list font 2>/dev/null | grep -q "Font: $f\$"; then font_args=(-font "$f"); break; fi
done

args=(-size 1600x800 "gradient:#2b1247-#000000")

if [ -f "$mark" ]; then
  args+=( \( "$mark" -resize 230x230 \) -gravity center -geometry +0-150 -composite )
fi

args+=(
  "${font_args[@]}"
  -gravity center
  -fill white -pointsize 104 -annotate +0+70 "Mine Music"
  -fill "#cdb8f0" -pointsize 46 -annotate +0+165 "Version ${version}"
  "$out"
)

"${IM[@]}" "${args[@]}"
echo "banner written to $out"
