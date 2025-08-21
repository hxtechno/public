#!/usr/bin/env bash
# get-slides-from-video.bash — download a YouTube webinar, extract slides, build PDF and PPTX
# (c) 2025 H-X Technologies 
# www.h-x.technology
# License: MIT

# Quick Start
# Make it executable:
# chmod +x get-slides-from-video.bash
# Basic example (≤1080p):
# ./get-slides-from-video.bash --url "https://www.youtube.com/watch?v=uEvKjSQ0EMA&t=1687s" --out blockchain_security
# With Firefox cookies for FullHD+:
# ./get-slides-from-video.bash --url "https://www.youtube.com/watch?v=uEvKjSQ0EMA&t=1687s" --cookies-browser firefox --out blockchain_security
# With cookies.txt:
# ./get-slides-from-video.bash --url "URL" --cookies-file /path/cookies.txt --out slides

# Tips
# If the result is <900p, add --cookies-browser firefox or --cookies-file cookies.txt.
# For 4K, raise --max-height 2160.
# For talking-head webinars, crop presentation with `--

set -euo pipefail

# ---------- Default parameters ----------
URL=""
VIDEO_FILE=""
OUT_BASE="slides"
WORKDIR=""
SCENE_THR="0.30"       # slide change detection threshold 0.15..0.5
START_AT=""            # HH:MM:SS
END_AT=""              # HH:MM:SS
CROP=""                # X:Y:W:H for ffmpeg crop
FPS_LIMIT=""           # frame rate after select
HAMMING_THR="6"        # 0..64 similarity threshold for deduplication
KEEP_INTERMEDIATE="no" # yes|no keep intermediate frames
COOKIES_BROWSER=""     # chrome|chromium|opera|brave|firefox
COOKIES_FILE=""        # path to cookies.txt
MAX_HEIGHT="1080"      # max quality 720/1080/1440/2160
MIN_ACCEPT_H="900"     # minimal height, otherwise try another client
PREFER_MP4="yes"       # yes = try MP4 first (no re-mux)
VERBOSE="no"           # yes = verbose logs

usage() {
  cat <<'EOF'
Usage.
  get-slides-from-video.bash --url "https://www.youtube.com/watch?v=ID" [options]
  get-slides-from-video.bash --video path/to/local.mp4                  [options]

Main options.
  --out NAME                base name of output files (default slides)
  --workdir PATH            working folder (default ./slides_work_TIMESTAMP)
  --scene-thr FLOAT         slide change detection threshold (default 0.30)
  --start HH:MM:SS          trim video start
  --end HH:MM:SS            trim video end
  --crop "X:Y:W:H"          crop presentation area
  --fps-limit N             limit frame extraction rate after select
  --hamming N               deduplication threshold (default 6)
  --keep-intermediate yes|no keep raw frames (default no)
  --cookies-browser NAME    chrome|chromium|opera|brave|firefox
  --cookies-file PATH       path to cookies.txt (alternative to --cookies-browser)
  --max-height N            720|1080|1440|2160 (default 1080)
  --min-accept-height N     minimum resolution to accept (default 900)
  --prefer-mp4 yes|no       prioritize MP4 without re-mux (default yes)
  --verbose yes|no          verbose yt-dlp/ffmpeg logs (default no)

Output.
  NAME.pdf, NAME.pptx and folder NAME_frames_dedup with PNG slides.

Examples.
  # up to 1080p max, using Firefox cookies
  get-slides-from-video.bash --url "https://www.youtube.com/watch?v=XXXX" --cookies-browser firefox --out webinar

  # up to 2160p max, local file, crop only presentation area
  get-slides-from-video.bash --video webinar.mkv --crop "100:80:1720:970" --max-height 2160 --out webinar_4k

  # with cookies.txt exported from a browser extension
  get-slides-from-video.bash --url "URL" --cookies-file /path/cookies.txt --out slides
EOF
}

timestamp() { date +"%Y%m%d_%H%M%S"; }

