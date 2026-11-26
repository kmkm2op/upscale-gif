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

The models are in ncnn format, as converted and distributed by the Upscayl project
(https://github.com/upscayl/upscayl and https://github.com/upscayl/custom-models). They are
unmodified otherwise. License texts: `licenses/models-*.txt` and
`licenses/Real-ESRGAN-models-BSD-3-Clause.txt`.

| File name | Model | Author | License |
|---|---|---|---|
| upscayl-standard-4x | RealESRGAN_x4plus | Xintao Wang (Real-ESRGAN) | BSD-3-Clause |
| upscayl-lite-4x | realesr-general-x4v3 | Xintao Wang (Real-ESRGAN) | BSD-3-Clause |
| digital-art-4x | RealESRGAN_x4plus_anime_6B | Xintao Wang (Real-ESRGAN) | BSD-3-Clause |
| RealESRGAN_General_WDN_x4_v3 | realesr-general-wdn-x4v3 | Xintao Wang (Real-ESRGAN) | BSD-3-Clause |
| realesr-animevideov3-x2, -x3, -x4 | realesr-animevideov3 | Xintao Wang (Real-ESRGAN) | BSD-3-Clause |
| high-fidelity-4x | 4xHFA2k | Philip Hofmann (Helaman) | CC BY 4.0 |
| 4xLSDIR | 4xLSDIR | Philip Hofmann (Helaman) | CC BY 4.0 |
| 4xLSDIRCompactC3 | 4xLSDIRCompactC3 | Philip Hofmann (Helaman) | CC BY 4.0 |
| 4xLSDIRplusC | 4xLSDIRplusC | Philip Hofmann (Helaman) | CC BY 4.0 |
| 4xNomos8kSC | 4xNomos8kSC | Philip Hofmann (Helaman) | CC BY 4.0 |
| 4x_NMKD-Siax_200k | 4x-NMKD-Siax-CX | Nmkd | WTFPL |
| 4x_NMKD-Superscale-SP_178000_G | 4x-NMKD-Superscale | Nmkd | WTFPL |
| ultrasharp-4x | 4x-UltraSharp | Kim2091 | CC BY-NC-SA 4.0 |
| ultramix-balanced-4x | 4x-UltraMix_Balanced | Kim2091 | CC BY-NC-SA 4.0 |
| uniscale_restore | 4x-UniScale_Restore | Kim2091 | CC BY-NC-SA 4.0 |
| remacri-4x | 4x-Remacri | Foolhardy | CC BY-NC-SA 4.0 |

Model pages: https://openmodeldb.info and https://github.com/xinntao/Real-ESRGAN

**Non-commercial models:** ultrasharp-4x, ultramix-balanced-4x, uniscale_restore and
remacri-4x are licensed CC BY-NC-SA 4.0. They may only be used and shared for
non-commercial purposes, and shared copies must keep the same license. Use one of the
other models for commercial work.
