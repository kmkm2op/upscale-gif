# upscale-gif

Upscale animations and videos with [Upscayl](https://github.com/upscayl/upscayl)'s AI models.
The output keeps every frame's original timing, its transparency and its audio.

- **Input:** GIF, animated WebP, APNG, animated AVIF, MP4, WebM, MKV, MOV, and anything
  else ffmpeg can decode
- **Output:** GIF, MP4 (H.264), WebM (VP9) or AVIF (AV1)
- **Interface:** command-line options, or a small settings window (zenity) for anything
  you leave out, so it also works from a desktop launcher or file manager

## How it works

1. Probes the input and works out each frame's exact duration (variable frame timing is
   supported).
2. Extracts every frame as a lossless RGBA PNG.
3. Upscales all frames with `upscayl-bin` on the GPU (Vulkan), at the model's own scale
   (4× for the built-in models).
4. Downsamples to the size you chose (Lanczos), then reassembles the frames with their
   original durations.
5. Encodes the result:

| Format | Codec      | Transparency           | Audio |
|--------|------------|------------------------|-------|
| gif    | GIF        | yes (1-bit)            | no    |
| webm   | VP9        | yes                    | yes (Opus) |
| avif   | AV1        | yes                    | no    |
| mp4    | H.264      | no (becomes black)     | yes (AAC) |

Temporary frames go to `~/.cache/upscale-gif.XXXXXX` (or `$XDG_CACHE_HOME`), not `/tmp`,
because they can take several GB. That folder is deleted when the script exits.

## Requirements

- bash 4+, GNU coreutils (`numfmt`, `realpath`), awk
- ffmpeg and ffprobe 7+ (8+ for animated WebP input), built with the encoders for the
  formats you want: `gif`, `libx264`, `libvpx-vp9`, `libaom-av1`, and `libopus` (optional)
- Upscayl, from any source: distro package, .deb/.rpm, Snap, Flatpak, or an extracted
  AppImage
- A GPU with Vulkan support
- python3 (optional): reads Upscayl's own settings, i.e. its custom models folder and GPU ID
- For the windows: `zenity` (and `kdialog` for the file picker, when available),
  plus `notify-send` for the "done" notification

## Install

```sh
make install                      # to /usr/local/bin (needs sudo)
make install PREFIX=~/.local      # just for you, to ~/.local/bin
```

Or copy `upscale-gif` anywhere on your `PATH` and make it executable.

Run `upscale-gif -c` to check what was detected.

## Windows

`windows/` has a PowerShell version with the same features. It needs no extra software
beyond Upscayl and ffmpeg, and it uses Windows dialogs instead of zenity. Build the zip with:

```sh
make windows                  # creates dist/upscale-gif-<version>-windows.zip
make windows VERSION=1.1.0
```

On Windows, extract the zip and run `Install.cmd`. It needs no administrator rights. It adds
"Upscale GIF" to the Start menu, the desktop and the "Send to" menu, and offers to install
ffmpeg and Upscayl with winget if they're missing. See [windows/README.txt](windows/README.txt).

## Usage

```
upscale-gif [-m model] [-w width | -H height] [-f gif|mp4|webm|avif] [-g gpu] [-o output] [input]
upscale-gif -c     # show detected Upscayl, models, GPUs and ffmpeg encoders
upscale-gif -h     # help
```

| Option      | Meaning |
|-------------|---------|
| `-m model`  | Upscayl model name, e.g. `digital-art-4x` (see `-c` for the list) |
| `-w width`  | Output width in pixels; height follows the aspect ratio |
| `-H height` | Output height in pixels; width follows the aspect ratio |
| `-f format` | `gif`, `mp4`, `webm` or `avif`. Can be left out when `-o` ends in one of these |
| `-g gpu`    | GPU ID as listed by `-c`, a list such as `0,1`, or `auto` |
| `-o output` | Output file. Default: `<input>_<W>x<H>.<format>` next to the input |

Anything you don't give on the command line is asked for:

- No input file: a file picker opens.
- No model, size or format: a settings window opens. It shows the source size, frame count,
  duration, fps and the temporary space needed. The size list offers 2×/3×/4× and
  720p–2160p presets. With more than one GPU, it also offers a GPU choice.

The last model, format and folder you used are saved in `~/.config/upscale-gif.conf`.

Examples:

```sh
upscale-gif                                   # everything from the windows
upscale-gif -m digital-art-4x -w 1920 -f webm anime.gif
upscale-gif -m high-fidelity-4x -H 2160 -f mp4 -o out.mp4 clip.mp4
```

Sizes follow the picture as it's displayed: rotated phone videos come out upright, and
non-square pixels (anamorphic video) are made square.

Output sizes are rounded to even numbers. Sizes above 4× still work, but the final step
just enlarges the image.

## Finding Upscayl

The script looks for Upscayl's command-line upscaler (`upscayl-bin`) in this order:

1. `UPSCAYL_BIN` environment variable
2. `upscayl-bin` or `upscayl-ncnn` on `PATH`
3. Common install locations: `/usr/share/upscayl/bin`, `/usr/lib/upscayl/resources/bin`,
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

The GPU is chosen by `-g`, else by Upscayl's **GPU ID** setting, else automatically.
`upscale-gif -c` lists the GPUs with the IDs Upscayl uses.

## Notes

- A file with many frames takes a while: each frame is a separate AI upscale. The settings
  window warns above 500 frames or when disk space is low.
- Zero-delay GIF frames are given 0.1 s, as browsers display them.

## License

[MIT](LICENSE)
