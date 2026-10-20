#!/bin/sh
# goodluckOS entry point for Minecraft Bedrock (mcpelauncher).
#
#   Puppy -> appctl -> su -l player -> sh /home/player/ports/minecraft-bedrock/start.sh
#
# Files copied to the SD card from Windows/MTP lose their executable bit, so
# every ELF we are about to run gets +x here. The HOME partition is ext4, so
# chmod works for the "player" user.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# chmod one file at a time: BusyBox chmod stops at the first missing operand on
# some builds, and a fresh install legitimately lacks some of these files.
for f in \
    "$ROOT/McpeLauncher.sh" \
    "$ROOT/mcpe_launcher/SetupMcpe.sh" \
    "$ROOT/mcpe_launcher/mcpelauncher/armhf/mcpelauncher-client" \
    "$ROOT/love/love"
do
    if [ -f "$f" ]; then
        chmod +x "$f" 2>/dev/null || true
    fi
done

# goodluckOS is KMSDRM-only (no X11, no Wayland, no window manager).
export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-kmsdrm}"
export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-alsa}"

# The launcher spawns LÖVE with these; keep them consistent for both.
export SDL_VIDEO_KMSDRM_DOUBLE_BUFFER=1

exec sh "$ROOT/McpeLauncher.sh"
