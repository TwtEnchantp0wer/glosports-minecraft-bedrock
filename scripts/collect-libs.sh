#!/bin/sh
# Walk the DT_NEEDED closure of an armhf ELF and copy every non-system library
# into <dest>. Run inside the Debian bookworm armhf multiarch container.
#
#   collect-libs.sh <binary> <dest>
#
# EXTRA_LIBDIRS (optional) is searched first, e.g. a libtheora we built
# ourselves without Debian's accidental cairo/X11 dependency.
#
# Blocklisted: glibc, SDL2 and the graphics stack. goodluckOS provides those
# (Mesa Lima + Buildroot SDL2); bundling them would shadow the system ones.
set -eu

BIN=${1:?usage: collect-libs.sh <binary> <dest>}
DEST=${2:?usage: collect-libs.sh <binary> <dest>}

LIBDIRS="${EXTRA_LIBDIRS:-} /usr/lib/arm-linux-gnueabihf /lib/arm-linux-gnueabihf"

BLOCK="libc.so.6 libm.so.6 libpthread.so.0 libdl.so.2 librt.so.1 libresolv.so.2
libnsl.so.1 libutil.so.1 libanl.so.1 libcrypt.so.1 libBrokenLocale.so.1
ld-linux-armhf.so.3
libSDL2-2.0.so.0
libEGL.so.1 libGLESv2.so.2 libGLESv1_CM.so.1 libGL.so.1 libOpenGL.so.0
libgbm.so.1 libdrm.so.2
libwayland-client.so.0 libwayland-cursor.so.0 libwayland-egl.so.1
libxkbcommon.so.0 libX11.so.6 libXext.so.6 libXcursor.so.1 libXi.so.6
libXrandr.so.2 libXss.so.1 libXfixes.so.3
libasound.so.2
libfreetype.so.6 libfontconfig.so.1"

# The list above is written across lines; flatten it, otherwise entries at the
# start/end of a line are not surrounded by spaces and the case match misses
# them (that is how freetype and ld-linux leaked into the first build).
BLOCK=$(printf '%s\n' "$BLOCK" | tr '\n' ' ')

mkdir -p "$DEST"
QUEUE="$BIN"
COPIED=" "

resolve() {
    for d in $LIBDIRS; do
        if [ -e "$d/$1" ]; then
            readlink -f "$d/$1"
            return 0
        fi
    done
    return 1
}

while [ -n "$QUEUE" ]; do
    f=$(printf '%s\n' "$QUEUE" | head -n 1)
    QUEUE=$(printf '%s\n' "$QUEUE" | tail -n +2)
    [ -n "$f" ] || continue

    for n in $(arm-linux-gnueabihf-objdump -p "$f" | awk '/NEEDED/ { print $2 }'); do
        case " $BLOCK " in
            *" $n "*) continue ;;
        esac
        case "$COPIED" in
            *" $n "*) continue ;;
        esac

        if ! real=$(resolve "$n"); then
            echo "WARN: $n required by $(basename "$f") not found in $LIBDIRS" >&2
            continue
        fi

        base=$(basename "$real")
        cp -f "$real" "$DEST/$base"
        if [ "$base" != "$n" ]; then
            ln -sf "$base" "$DEST/$n"
        fi
        COPIED="$COPIED$n $base "
        QUEUE="$QUEUE
$real"
    done
done

echo "--- bundled libraries ($(ls -1 "$DEST" | wc -l) entries) ---"
ls -l "$DEST"