# ---------- Parse arguments ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) URL="${2:-}"; shift 2 ;;
    --video) VIDEO_FILE="${2:-}"; shift 2 ;;
    --out) OUT_BASE="${2:-}"; shift 2 ;;
    --workdir) WORKDIR="${2:-}"; shift 2 ;;
    --scene-thr) SCENE_THR="${2:-}"; shift 2 ;;
    --start) START_AT="${2:-}"; shift 2 ;;
    --end) END_AT="${2:-}"; shift 2 ;;
    --crop) CROP="${2:-}"; shift 2 ;;
    --fps-limit) FPS_LIMIT="${2:-}"; shift 2 ;;
    --hamming) HAMMING_THR="${2:-}"; shift 2 ;;
    --keep-intermediate) KEEP_INTERMEDIATE="${2:-}"; shift 2 ;;
    --cookies-browser) COOKIES_BROWSER="${2:-}"; shift 2 ;;
    --cookies-file) COOKIES_FILE="${2:-}"; shift 2 ;;
    --max-height) MAX_HEIGHT="${2:-}"; shift 2 ;;
    --min-accept-height) MIN_ACCEPT_H="${2:-}"; shift 2 ;;
    --prefer-mp4) PREFER_MP4="${2:-}"; shift 2 ;;
    --verbose) VERBOSE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$URL" && -z "$VIDEO_FILE" ]]; then
  echo "Error. Provide either --url or --video."
  usage; exit 1
fi

if [[ -z "$WORKDIR" ]]; then
  WORKDIR="./slides_work_$(timestamp)"
fi
mkdir -p "$WORKDIR"
WORKDIR="$(cd "$WORKDIR" && pwd)"
OUT_BASE_ABS="$(cd . && pwd)/${OUT_BASE}"

# ---------- Dependency checks ----------
need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "'$1' is required"; exit 1; }; }
need_cmd ffmpeg
need_cmd python3

# ---------- VENV and Python packages ----------
VENV_DIR="${WORKDIR}/.venv"
python3 -m venv "$VENV_DIR"
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
python -m pip -q install --upgrade pip >/dev/null

# Install Pillow, python-pptx, yt-dlp
python - <<'PY'
import sys, subprocess
def ensure(pkg, mod=None):
    mod = mod or pkg.replace('-', '_')
    try:
        __import__(mod)
    except Exception:
        subprocess.check_call([sys.executable, "-m", "pip", "install", pkg])
for pkg,mod in [("Pillow","PIL"), ("python-pptx","pptx"), ("yt-dlp","yt_dlp")]:
    ensure(pkg, mod)
PY

# ---------- Functions ----------
get_wh() {
  local f="$1"
  local line
  line=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$f" 2>/dev/null || true)
  [[ "$line" =~ ^([0-9]+)x([0-9]+)$ ]] && echo "$line" || echo "0x0"
}

log() {
  echo "$@"
}

