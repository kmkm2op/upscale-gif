# Third-party software in upscale-gif @VERSION@

upscale-gif itself is MIT-licensed (LICENSE.txt). This package also contains the programs
and models below. Each is a separate program or data file with its own license; their
license texts are in the `licenses` folder.

## Programs (in `bin`)

| Program | Version | License | Source |
|---|---|---|---|
| upscayl-bin (Upscayl's upscaler, unmodified) | upscayl-ncnn 20251207-174704 | AGPL-3.0 | https://github.com/upscayl/upscayl-ncnn/tree/20251207-174704 |
| ffmpeg, ffprobe | FFmpeg 9.1 | GPL-2.0-or-later (built with x264) | https://ffmpeg.org/releases/ffmpeg-9.1.tar.xz |

ffmpeg and ffprobe are built by `packaging/build.sh` with these libraries linked in
statically:

| Library | Version | License | Source |
|---|---|---|---|
| x264 | stable b35605ac | GPL-2.0-or-later | https://code.videolan.org/videolan/x264 |
| libvpx | 1.17.0 | BSD-3-Clause, plus patent grant | https://github.com/webmproject/libvpx |
| libaom | 3.15.3 | BSD-2-Clause, plus AOM patent license | https://aomedia.googlesource.com/aom |
| Opus | 1.6.1 | BSD-3-Clause | https://opus-codec.org |
| zlib | 1.4 | zlib | https://zlib.net |

The Windows package also contains `vcomp140.dll`, Microsoft's OpenMP runtime from the
Visual C++ Redistributable, which upscayl-bin.exe needs. Microsoft permits redistributing
it with applications.

### Source code

The complete source code of the GPL and AGPL programs above, with the build script that
produced them, is published next to this package on the release page as
`upscale-gif-@VERSION@-sources.tar.gz`. If you can't get it there, open an issue on the
project's GitHub page and a copy will be provided, for at least three years after this
release.

## Models (in `models`)

| Model | License | Author |
|---|---|---|
| realesrgan-x4plus | BSD-3-Clause | Xintao Wang (Real-ESRGAN) |
| realesrgan-x4plus-anime | BSD-3-Clause | Xintao Wang (Real-ESRGAN) |
| realesr-animevideov3-x2, -x3, -x4 | BSD-3-Clause | Xintao Wang (Real-ESRGAN) |
| RealESRGAN_General_x4_v3 | BSD-3-Clause | Xintao Wang (Real-ESRGAN); ncnn conversion from upscayl/custom-models |

Real-ESRGAN: https://github.com/xinntao/Real-ESRGAN
