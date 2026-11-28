#!/usr/bin/env bash
# Builds the self-contained release packages, which need nothing else installed:
#   dist/upscale-gif-VERSION-linux-x86_64.tar.gz
#   dist/upscale-gif-VERSION-windows-x64.zip
#   dist/upscale-gif-VERSION-sources.tar.gz   source code of the bundled GPL/AGPL programs
#
# Usage: packaging/build.sh VERSION [linux] [windows]     (both when neither is given)
#
# ffmpeg is built from source with only what upscale-gif needs (it reads nearly any input,
# but writes only GIF, MP4, WebM and AVIF), statically, so it runs on any distribution.
# Windows builds use llvm-mingw, which is downloaded. Host needs: gcc, g++, make, cmake,
# pkg-config, python3, curl, tar, xz, bzip2. Downloads and builds are cached in
# $UPSCALE_GIF_BUILD (default ~/.cache/upscale-gif-build).
set -euo pipefail

VERSION=${1:?usage: packaging/build.sh VERSION [linux] [windows]}
shift
TARGETS=("$@"); (( ${#TARGETS[@]} )) || TARGETS=(linux windows)
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
CACHE=${UPSCALE_GIF_BUILD:-$HOME/.cache/upscale-gif-build}
DL=$CACHE/downloads
DIST=$ROOT/dist
JOBS=$(nproc)
X264=x264-b35605ace3ddf7c1a5d67a2eb553f034aef41d55

log() { printf '\n==> %s\n' "$*" >&2; }

# --- Downloads ------------------------------------------------------------------------
mkdir -p "$DL/models" "$DIST"
while read -r name sum url dir; do
    [[ -z $name || $name == \#* ]] && continue
    f=$DL/$dir$name
    if [[ ! -s $f ]] || ! echo "$sum  $f" | sha256sum -c --status; then
        log "Downloading $name"
        curl -fL --retry 3 -o "$f.part" "$url"
        mv "$f.part" "$f"
    fi
    echo "$sum  $f" | sha256sum -c --quiet || { echo "checksum mismatch: $name" >&2; exit 1; }
done < <(cat "$HERE/sources.txt"; sed '/^#/d; /^$/d; s|$|  models/|' "$HERE/models.txt")

unpack() {   # unpack ARCHIVE DIR: extract into a fresh DIR, dropping the top-level folder
    rm -rf "$2"; mkdir -p "$2"
    case $1 in
        *.zip) python3 -m zipfile -e "$1" "$2.tmp" && mv "$2.tmp"/*/* "$2" && rm -rf "$2.tmp" ;;
        *) tar xf "$1" -C "$2" --strip-components=1 ;;
    esac
}

# --- Build tools --------------------------------------------------------------------------
TOOLS=$CACHE/tools
if [[ ! -x $TOOLS/bin/nasm ]]; then
    log "Building nasm"
    unpack "$DL/nasm-2.16.03.tar.xz" "$CACHE/src/nasm"
    (cd "$CACHE/src/nasm" && ./configure -q --prefix="$TOOLS" && make -s -j"$JOBS" && make -s install)
fi
export PATH=$TOOLS/bin:$PATH

# --- ffmpeg -------------------------------------------------------------------------------
# build_ffmpeg TARGET: builds x264, libvpx, libaom, opus and ffmpeg into $CACHE/TARGET/prefix
build_ffmpeg() {
    local t=$1 p=$CACHE/$1/prefix s=$CACHE/$1/src stamp
    # Rebuild when its sources or this function change
    stamp=$( { grep -E '^(nasm|zlib|x264|opus|libwebp|libvpx|libaom|ffmpeg|llvm-mingw)-' "$HERE/sources.txt"; declare -f build_ffmpeg; } \
        | sha256sum | cut -c1-16)
    [[ $(cat "$CACHE/$t/stamp" 2>/dev/null) == "$stamp" ]] && return 0
    rm -rf "$CACHE/$t"; mkdir -p "$p" "$s"

    local host=() cross="" vpx_target aom_cmake=() ff=()
    if [[ $t == windows ]]; then
        if [[ ! -x $CACHE/llvm-mingw/bin/x86_64-w64-mingw32-clang ]]; then
            log "Unpacking llvm-mingw"
            unpack "$DL/llvm-mingw-20261117-ucrt-ubuntu-22.04-x86_64.tar.xz" "$CACHE/llvm-mingw"
        fi
        export PATH=$CACHE/llvm-mingw/bin:$PATH
        cross=x86_64-w64-mingw32-
        host=(--host=x86_64-w64-mingw32)
        vpx_target=x86_64-win64-gcc
        aom_cmake=(-DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR=AMD64
            -DCMAKE_C_COMPILER=${cross}clang -DCMAKE_CXX_COMPILER=${cross}clang++
            -DCMAKE_AR="$(command -v ${cross}ar)" -DCMAKE_RANLIB="$(command -v ${cross}ranlib)")
        ff=(--target-os=mingw32 --arch=x86_64 --cross-prefix=$cross --cc=${cross}clang --cxx=${cross}clang++
            --extra-ldflags=-static)
    else
        vpx_target=x86_64-linux-gcc
        ff=(--extra-ldflags=-static --extra-cflags=-fPIC)
    fi
    export PKG_CONFIG_PATH=$p/lib/pkgconfig PKG_CONFIG_LIBDIR=$p/lib/pkgconfig

    log "[$t] zlib"
    unpack "$DL/zlib-1.4.tar.gz" "$s/zlib"
    if [[ $t == windows ]]; then
        (cd "$s/zlib" && make -s -f win32/Makefile.gcc PREFIX=$cross CC=${cross}clang -j"$JOBS" libz.a \
            && install -D -m644 libz.a "$p/lib/libz.a" && install -Dm644 -t "$p/include" zlib.h zconf.h)
    else
        (cd "$s/zlib" && CFLAGS="-O2 -fPIC" ./configure --prefix="$p" --static && make -s -j"$JOBS" && make -s install)
    fi >"$s/zlib.log" 2>&1 || { tail -30 "$s/zlib.log"; exit 1; }

    log "[$t] x264"
    unpack "$DL/$X264.tar.bz2" "$s/x264"
    (cd "$s/x264" && ./configure --prefix="$p" "${host[@]}" ${cross:+--cross-prefix=$cross} \
        --enable-static --enable-pic --disable-cli --disable-lavf --disable-swscale --disable-ffms --disable-gpac --disable-lsmash \
        && make -s -j"$JOBS" && make -s install) >"$s/x264.log" 2>&1 || { tail -30 "$s/x264.log"; exit 1; }

    log "[$t] opus"
    unpack "$DL/opus-1.6.1.tar.gz" "$s/opus"
    (cd "$s/opus" && CC=${cross}gcc ./configure --prefix="$p" "${host[@]}" --enable-static --disable-shared \
        --disable-doc --disable-extra-programs --with-pic && make -s -j"$JOBS" && make -s install) \
        >"$s/opus.log" 2>&1 || { tail -30 "$s/opus.log"; exit 1; }

    log "[$t] libwebp"
    unpack "$DL/libwebp-1.6.0.tar.gz" "$s/libwebp"
    (cd "$s/libwebp" && CC=${cross}gcc ./configure --prefix="$p" "${host[@]}" --enable-static --disable-shared --with-pic \
        --disable-libwebpdecoder --disable-sdl --disable-png --disable-jpeg --disable-tiff --disable-gif --disable-wic \
        && make -s -j"$JOBS" && make -s install) >"$s/libwebp.log" 2>&1 || { tail -30 "$s/libwebp.log"; exit 1; }

    log "[$t] libvpx"
    unpack "$DL/libvpx-1.17.0.tar.gz" "$s/libvpx"
    (cd "$s/libvpx" && CROSS=$cross ./configure --prefix="$p" --target=$vpx_target --as=nasm \
        --enable-static --disable-shared --enable-pic --disable-examples --disable-tools --disable-docs \
        --disable-unit-tests --enable-vp9-highbitdepth && make -s -j"$JOBS" && make -s install) \
        >"$s/libvpx.log" 2>&1 || { tail -30 "$s/libvpx.log"; exit 1; }

    log "[$t] libaom"
    unpack "$DL/libaom-3.15.3.tar.gz" "$s/aom"
    (mkdir -p "$s/aom-build" && cd "$s/aom-build" && cmake "$s/aom" -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$p" -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_SHARED_LIBS=0 -DCMAKE_POSITION_INDEPENDENT_CODE=1 \
        -DENABLE_DOCS=0 -DENABLE_EXAMPLES=0 -DENABLE_TESTS=0 -DENABLE_TOOLS=0 -DCONFIG_TUNE_VMAF=0 \
        -DCMAKE_ASM_NASM_COMPILER="$TOOLS/bin/nasm" "${aom_cmake[@]}" \
        && make -s -j"$JOBS" && make -s install) >"$s/aom.log" 2>&1 || { tail -30 "$s/aom.log"; exit 1; }

    log "[$t] ffmpeg"
    unpack "$DL/ffmpeg-9.1.tar.xz" "$s/ffmpeg"
    local filters=buffer,buffersink,abuffer,abuffersink,format,aformat,null,anull,copy,scale,setsar,split,palettegen
    filters+=,paletteuse,alphamerge,alphaextract,premultiply,aresample,atrim,trim,setpts,asetpts,color,overlay,crop,pad
    (cd "$s/ffmpeg" && ./configure --prefix="$p" "${ff[@]}" --pkg-config=pkg-config --pkg-config-flags=--static \
        --extra-cflags="-I$p/include" --extra-ldflags="-L$p/lib" --extra-libs="-lpthread -lm" \
        --enable-gpl --enable-static --disable-shared --disable-autodetect --disable-debug --disable-doc \
        --disable-network --disable-ffplay --disable-everything --enable-zlib \
        --enable-libx264 --enable-libvpx --enable-libaom --enable-libopus --enable-libwebp \
        --enable-protocol=file,pipe \
        --enable-demuxers --enable-decoders --enable-parsers --enable-bsfs \
        --enable-encoder=gif,png,mjpeg,libwebp,libwebp_anim,libx264,libvpx_vp9,libaom_av1,aac,libopus,wrapped_avframe \
        --enable-muxer=gif,mp4,webm,avif,webp,image2,null \
        --enable-filter=$filters \
        && make -s -j"$JOBS" && make -s install) >"$s/ffmpeg.log" 2>&1 || { tail -40 "$s/ffmpeg.log"; exit 1; }
    echo "$stamp" >"$CACHE/$t/stamp"
}

# --- Packages -----------------------------------------------------------------------------
# Models: everything in models.txt (licenses in THIRD-PARTY-NOTICES.md)
add_models() {
    mkdir -p "$1"
    sed '/^#/d; /^$/d' "$HERE/models.txt" | while read -r name _; do cp "$DL/models/$name" "$1/"; done
}

add_common() {   # add_common DIR TARGET: licenses, notices and the icon
    local d=$1 t=$2 l=$1/licenses s=$CACHE/$2/src
    mkdir -p "$l"
    cp "$ROOT/LICENSE" "$d/LICENSE.txt"
    cp "$s/ffmpeg/COPYING.GPLv2" "$l/ffmpeg-GPL-2.0.txt"
    cp "$s/ffmpeg/LICENSE.md" "$l/ffmpeg-LICENSE.md"
    cp "$s/x264/COPYING" "$l/x264-GPL-2.0.txt"
    cp "$s/libvpx/LICENSE" "$l/libvpx-LICENSE.txt"; cp "$s/libvpx/PATENTS" "$l/libvpx-PATENTS.txt"
    cp "$s/aom/LICENSE" "$l/libaom-LICENSE.txt"; cp "$s/aom/PATENTS" "$l/libaom-PATENTS.txt"
    cp "$s/opus/COPYING" "$l/opus-LICENSE.txt"
    cp "$s/zlib/LICENSE" "$l/zlib-LICENSE.txt"
    cp "$s/libwebp/COPYING" "$l/libwebp-LICENSE.txt"; cp "$s/libwebp/PATENTS" "$l/libwebp-PATENTS.txt"
    python3 -m zipfile -e "$DL/upscayl-bin-linux.zip" "$CACHE/upscayl-lic"
    cp "$CACHE"/upscayl-lic/*/LICENSE "$l/upscayl-ncnn-AGPL-3.0.txt"; rm -rf "$CACHE/upscayl-lic"
    cp "$DL/Real-ESRGAN-LICENSE" "$l/Real-ESRGAN-models-BSD-3-Clause.txt"
    cp "$DL/CC-BY-4.0.txt" "$l/models-CC-BY-4.0.txt"
    cp "$DL/CC-BY-NC-SA-4.0.txt" "$l/models-CC-BY-NC-SA-4.0.txt"
    cp "$DL/WTFPL.txt" "$l/models-WTFPL.txt"
    sed "s/@VERSION@/$VERSION/g" "$HERE/THIRD-PARTY-NOTICES.md" >"$d/THIRD-PARTY-NOTICES.md"
}

extract_one() {  # extract_one ZIP MEMBER-SUFFIX DEST
    python3 - "$@" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
m = [n for n in z.namelist() if n.endswith(sys.argv[2])][0]
open(sys.argv[3], "wb").write(z.read(m))
PY
}

package_linux() {
    local name=upscale-gif-$VERSION-linux-x86_64 d
    d=$CACHE/pkg/$name; rm -rf "$d"; mkdir -p "$d/bin"
    log "Packaging $name"
    install -m755 "$ROOT/upscale-gif" "$d/upscale-gif"
    install -m755 "$HERE/linux/install.sh" "$d/install.sh"
    cp "$HERE/linux/README.txt" "$d/README.txt"
    cp "$HERE/icon.svg" "$HERE/icon.png" "$d/"
    extract_one "$DL/upscayl-bin-linux.zip" /upscayl-bin "$d/bin/upscayl-bin"
    cp "$CACHE/linux/prefix/bin/ffmpeg" "$CACHE/linux/prefix/bin/ffprobe" "$d/bin/"
    strip "$d/bin/ffmpeg" "$d/bin/ffprobe"
    chmod 755 "$d/bin/"*
    add_models "$d/models"
    add_common "$d" linux
    tar -C "$CACHE/pkg" -czf "$DIST/$name.tar.gz" --owner=0 --group=0 "$name"
}

package_windows() {
    local name=upscale-gif-$VERSION-windows-x64 d f
    d=$CACHE/pkg/$name; rm -rf "$d"; mkdir -p "$d/bin"
    log "Packaging $name"
    for f in upscale-gif.ps1 install.ps1 Install.cmd "Upscale GIF.cmd" README.txt; do cp "$ROOT/windows/$f" "$d/$f"; done
    sed -i "s/^\$Version = 'dev'/\$Version = '$VERSION'/" "$d/install.ps1"
    cp "$HERE/icon.ico" "$d/upscale-gif.ico"
    extract_one "$DL/upscayl-bin-windows.zip" /upscayl-bin.exe "$d/bin/upscayl-bin.exe"
    # Microsoft's OpenMP runtime, which upscayl-bin.exe needs (redistributable)
    extract_one "$DL/realesrgan-ncnn-vulkan-windows.zip" vcomp140.dll "$d/bin/vcomp140.dll"
    cp "$CACHE/windows/prefix/bin/ffmpeg.exe" "$CACHE/windows/prefix/bin/ffprobe.exe" "$d/bin/"
    "$CACHE/llvm-mingw/bin/x86_64-w64-mingw32-strip" "$d/bin/ffmpeg.exe" "$d/bin/ffprobe.exe"
    add_models "$d/models"
    add_common "$d" windows
    mv "$d/THIRD-PARTY-NOTICES.md" "$d/THIRD-PARTY-NOTICES.txt"
    # Windows text files: CRLF line endings
    find "$d" -maxdepth 2 \( -name '*.ps1' -o -name '*.cmd' -o -name '*.txt' -o -name '*.md' \) -print0 \
        | xargs -0 sed -i 's/\r*$/\r/'
    rm -f "$DIST/$name.zip"
    (cd "$CACHE/pkg" && python3 -m zipfile -c "$DIST/$name.zip" "$name")
}

package_sources() {
    local name=upscale-gif-$VERSION-sources d
    d=$CACHE/pkg/$name; rm -rf "$d"; mkdir -p "$d"
    log "Packaging $name"
    cp "$DL/ffmpeg-9.1.tar.xz" "$DL/$X264.tar.bz2" "$DL/libvpx-1.17.0.tar.gz" "$DL/libaom-3.15.3.tar.gz" \
        "$DL/opus-1.6.1.tar.gz" "$DL/zlib-1.4.tar.gz" "$DL/libwebp-1.6.0.tar.gz" "$DL/upscayl-ncnn-20251207-174704.tar.gz" "$d/"
    mkdir -p "$d/packaging"; cp "$HERE/sources.txt" "$HERE/models.txt" "$HERE/build.sh" "$d/packaging/"
    cat >"$d/README.txt" <<EOF
Source code of the GPL and AGPL programs bundled with upscale-gif $VERSION:

  ffmpeg 9.1 (GPL-2.0-or-later, with x264), x264, libvpx, libaom, opus, libwebp and zlib: built
    statically into bin/ffmpeg and bin/ffprobe by packaging/build.sh
  upscayl-ncnn 20251207-174704 (AGPL-3.0): bin/upscayl-bin, unmodified
    (the release binary from https://github.com/upscayl/upscayl-ncnn)

packaging/build.sh and packaging/sources.txt rebuild the packages from these sources.
EOF
    tar -C "$CACHE/pkg" -czf "$DIST/$name.tar.gz" --owner=0 --group=0 "$name"
}

for t in "${TARGETS[@]}"; do
    case $t in
        linux | windows) build_ffmpeg "$t"; "package_$t" ;;
        *) echo "unknown target: $t" >&2; exit 1 ;;
    esac
done
package_sources
log "Done"
ls -la "$DIST"/upscale-gif-"$VERSION"-*