# ---------- 1. Download video ----------
VID="${VIDEO_FILE}"
if [[ -z "$VID" ]]; then
  log "[1/5] Downloading video in max quality ≤${MAX_HEIGHT}..."
  OUTTPL="${WORKDIR}/webinar.%(ext)s"

  # YouTube player clients. web and tv_embedded often give DASH without SABR with cookies
  YT_CLIENTS=(web tv_embedded android ios tv)

  base_flags=( --ignore-config --force-ipv4 --retries 10 --fragment-retries 10 --concurrent-fragments 5 --no-playlist -o "${OUTTPL}" )
  [[ "$VERBOSE" == "yes" ]] && base_flags=( -v "${base_flags[@]}" )

  # cookies priority: file > browser
  COOKIES_OPTS=()
  if [[ -n "$COOKIES_FILE" ]]; then
    COOKIES_OPTS=( --cookies "$COOKIES_FILE" )
  elif [[ -n "$COOKIES_BROWSER" ]]; then
    COOKIES_OPTS=( --cookies-from-browser "$COOKIES_BROWSER" )
  fi

  got_ok="no"
  for client in "${YT_CLIENTS[@]}"; do
    log "[1/5] Trying client ${client}."
    rm -f "${WORKDIR}/webinar."* 2>/dev/null || true

    if [[ "$PREFER_MP4" == "yes" ]]; then
      # MP4 attempt: AVC + M4A without re-mux
      set +e
      python -m yt_dlp \
        --extractor-args "youtube:player_client=${client}" \
        "${COOKIES_OPTS[@]}" \
        -S "res:${MAX_HEIGHT},res,codec:avc:m4a,fps,br" \
        -f "bv*[height<=${MAX_HEIGHT}][vcodec*=avc1][ext=mp4]+ba[acodec*=mp4a][ext=m4a]/(137+140)" \
        "${base_flags[@]}" "$URL"
      rc=$?
      set -e
      if [[ $rc -eq 0 && -f "${WORKDIR}/webinar.mp4" ]]; then
        VID="${WORKDIR}/webinar.mp4"
      fi
    fi

    if [[ -z "${VID}" || ! -f "${VID}" ]]; then
      # fallback: remux to MKV
      set +e
      python -m yt_dlp \
        --extractor-args "youtube:player_client=${client}" \
        "${COOKIES_OPTS[@]}" \
        -S "res:${MAX_HEIGHT},res,fps,br,codec" \
        -f "bv*[height<=${MAX_HEIGHT}]+ba/best" \
        --remux-video mkv \
        "${base_flags[@]}" "$URL"
      rc=$?
      set -e
      if [[ $rc -eq 0 && -f "${WORKDIR}/webinar.mkv" ]]; then
        VID="${WORKDIR}/webinar.mkv"
      fi
    fi

    if [[ -f "${VID:-/dev/null}" ]]; then
      wh="$(get_wh "$VID")"; vw="${wh%x*}"; vh="${wh#*x}"
      log "[1b] Got ${vw}x${vh}."
      if [[ "$vh" -ge "$MIN_ACCEPT_H" ]]; then
        got_ok="yes"; break
      else
        log "[1b] Too low resolution. Trying another client..."
        VID=""; rm -f "${WORKDIR}/webinar."* 2>/dev/null || true
      fi
    else
      log "[1/5] Download failed on client ${client}. Trying another..."
    fi
  done

  if [[ "$got_ok" != "yes" ]]; then
    echo "Could not get ≥${MIN_ACCEPT_H}p. Try --cookies-file cookies.txt or --cookies-browser firefox and/or --max-height 2160."
    exit 1
  fi
fi

[[ -f "$VID" ]] || { echo "Video file $VID not found"; exit 1; }

# print video params
ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,avg_frame_rate,bit_rate -of default=nw=1 "$VID" || true

# ---------- 2. Extract slide changes ----------
log "[2/5] Extracting slide changes with ffmpeg..."
FRAMES_DIR="${WORKDIR}/frames_raw"; mkdir -p "$FRAMES_DIR"

FILTERS=""
if [[ -n "$CROP" ]]; then
  IFS=':' read -r CX CY CW CH <<< "$CROP"
  FILTERS+="crop=${CW}:${CH}:${CX}:${CY},"
fi
FILTERS+="select='gt(scene\\,${SCENE_THR})'"
if [[ -n "$FPS_LIMIT" ]]; then
  FILTERS+=",fps=${FPS_LIMIT}"
fi

SS_ARGS=(); TO_ARGS=()
[[ -n "$START_AT" ]] && SS_ARGS=( -ss "$START_AT" )
[[ -n "$END_AT"   ]] && TO_ARGS=( -to "$END_AT" )

ffmpeg $([[ "$VERBOSE" == "yes" ]] && echo "" || echo "-hide_banner -loglevel error") \
  "${SS_ARGS[@]}" -i "$VID" "${TO_ARGS[@]}" \
  -vf "$FILTERS" -vsync vfr "${FRAMES_DIR}/slide_%05d.png"

