Upscale GIF for Linux
=====================

Upscale animations and videos with AI. The output keeps every frame's original timing,
its transparency and its audio.

  Input:  GIF, animated WebP, APNG, animated AVIF, MP4, WebM, MKV, MOV, and most other
          video formats
  Output: GIF, animated WebP, MP4 (H.264), WebM (VP9) or AVIF (AV1); still images (PNG,
          JPEG, WebP, BMP, TIFF...) also as PNG or JPEG
  Quality: one 1-100% setting (default 80%), used by every format except PNG

Everything it needs is included: Upscayl's upscaler, 18 AI models and ffmpeg. Four of the
models (marked in the list) are for non-commercial use only; see THIRD-PARTY-NOTICES.

For pixel art, choose "nearest" in the model list: it scales by whole multiples (2x, 3x...)
with sharp square pixels, without AI, and works even without a GPU. GIF, WebP (always
lossless with nearest) and PNG suit pixel art best. Pixel art that was already enlarged
(even by an uneven factor such as 3.5x) is detected and restored to its original pixels
first, so uneven pixel sizes and blurred edges don't carry over. Finer detail such as text
drawn at twice the resolution is kept.

It is made for GIFs, short clips and images. For long videos, a dedicated video upscaler
such as Video2X (github.com/k4yt3x/video2x) or REAL Video Enhancer
(github.com/TNTwise/REAL-Video-Enhancer) is a better fit: they need far less temporary
space.


Requirements
------------

- 64-bit Linux with glibc 2.35 or newer (Ubuntu 22.04, Debian 12, Fedora 36 or newer)
- A GPU with a Vulkan driver: AMD Radeon HD 7000 or newer, NVIDIA GeForce GTX 600 or
  newer, or Intel 6th-gen Core graphics or newer (Mesa's Vulkan driver for AMD and
  Intel, NVIDIA's own driver for NVIDIA). Virtual machines usually have none.
- Recommended: a dedicated GPU with 4 GB or more of video memory. Integrated GPUs and
  cards with less memory work, but more slowly.
- zenity, for the settings and progress dialogs (most desktops have it; otherwise install it with your
  package manager)


Install
-------

    tar xf upscale-gif-*-linux-x86_64.tar.gz
    cd upscale-gif-*-linux-x86_64
    ./install.sh

This installs to ~/.local/share/upscale-gif (no root needed) and adds:
- "Upscale GIF" in the application menu and on the desktop
- "Open with > Upscale GIF" for animations and videos, and a Dolphin right-click action
- the upscale-gif command in ~/.local/bin

To remove it: ~/.local/share/upscale-gif/install.sh --uninstall

You can also run ./upscale-gif straight from the extracted folder without installing.


Use
---

Start Upscale GIF, pick a file, then choose the model, size and format. A progress window
shows the time left. The result is saved next to the original as
<name>_<width>x<height>.<ext>.

If you also have the Upscayl app, its models and its custom models folder
(Settings > Custom models folder) appear in the model list too.

Command line:

    upscale-gif [-m model] [-w width | -H height] [-f format] [-q quality] [-d downsampler] [-g gpu] [-o output] [file]
    -d: how the AI result is resized: lanczos (default, sharpest), spline, bicubic or area
        (softest, no halos)
    -t: where the temporary frames go: auto (RAM when they fit in half the available
        memory, else disk; the default), ram or disk
    upscale-gif -c    show the detected upscaler, models, GPUs and ffmpeg
    upscale-gif -h    help


License: MIT (LICENSE.txt). The bundled programs and models have their own licenses; see
THIRD-PARTY-NOTICES.md and the licenses folder.
