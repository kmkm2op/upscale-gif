# upscale-gif

Upscale animations and videos with AI, using [Upscayl](https://github.com/upscayl/upscayl)'s
upscaler and Real-ESRGAN models.
The output keeps every frame's original timing, its transparency and its audio.

- **Input:** GIF, animated WebP, APNG, animated AVIF, MP4, WebM, MKV, MOV, and most other
  video formats; also still images (PNG, JPEG, WebP, AVIF, BMP, TIFF)
- **Output:** GIF, animated WebP, MP4 (H.264), WebM (VP9) or AVIF (AV1); still images also as
  PNG or JPEG
- **Quality:** one 1–100% setting, mapped onto each format's own quality scale
- **Interface:** command-line options, or a small settings window for anything you leave
  out, so it also works from a desktop launcher or file manager
- **Platforms:** Linux (bash) and Windows (PowerShell)

## How it works

1. Probes the input and works out each frame's exact duration (variable frame timing is
   supported).
2. Extracts every frame as a lossless RGBA PNG.
3. Upscales all frames with `upscayl-bin` on the GPU (Vulkan), at the model's own scale
   (4× for the built-in models). The `nearest` choice for pixel art skips this step.
4. Downsamples to the size you chose (Lanczos), then reassembles the frames with their
   original durations.
5. Encodes the result:

| Format | Codec      | Transparency           | Audio |
|--------|------------|------------------------|-------|
| gif    | GIF        | yes (1-bit)            | no    |
| webp   | WebP       | yes                    | no    |
| webm   | VP9        | yes                    | yes (Opus) |
| avif   | AV1        | yes                    | no    |
| mp4    | H.264      | no (becomes black)     | yes (AAC) |
| png    | PNG        | yes                    | still images only, lossless |
| jpg    | JPEG       | no (becomes white)     | still images only |

Animated WebP is a good GIF alternative: full colour instead of 256 colours, smooth
transparency, millisecond timing and much smaller files. All modern browsers show it, but
some older viewers and upload sites only animate GIFs.

When the input has a single frame (a photo, or a one-frame GIF), the settings window offers
PNG, JPEG, WebP, AVIF and GIF instead of the video formats, and WebP and AVIF are saved as
still images. Photos with an EXIF orientation are turned upright.

**Quality** (`-q`, default 80%) sets how much compression each format uses. 80% gives
the defaults below; 100% is the best the format offers. It is ignored for PNG, which is
always lossless.

| Format | 80% | 100% | Lower |
|---|---|---|---|
| mp4 | CRF 16 | CRF 7 | up to CRF 51 |
| webm | CRF 18 | CRF 7 | up to CRF 63 |
| avif | CRF 20 | CRF 9 | up to CRF 63 |
| jpg | q 7 | q 1 | up to q 31 |
| webp | quality 80 | lossless | quality = the percentage |
| gif | 256 colours | 256 colours | fewer colours below 80% (smaller files) |

Temporary frames go to `~/.cache/upscale-gif.XXXXXX` (or `$XDG_CACHE_HOME`), not `/tmp`,
because they can take several GB. That folder is deleted when the script exits.

## Install

Download the package for your system from the
[Releases](../../releases) page. Everything is included: Upscayl's upscaler, AI models and
ffmpeg.

**Windows 10/11:** extract `upscale-gif-<version>-windows-x64.zip` and double-click
`Install.cmd`. No administrator rights needed. This adds "Upscale GIF" to the Start menu,
the desktop and the "Send to" menu. See [windows/README.txt](windows/README.txt).

**Linux (x86-64):**

```sh
tar xf upscale-gif-*-linux-x86_64.tar.gz
cd upscale-gif-*-linux-x86_64
./install.sh            # ./install.sh --uninstall removes it again
```

This installs to `~/.local/share/upscale-gif` (no root needed) and adds an application menu
entry, a desktop shortcut, "Open with" for animations and videos, a Dolphin right-click
action and the `upscale-gif` command.