COUNT_RAW=$(ls -1 "${FRAMES_DIR}"/*.png 2>/dev/null | wc -l | tr -d ' ')
[[ "$COUNT_RAW" -gt 0 ]] || { echo "No frames found. Lower --scene-thr, e.g. to 0.20."; exit 1; }
log "Found $COUNT_RAW candidate frames"

# ---------- 3. Deduplicate with aHash ----------
log "[3/5] Deduplicating with aHash, threshold ${HAMMING_THR}..."
FRAMES_DEDUP="${OUT_BASE_ABS}_frames_dedup"; mkdir -p "$FRAMES_DEDUP"

python - "$FRAMES_DIR" "$FRAMES_DEDUP" "$HAMMING_THR" <<'PY'
import sys, os, glob
from PIL import Image

src, dst, thr = sys.argv[1], sys.argv[2], int(sys.argv[3])
os.makedirs(dst, exist_ok=True)

def ahash(img, size=8):
    img = img.convert("L").resize((size, size), Image.BILINEAR)
    px = list(img.getdata()); avg = sum(px)/len(px)
    bits = 0
    for p in px: bits = (bits<<1) | (1 if p >= avg else 0)
    return bits

def hamming(a, b): return (a ^ b).bit_count()

files = sorted(glob.glob(os.path.join(src, "*.png")))
last = None; kept = 0
for f in files:
    try:
        im = Image.open(f).copy()
    except Exception:
        continue
    h = ahash(im)
    if last is None or hamming(h, last) > thr:
        im.save(os.path.join(dst, os.path.basename(f)), "PNG")
        last = h; kept += 1
print(f"KEPT={kept}")
PY

KEPT=$(ls -1 "${FRAMES_DEDUP}"/*.png 2>/dev/null | wc -l | tr -d ' ')
[[ "$KEPT" -gt 0 ]] || { echo "After deduplication empty. Reduce --hamming, e.g. to 4."; exit 1; }
log "Kept $KEPT unique slides"

# ---------- 4. Build PDF ----------
log "[4/5] Building PDF..."
PDF_OUT="${OUT_BASE_ABS}.pdf"
if command -v img2pdf >/dev/null 2>&1; then
  img2pdf "${FRAMES_DEDUP}"/slide_*.png -o "$PDF_OUT"
else
  python - "$FRAMES_DEDUP" "$PDF_OUT" <<'PY'
import sys, os, glob
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
files = sorted(glob.glob(os.path.join(src, "slide_*.png")))
if not files: raise SystemExit("no images")
cover = Image.open(files[0]).convert("RGB")
rest = [Image.open(f).convert("RGB") for f in files[1:]]
cover.save(dst, save_all=True, append_images=rest)
PY
fi
log "PDF saved $PDF_OUT"

# ---------- 5. Build PPTX ----------
log "[5/5] Building PPTX..."
PPTX_OUT="${OUT_BASE_ABS}.pptx"
python - "$FRAMES_DEDUP" "$PPTX_OUT" <<'PY'
import sys, os, glob
from pptx import Presentation
from pptx.util import Inches
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
prs = Presentation()
# 16:9 ~ 1920x1080 @144DPI
prs.slide_width, prs.slide_height = Inches(13.333), Inches(7.5)

files = sorted(glob.glob(os.path.join(src, "slide_*.png")))
if not files: raise SystemExit("no images")

for p in files:
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    with Image.open(p) as im: w, h = im.size
    sw, sh = prs.slide_width, prs.slide_height
    pic_w = sw; pic_h = int(h*(float(pic_w)/float(w)))
    if pic_h > sh:
        pic_h = sh; pic_w = int(w*(float(pic_h)/float(h)))
    left = int((sw - pic_w)/2); top = int((sh - pic_h)/2)
    slide.shapes.add_picture(p, left, top, width=pic_w, height=pic_h)

prs.save(dst)
PY
log "PPTX saved $PPTX_OUT"

# ---------- Cleanup ----------
[[ "$KEEP_INTERMEDIATE" == "yes" ]] || rm -rf "${FRAMES_DIR}"

echo
echo "Done."
echo "Files."
echo "  $PDF_OUT"
echo "  $PPTX_OUT"
echo "Slide images."
echo "  ${FRAMES_DEDUP}"
