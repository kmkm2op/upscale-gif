Upscale GIF for Windows
=======================

Upscale animations and videos with AI. The output keeps every frame's original timing,
its transparency and its audio.

  Input:  GIF, animated WebP, APNG, animated AVIF, MP4, WebM, MKV, MOV, and most other
          video formats
  Output: GIF, MP4 (H.264), WebM (VP9) or AVIF (AV1)

Everything it needs is included: Upscayl's upscaler, 18 AI models and ffmpeg. Four of the
models (marked in the list) are for non-commercial use only; see THIRD-PARTY-NOTICES.


What you need
-------------

- Windows 10 or 11, 64-bit (PowerShell is built in)
- A GPU with a Vulkan driver (any recent AMD, NVIDIA or Intel GPU with its normal driver)


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

A progress window shows the current step and the time left, with a Cancel button. When
it's done, you can open the folder of the new file. By default the result is saved next
to the original as <name>_<width>x<height>.<ext>.

If you also have the Upscayl app, its models and its custom models folder
(Settings > Custom models folder) appear in the model list too.


Command line
------------

  powershell -ExecutionPolicy Bypass -File upscale-gif.ps1 [-m model] [-w width | -Height height]
      [-f gif|mp4|webm|avif] [-g gpu] [-o output] [file]

  -f can be left out when -o ends in .gif, .mp4, .webm or .avif.
  Use -Height (not -H, which PowerShell reads as -h for help).
  -c   show the detected upscaler, models, GPUs and ffmpeg encoders
  -h   help

Settings (optional environment variables):

  UPSCAYL_BIN            path to another upscayl-bin.exe to use instead of the bundled one
  UPSCAYL_MODELS         models folder for that upscayl-bin.exe
  UPSCAYL_CUSTOM_MODELS  custom models folder, instead of the one set in Upscayl
  UPSCALE_GIF_TEMP       folder for temporary frames (default %TEMP%); they can take
                         several GB for long videos

Without the bundled bin folder (e.g. the script alone), ffmpeg is looked for on PATH and
in winget's folders, and Upscayl in its usual install folders.


License: MIT (see LICENSE.txt). The bundled programs and models have their own licenses;
see THIRD-PARTY-NOTICES.txt and the licenses folder.