You need a GPU with a Vulkan driver (see [GPU](#gpu)) for the AI models. On Linux you also need glibc 2.35+ (Ubuntu 22.04,
Debian 12, Fedora 36 or newer) and `zenity` for the windows (`kdialog` is used for the file
picker when available).

Run `upscale-gif -c` to see what was detected.

### Without the bundle

The script also works on its own (`make install PREFIX=~/.local`, or copy `upscale-gif`
onto your `PATH`). It then needs bash 4+, GNU coreutils, ffmpeg/ffprobe 7+ (8+ for
animated WebP input) with `gif`, `libx264`, `libvpx-vp9` and `libaom-av1`, and an
installed Upscayl (distro package, .deb/.rpm, Snap, Flatpak, or an extracted AppImage).
python3 is optional: it reads Upscayl's own settings (custom models folder, GPU ID).

## Building the release packages

```sh
make release VERSION=1.0.0      # or release-linux / release-windows
```

[packaging/build.sh](packaging/build.sh) downloads the pinned sources in
[packaging/sources.txt](packaging/sources.txt), builds a small static ffmpeg for Linux and,
with the llvm-mingw cross-compiler, for Windows, and writes three files to `dist/`: the
Linux and Windows packages, and the source code of the bundled GPL/AGPL programs. It needs
gcc, make, cmake, pkg-config, python3, curl, xz and bzip2; the first build takes a few
minutes.

Pushing a tag like `v1.0.0` runs the same build on GitHub Actions
([release.yml](.github/workflows/release.yml)) and publishes a release with the three files.

## Usage

```
upscale-gif [-m model] [-w width | -H height] [-f format] [-q quality] [-g gpu] [-o output] [input]
upscale-gif -c     # show detected Upscayl, models, GPUs and ffmpeg encoders
upscale-gif -h     # help
```

| Option      | Meaning |
|-------------|---------|
| `-m model`  | Upscayl model name, e.g. `digital-art-4x` (see `-c` for the list), or `nearest` for pixel art |
| `-w width`  | Output width in pixels; height follows the aspect ratio |
| `-H height` | Output height in pixels; width follows the aspect ratio |
| `-f format` | `gif`, `webp`, `mp4`, `webm`, `avif`, and for single images `png`, `jpg`. Can be left out when `-o` ends in one of these |
| `-q quality`| 1–100 (default 80); ignored for `png` |
| `-g gpu`    | GPU ID as listed by `-c`, a list such as `0,1`, or `auto` |
| `-o output` | Output file. Default: `<input>_<W>x<H>.<format>` next to the input |

Anything you don't give on the command line is asked for:

- No input file: a file picker opens.
- No model, size or format: a settings window opens. It shows the source size, frame count,
  duration, fps and the temporary space needed. The size list offers 2×/3×/4× and
  720p–2160p presets. With more than one GPU, it also offers a GPU choice.

The last model, format and folder you used are saved in `~/.config/upscale-gif.conf`.

While it runs, a progress bar shows the current step and the time left: in the terminal, or
in a window with a Cancel button when started without one (e.g. from a desktop shortcut).

Examples:

```sh
upscale-gif                                   # everything from the windows
upscale-gif -m digital-art-4x -w 1920 -f webm anime.gif
upscale-gif -m high-fidelity-4x -H 2160 -f mp4 -o out.mp4 clip.mp4
upscale-gif -m nearest -w 1024 -f webp sprite.gif
```

Sizes follow the picture as it's displayed: rotated phone videos come out upright, and
non-square pixels (anamorphic video) are made square.

Output sizes are rounded to even numbers. Sizes above 4× still work, but the final step
just enlarges the image.

## Models

The packages include Upscayl's built-in models and its
[custom models](https://github.com/upscayl/custom-models) collection, 18 in all:

| Model | Good for | License |
|---|---|---|
| `upscayl-standard-4x` | General purpose (the default) | BSD-3-Clause |
| `upscayl-lite-4x` | General purpose, faster | BSD-3-Clause |
| `digital-art-4x` | Digital art, anime, cartoons | BSD-3-Clause |
| `high-fidelity-4x` | Photos, keeps fine detail | CC BY 4.0 |
| `realesr-animevideov3-x4`, `-x3`, `-x2` | Anime and cartoon video, fastest | BSD-3-Clause |
| `RealESRGAN_General_WDN_x4_v3` | General purpose, fast, less smoothing | BSD-3-Clause |
| `4x_NMKD-Siax_200k` | General purpose, clean or lightly compressed | WTFPL |
| `4xLSDIR` | Photos, clean sources | CC BY 4.0 |
| `4xLSDIRplusC`, `4xLSDIRCompactC3` | Photos with JPEG artifacts (C3 is faster) | CC BY 4.0 |
| `4xNomos8kSC` | Photos with JPEG artifacts or blur | CC BY 4.0 |
| `4x_NMKD-Superscale-SP_178000_G` | Photos with noise and artifacts | WTFPL |
| `remacri-4x` | Natural and sharp | CC BY-NC-SA 4.0 |
| `ultrasharp-4x` | Very sharp | CC BY-NC-SA 4.0 |
| `ultramix-balanced-4x` | Balance of sharp and smooth | CC BY-NC-SA 4.0 |
| `uniscale_restore` | Heavily compressed or noisy images | CC BY-NC-SA 4.0 |

The four CC BY-NC-SA models may only be used for non-commercial purposes; the model list
marks them. Authors and details are in
[packaging/THIRD-PARTY-NOTICES.md](packaging/THIRD-PARTY-NOTICES.md).

Models in the custom models folder set in the Upscayl app (below) are added to the list.

### Pixel art: `nearest`

AI models smooth and redraw edges, which spoils pixel art. The `nearest` choice instead
scales with nearest neighbour: every source pixel becomes a sharp square of the same
colour. It uses no AI and no GPU, so it is fast and also works when no Vulkan GPU is found
(the model list then offers only `nearest`).

- Sizes are whole multiples of the original (2×, 3×, 4×…), rounding the chosen size down,
  with no upper limit. A note shows the size used.
- GIF output gets no dithering, and WebP output is always lossless, so colours stay intact.
  GIF, WebP and PNG suit pixel art best; MP4, WebM, AVIF and JPEG blur colour slightly.
- MP4 and WebM need even sizes: an odd one gets a 1-pixel transparent (MP4: black) edge.

## Finding Upscayl

The script looks for Upscayl's command-line upscaler (`upscayl-bin`) in this order:

1. `UPSCAYL_BIN` environment variable
2. The bundled `bin/upscayl-bin` next to the script
3. `upscayl-bin` or `upscayl-ncnn` on `PATH`
4. Common install locations: `/usr/share/upscayl/bin`, `/usr/lib/upscayl/resources/bin`,
   `/opt/Upscayl/resources/bin`, `/snap/upscayl/current/resources/bin`, and Flatpak
   `org.upscayl.Upscayl` (system and user installs)

A binary is used only if its `-h` output includes the `-z model-scale` option. This
rules out the Electron GUI launcher and other Real-ESRGAN builds.

The models folder is found next to the binary, or set with `UPSCAYL_MODELS`.

**AppImage:** extract it first, then point the script at the binary:

```sh
./Upscayl-*.AppImage --appimage-extract
export UPSCAYL_BIN=$PWD/squashfs-root/resources/bin/upscayl-bin
```

## Custom models

The script uses the custom models folder chosen in Upscayl itself
(**Settings → Custom models folder**), so models added there show up in both. Get models
from [upscayl/custom-models](https://github.com/upscayl/custom-models); each one is a
`.param` + `.bin` pair. To use a different folder, set `UPSCAYL_CUSTOM_MODELS`.

As in Upscayl, the model's scale comes from its name: names containing `x2`/`2x` are 2×,
`x3`/`3x` are 3×, and all others are 4×.

Upscayl keeps its settings in its Chromium storage (`~/.config/Upscayl/Local Storage`,
or the Flatpak/Snap equivalent). The script reads them with python3 and never writes to
them. Upscayl must have saved the setting, which normally happens within seconds of
choosing the folder.

## GPU

### Requirements

Upscaling runs on the GPU through Vulkan, so any GPU with a Vulkan driver works:

- **AMD:** Radeon HD 7000 series (GCN, 2012) or newer
- **NVIDIA:** GeForce GTX 600 series (Kepler) or newer
- **Intel:** 6th-gen Core integrated graphics (HD/UHD 500 series) or newer, Iris Xe, Arc

The normal driver is enough: Mesa (`mesa-vulkan-drivers`, `vulkan-radeon`, `vulkan-intel`)
on Linux, or the AMD/NVIDIA/Intel driver on Windows. Virtual machines and Remote Desktop
sessions usually have no Vulkan GPU. A software Vulkan driver (llvmpipe, lavapipe,
SwiftShader) works but runs on the CPU and is very slow; upscale-gif warns about it.

Video memory is not a hard limit: each frame is split into tiles sized to fit the GPU's
memory, so 1–2 GB cards work, just more slowly.

### Recommendations

- A dedicated GPU with 4 GB or more of video memory; integrated GPUs work but are slower.
- For long videos, a lighter model. On an RX 9070 XT, a 480×270 frame upscaled to
  1920×1080 takes about 0.06 s with `upscayl-lite-4x` and 0.5 s with
  `upscayl-standard-4x`; a 1000-frame clip is then about 1 or 8 minutes.

### Choosing and checking the GPU

The GPU is chosen by `-g`, else by Upscayl's **GPU ID** setting, else automatically.
`upscale-gif -c` lists the GPUs with the IDs Upscayl uses, or explains what to install
when none is found. A run stops with the same explanation before asking for anything.

## Notes

- A file with many frames takes a while: each frame is a separate AI upscale. The settings
  window warns above 500 frames or when disk space is low.
- Zero-delay GIF frames are given 0.1 s, as browsers display them.

## Credits

upscale-gif was written with [GitHub Copilot](https://github.com/features/copilot), an AI
coding assistant, which wrote and tested most of the code under Someone's direction. Every
commit lists Copilot as a co-author.

## License

upscale-gif is [MIT](LICENSE)-licensed. The release packages also contain programs and
models with their own licenses, listed in
[packaging/THIRD-PARTY-NOTICES.md](packaging/THIRD-PARTY-NOTICES.md): Upscayl's upscaler
(AGPL-3.0), ffmpeg with x264 (GPL-2.0-or-later), and the models (BSD-3-Clause, CC BY 4.0,
WTFPL, and CC BY-NC-SA 4.0 for four models that are for non-commercial use only).
They are separate programs that upscale-gif runs, so they don't change the license of
upscale-gif itself. Their source code is published with each release.
