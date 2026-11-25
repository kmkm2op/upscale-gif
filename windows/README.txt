Upscale GIF for Windows
=======================

Upscale animations and videos with Upscayl's AI models. The output keeps every frame's
original timing, its transparency and its audio.

  Input:  GIF, animated WebP, APNG, animated AVIF, MP4, WebM, MKV, MOV, and anything
          else ffmpeg can read
  Output: GIF, MP4 (H.264), WebM (VP9) or AVIF (AV1)


What you need
-------------

- Windows 10 or 11 (PowerShell is built in)
- Upscayl:  https://upscayl.org   or   winget install Upscayl.Upscayl
- ffmpeg:   winget install Gyan.FFmpeg
- A GPU with Vulkan support (any recent AMD, NVIDIA or Intel GPU)

The installer offers to install ffmpeg and Upscayl with winget if they are missing.


Install
-------

1. Extract the whole zip file.
2. Double-click Install.cmd. If Windows warns that the file came from the internet,
   choose "Run" (or right-click the zip > Properties > Unblock before extracting).

This adds "Upscale GIF" to the Start menu, the desktop and the "Send to" menu.
Nothing needs administrator rights. To remove it, use Settings > Apps > Upscale GIF.

You can also skip installing and double-click "Upscale GIF.cmd", or drop a file on it.


Use
---

- Start "Upscale GIF", pick a file, then choose the model, size and format.
- Or drop a file on the desktop icon.
- Or right-click a file > Send to > Upscale GIF.
  (On Windows 11, choose "Show more options" first.)

A console window shows the progress. When it's done, you can open the folder of the new
file. By default the result is saved next to the original as <name>_<width>x<height>.<ext>.

Custom models: models in the custom models folder chosen in Upscayl
(Settings > Custom models folder) appear in the model list automatically.


Command line
------------

  powershell -ExecutionPolicy Bypass -File upscale-gif.ps1 [-m model] [-w width | -Height height]
      [-f gif|mp4|webm|avif] [-g gpu] [-o output] [file]

  -c   show the detected Upscayl, models, GPUs and ffmpeg encoders
  -h   help

Settings (optional environment variables):

  UPSCAYL_BIN            path to upscayl-bin.exe, for an Upscayl install that isn't found
  UPSCAYL_MODELS         models folder for that install
  UPSCAYL_CUSTOM_MODELS  custom models folder, instead of the one set in Upscayl
  UPSCALE_GIF_TEMP       folder for temporary frames (default %TEMP%); they can take
                         several GB for long videos

ffmpeg is found on PATH, in winget's folders, or next to upscale-gif.ps1.


License: MIT (see LICENSE.txt)
