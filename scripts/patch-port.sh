#!/bin/sh
# Adapt the upstream PortMaster port (mcpelauncher-r36s) to goodluckOS.
#
# The upstream launcher is a bash script that assumes PortMaster: control.txt,
# device_info.txt, get_controls, gptokeyb, ESUDO, a PortMaster LÖVE runtime and
# /roms/ports paths. goodluckOS has BusyBox ash, no bash, no PortMaster, no
# gptokeyb and no LÖVE. This script makes the smallest set of edits needed:
#
#   * bash -> POSIX sh (BusyBox ash)
#   * source -> .
#   * PortMaster control folder -> in-port shim/ (see overlay/shim)
#   * drop the EmulationStation button-inversion detection (bash process
#     substitution); default to A=confirm, which matches goodluckOS
#   * force C.UTF-8 (goodluckOS has no `locale`, upstream falls back to "C")
#   * banner writes to stderr instead of /dev/tty1 (player cannot write tty1)
#   * skip privileged /proc tweaks (doas does not permit them)
set -eu

ROOT=${1:?usage: patch-port.sh <port-root>}
SH="$ROOT/McpeLauncher.sh"
SETUP="$ROOT/mcpe_launcher/SetupMcpe.sh"
MENU="$ROOT/mcpe_launcher/menu/main.lua"

die() { echo "patch-port: $*" >&2; exit 1; }

[ -f "$SH" ]    || die "missing $SH"
[ -f "$SETUP" ] || die "missing $SETUP"
[ -f "$MENU" ]  || die "missing $MENU"

# --- 1. POSIX shell ---------------------------------------------------------
sed -i '1s|^#!/bin/bash$|#!/bin/sh|' "$SH"
sed -i '1s|^#!/bin/bash$|#!/bin/sh|' "$SETUP"

# Every `bash` invocation becomes `sh` (recovery, re-exec, SetupMcpe, updater).
sed -i 's/\<bash\>/sh/g' "$SH"

# `source` is a bashism; BusyBox ash only guarantees `.`
sed -i 's/\<source\>/. /g' "$SH"

# --- 2. PortMaster -> in-port shim -----------------------------------------
sed -i 's|^  controlfolder="/roms/ports/PortMaster"$|  controlfolder="$SCRIPT_DIR/shim"|' "$SH"
grep -q 'controlfolder="$SCRIPT_DIR/shim"' "$SH" || die "controlfolder redirect failed"

# --- 3. drop EmulationStation confirm-button detection ---------------------
# It uses `< <(...)` process substitution, which ash does not have.
awk '
    /^mcpe_detect_confirm\(\) \{/ { skip = 1 }
    skip == 1 && /^export MCPE_CONFIRM_SDL MCPE_CONFIRM_LABEL$/ {
        print "export MCPE_CONFIRM_SDL=a"
        print "export MCPE_CONFIRM_LABEL=A"
        skip = 0
        next
    }
    skip == 1 { next }
    { print }
' "$SH" > "$SH.tmp"
mv "$SH.tmp" "$SH"
grep -q 'mcpe_detect_confirm' "$SH" && die "confirm-button block still present"
! grep -q '< <(' "$SH" || die "process substitution left in launcher"

# --- 4. UTF-8 --------------------------------------------------------------
# Upstream ends with MCPE_LANG_RESOLVED=C when `locale` is missing; Bedrock
# wants a UTF-8 locale for world/player names.
sed -i 's|^mcpe_select_utf8_locale$|mcpe_select_utf8_locale\nMCPE_LANG_RESOLVED=C.UTF-8|' "$SH"
grep -q '^MCPE_LANG_RESOLVED=C.UTF-8$' "$SH" || die "locale override failed"

# --- 5. SetupMcpe banner ---------------------------------------------------
# appctl runs us without a controlling tty; `exec > /dev/tty1` would make the
# whole setup script exit because of `set -e`.
sed -i 's|^\( *\)exec > /dev/tty1$|\1exec >\&2|' "$SETUP"
! grep -q 'exec > /dev/tty1' "$SETUP" || die "tty redirect not patched"

# --- 6. privileged / slow tweaks ------------------------------------------
# Harmless to fail, but they spam the log on every launch.
sed -i 's|^echo 3 .*drop_caches.*$|:|' "$SH"

# `chmod -R 777` walks the whole ~1 GB asset tree on every launch (upstream
# does this because PortMaster's FAT /roms partition loses modes).  The HOME
# partition is ext4 and everything is already owned by "player", so skip it.
sed -i 's|^\( *\)\$ESUDO chmod -R 777 "\$GAMEDIR/mcpelauncher"$|\1:|' "$SH"
! grep -q 'chmod -R 777' "$SH" || die "chmod -R 777 not removed"

# --- 7. sanity checks ------------------------------------------------------
grep -q '^export MCPE_CONFIRM_SDL=a$' "$SH" || die "confirm env missing"
grep -q 'sh -x "\$GAMEDIR/SetupMcpe.sh"' "$SH" || die "SetupMcpe invocation not converted"
! grep -q '\<bash\>' "$SH" || die "bash invocation left in launcher"
! grep -q '\<source\>' "$SH" || die "source builtin left in launcher"

echo "--- patched launcher head ---"
sed -n '1,20p' "$SH"
echo "--- end of patch-port ---"
