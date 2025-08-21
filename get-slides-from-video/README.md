<h1> H-X YouTube Video Slide Extractor </h1>

This is a YouTube webinar and other video downloader which extract slides, build PDF and PPTX.

<h2>Quick Start</h2>
<p>Make it executable:</p>
<pre>chmod +x get-slides-from-video.bash</pre>
<p>Basic example (≤1080p):
<pre>./get-slides-from-video.bash --url "https://www.youtube.com/watch?v=uEvKjSQ0EMA&t=1687s" --out blockchain_security</pre>
<p>With Firefox cookies for FullHD+:
<pre>./get-slides-from-video.bash --url "https://www.youtube.com/watch?v=uEvKjSQ0EMA&t=1687s" --cookies-browser firefox --out blockchain_security</pre>
<p>With cookies.txt:
<pre>./get-slides-from-video.bash --url "URL" --cookies-file /path/cookies.txt --out slides</pre>

<h2>Tips</h2>
<p>If the result is <900p, add --cookies-browser firefox or --cookies-file cookies.txt.
<p>For 4K, raise --max-height 2160.
<p>For talking-head webinars, crop presentation with `--
<p> &nbsp;
<p>License: MIT
<p>(c) H-X Technologies<br>
<p>https://www.h-x.technology/
