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


Requirements
------------

- 64-bit Linux with glibc 2.35 or newer (Ubuntu 22.04, Debian 12, Fedora 36 or newer)
- A GPU with a Vulkan driver (any recent AMD, Intel or NVIDIA GPU)
- zenity, for the windows (most desktops have it; otherwise install it with your
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

    upscale-gif [-m model] [-w width | -H height] [-f format] [-q quality] [-g gpu] [-o output] [file]
    upscale-gif -c    show the detected upscaler, models, GPUs and ffmpeg
    upscale-gif -h    help


License: MIT (LICENSE.txt). The bundled programs and models have their own licenses; see
THIRD-PARTY-NOTICES.md and the licenses folder.
