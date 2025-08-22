# H-X YouTube Video Slide Extractor

A command‑line tool that downloads YouTube webinars (and other videos), detects slide changes, and exports them as high‑quality **PNG images, PDF, and PowerPoint (PPTX)** files.  
Perfect for creating slide decks from recorded conferences, webinars, or online courses.

---

## ✨ Features
- 📥 Downloads videos from YouTube (supports cookies to access higher resolutions).
- 🖼 Detects scene/slide changes automatically using `ffmpeg`.
- 🔍 Deduplicates frames with perceptual hashing (aHash) to keep only unique slides.
- 📄 Exports slides as:
  - Individual PNG images
  - A compiled PDF
  - A PowerPoint (PPTX) deck with each slide centered
- ⚙️ Configurable:
  - Target max resolution (720p / 1080p / 1440p / 2160p)
  - Scene detection sensitivity
  - Cropping area (focus only on the presentation window)
  - FPS limits, deduplication thresholds, verbosity, and more

---

## 🚀 Quick Start

### 1. Make the script executable
```bash
chmod +x get-slides-from-video.bash
```

### 2. Basic usage (≤1080p)
```bash
./get-slides-from-video.bash \
  --url "https://www.youtube.com/watch?v=uEvKjSQ0EMA&t=1687s" \
  --out blockchain_security
```

### 3. With Firefox cookies for FullHD+
```bash
./get-slides-from-video.bash \
  --url "https://www.youtube.com/watch?v=uEvKjSQ0EMA&t=1687s" \
  --cookies-browser firefox \
  --out blockchain_security
```

### 4. With cookies.txt
```bash
./get-slides-from-video.bash \
  --url "URL" \
  --cookies-file /path/cookies.txt \
  --out slides
```

### 5. Local video file (no download)
```bash
./get-slides-from-video.bash \
  --video path/to/webinar.mkv \
  --out my_slides
```

---

## 🧰 CLI Options

All options (with defaults):

```text
--url "https://www.youtube.com/watch?v=ID"   # Video URL to download
--video path/to/local.mp4                    # Use a local file instead of downloading
--out NAME                                   # Base name of output files (default: slides)
--workdir PATH                               # Working directory (default: ./slides_work_TIMESTAMP)

--max-height N                               # 720|1080|1440|2160 (default: 1080)
--min-accept-height N                        # Minimum height to accept (default: 900)
--prefer-mp4 yes|no                          # Prefer MP4 w/o re-encode (default: yes)

--cookies-browser chrome|chromium|opera|brave|firefox
--cookies-file /path/to/cookies.txt          # Alternative to --cookies-browser

--scene-thr FLOAT                            # Slide change threshold (default: 0.30)
--start HH:MM:SS                             # Trim video start
--end HH:MM:SS                               # Trim video end
--crop "X:Y:W:H"                             # Crop region (pixels)
--fps-limit N                                # Cap frame extraction after select
--hamming N                                  # aHash dedup threshold (default: 6)
--keep-intermediate yes|no                   # Keep raw frames (default: no)

--verbose yes|no                             # Verbose yt-dlp/ffmpeg logs (default: no)
```

**Typical values**  
- `--scene-thr`: 0.20–0.35 (lower = more slides, higher = fewer).  
- `--hamming`: 4–10 (higher = remove more near-duplicates).  
- `--crop`: Use when the video alternates between speaker and slides.

---

## 📂 Output

After running you will get:

- `NAME.pdf` — all slides in a single PDF.
- `NAME.pptx` — a PowerPoint deck, one image per slide, centered.
- `NAME_frames_dedup/` — a folder with the final unique PNG slides.

---

## 🧱 Requirements & Dependencies

- **OS**: Linux/macOS with Bash
- **Must have**: `ffmpeg` available in `$PATH`
- **Python**: 3.8+

The script automatically creates a **Python virtual environment** inside the working directory and installs:

- [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) — resilient YouTube downloader with multiple client strategies
- [`Pillow`](https://pypi.org/project/Pillow/) — image handling
- [`python-pptx`](https://pypi.org/project/python-pptx/) — PPTX generation

> No global Python packages are required; everything is self-contained per run.

---

## 🧩 How It Works (High Level)

1. **Download**. Tries multiple YouTube player clients (e.g., `web`, `tv_embedded`) and uses cookies if provided to bypass SABR/age/region limits. Prefers **MP4 (AVC + M4A)** without re-encoding; otherwise falls back to **MKV** (remux only).
2. **Verify resolution**. Accepts the download only if the actual video height ≥ `--min-accept-height`.
3. **Extract slide changes**. Uses `ffmpeg` `select='gt(scene,THR)'` (plus optional `crop` and `fps` cap) to extract candidate frames as PNG.
4. **Deduplicate**. Uses a perceptual average hash (aHash) with Hamming distance to keep unique slides.
5. **Export**. Builds a **PDF** and a **PPTX** (16:9 canvas) from the deduplicated PNGs.

---

## 🛠 Troubleshooting

- **Only 360p/720p is downloaded**  
  Use cookies: `--cookies-browser firefox` **or** export `cookies.txt` with a browser extension and pass `--cookies-file /path/cookies.txt`. Try another client (`web` often works best with cookies).

- **Chrome cookies cannot be decrypted on Linux**  
  Install keyring support (`secretstorage`, `keyring`, `jeepney`) or prefer `--cookies-file`. Firefox usually works without OS keyring.

- **Too many or too few slides**  
  Tune `--scene-thr` (e.g., 0.20–0.35) and `--hamming` (e.g., 4–10). Add `--fps-limit 1` to avoid micro-scenes.

- **Talking-head videos**  
  Use `--crop "X:Y:W:H"` to isolate the actual slide area.

- **4K sources**  
  Set `--max-height 2160`. Slides will be exported at the source frame size.

---

## ⚖️ Legal & Ethics

Respect YouTube’s Terms of Service and copyright. Use this tool only for videos you own, have permission to process, or where fair-use/extraction is lawful in your jurisdiction.

---

## 📜 License

MIT License

© H-X Technologies  
https://www.h-x.technology/
