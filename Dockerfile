# syntax=docker/dockerfile:1
#
# glOSports: Minecraft Bedrock (Android APK) for goodluckOS / GA36-MB (Allwinner A33)
#
# This packages the community PortMaster port "mcpelauncher-r36s" (AArch64/ARMv7)
# into the goodluckOS "ports/<name>" + Puppy launcher layout, with the PortMaster
# runtime dependency replaced by a small in-port shim.
#
#   docker buildx build --output type=local,dest=./out .
#
FROM debian:bookworm AS builder

# --- armhf build/runtime tooling -------------------------------------------
# We do not compile the game. We only need:
#   * armhf ELF tools (objdump) to walk the shared-library closure of LÖVE
#   * armhf LÖVE dependencies from Debian (the launcher menu is written in Lua)
RUN dpkg --add-architecture armhf && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        unzip \
        zip \
        file \
        bzip2 \
        make \
        pkg-config \
        crossbuild-essential-armhf \
        binutils-arm-linux-gnueabihf \
        libluajit-5.1-2:armhf \
        libopenal1:armhf \
        libmodplug1:armhf \
        libmpg123-0:armhf \
        libogg0:armhf \
        libogg-dev:armhf \
        libvorbisfile3:armhf \
        zlib1g:armhf \
        libstdc++6:armhf \
        libgcc-s1:armhf && \
    rm -rf /var/lib/apt/lists/*

# --- pinned upstream inputs ------------------------------------------------
ARG MCPE_VERSION=1.7.0
ARG MCPE_SHA256=813df5256f7766912b66eb93b2624bae5b5fa6805fcd301dd4ff780d993bc564

# LÖVE 11.5 armhf runtime as shipped by PortMaster (single self-contained
# binary). Pinned by SHA-256 so the port cannot change under our feet.
ARG LOVE_URL=https://raw.githubusercontent.com/PortsMaster/PortMaster-New/main/ports/drilbertiidiggeredoo/drilbertiidiggeredoo/bin/love.armhf
ARG LOVE_SHA256=aae38077ae31913c6e9a573b67e377d69dba99b09b5a4e7331829b09e86b6423

WORKDIR /download
RUN curl -fsSL -o port.zip \
        "https://github.com/impressivestay6355-cmyk/mcpelauncher-r36s/releases/download/${MCPE_VERSION}/McpeLauncher-Port.zip" && \
    echo "${MCPE_SHA256}  port.zip" | sha256sum -c - && \
    curl -fsSL -o love.armhf "${LOVE_URL}" && \
    echo "${LOVE_SHA256}  love.armhf" | sha256sum -c - && \
    file love.armhf | grep -q 'ELF 32-bit' && \
    sha256sum port.zip love.armhf > /download/INPUTS.sha256

# --- libtheora without Debian's cairo/X11 baggage --------------------------
# Debian's libtheora0 links libcairo2, which drags in X11, xcb, pixman and
# fontconfig — none of which exist on a KMSDRM handheld. LÖVE only uses the
# decoder, so build upstream 1.1.1 with everything else switched off.
ARG THEORA_URL=https://downloads.xiph.org/releases/theora/libtheora-1.1.1.tar.bz2
ARG THEORA_SHA256=b6ae1ee2fa3d42ac489287d3ec34c5885730b1296f0801ae577a35193d3affbc
RUN set -eu; \
    curl -fsSL -o /tmp/libtheora.tar.bz2 "${THEORA_URL}"; \
    echo "${THEORA_SHA256}  /tmp/libtheora.tar.bz2" | sha256sum -c -; \
    mkdir -p /tmp/theora; \
    tar xf /tmp/libtheora.tar.bz2 -C /tmp/theora --strip-components=1; \
    cd /tmp/theora; \
    ./configure --host=arm-linux-gnueabihf --prefix=/opt/theora \
        --disable-asm --disable-examples --disable-encode \
        --disable-spec --disable-vorbistest; \
    make -j"$(nproc)"; \
    make install; \
    rm -rf /tmp/theora /tmp/libtheora.tar.bz2

# --- stage the HOME overlay ------------------------------------------------
RUN mkdir -p /output/ports/minecraft-bedrock && \
    unzip -q port.zip -d /output/ports/minecraft-bedrock && \
    rm -rf /output/ports/minecraft-bedrock/mcpe_launcher/mcpelauncher/arm64 \
           /output/ports/minecraft-bedrock/mcpe_launcher/menu/update \
           /output/ports/minecraft-bedrock/mcpe_launcher/UpdatePort.sh

COPY overlay/ /tmp/overlay/
COPY scripts/ /tmp/scripts/

RUN set -eu; \
    ROOT=/output/ports/minecraft-bedrock; \
    cp /tmp/overlay/menu/main.lua "$ROOT/mcpe_launcher/menu/main.lua"; \
    cp -a /tmp/overlay/shim "$ROOT/shim"; \
    mkdir -p "$ROOT/love"; \
    cp /tmp/overlay/love/run-love.sh "$ROOT/love/run-love.sh"; \
    cp /tmp/overlay/start.sh "$ROOT/start.sh"; \
    cp /download/love.armhf "$ROOT/love/love"; \
    EXTRA_LIBDIRS=/opt/theora/lib \
        sh /tmp/scripts/collect-libs.sh "$ROOT/love/love" "$ROOT/love/lib"; \
    test -f "$ROOT/love/lib/libtheoradec.so.1"; \
    if arm-linux-gnueabihf-objdump -p "$ROOT/love/lib/libtheoradec.so.1" | grep -q cairo; then \
        echo "ERROR: bundled libtheoradec still links cairo" >&2; exit 1; \
    fi; \
    for bad in libc.so.6 libm.so.6 ld-linux-armhf.so.3 libSDL2-2.0.so.0 \
               libEGL.so.1 libGLESv2.so.2 libgbm.so.1 libdrm.so.2 \
               libfreetype.so.6 libcairo.so.2 libX11.so.6 libasound.so.2; do \
        if [ -e "$ROOT/love/lib/$bad" ]; then \
            echo "ERROR: $bad must not be bundled" >&2; exit 1; \
        fi; \
    done; \
    missing=0; \
    for n in $(arm-linux-gnueabihf-objdump -p "$ROOT/love/love" | awk '/NEEDED/ { print $2 }'); do \
        case "$n" in \
            libc.so.6|libm.so.6|libpthread.so.0|libdl.so.2|librt.so.1) continue ;; \
            ld-linux-armhf.so.3|libSDL2-2.0.so.0|libfreetype.so.6) continue ;; \
        esac; \
        if [ ! -e "$ROOT/love/lib/$n" ]; then \
            echo "ERROR: love needs $n but it is not bundled" >&2; missing=1; \
        fi; \
    done; \
    [ "$missing" = 0 ] || exit 1; \
    sh /tmp/scripts/patch-port.sh "$ROOT"; \
    rm -rf /tmp/overlay /tmp/scripts

# --- launcher entry + icon -------------------------------------------------
RUN mkdir -p /output/.local/share/applications /output/.local/share/icons
COPY launcher/minecraft-bedrock.puppy /output/.local/share/applications/minecraft-bedrock.puppy
COPY icon/minecraft-bedrock.png      /output/.local/share/icons/minecraft-bedrock.png

# --- licences / notices (upstream zip does not carry them) -----------------
RUN mkdir -p /output/ports/minecraft-bedrock/licenses && \
    for f in LICENSE LEGAL.md CREDITS.md THIRD_PARTY_NOTICES.md TRADEMARKS.md GETTING-APKS.md TESTING.md; do \
        curl -fsSL -o "/output/ports/minecraft-bedrock/licenses/$f" \
            "https://raw.githubusercontent.com/impressivestay6355-cmyk/mcpelauncher-r36s/refs/tags/${MCPE_VERSION}/$f" || \
        curl -fsSL -o "/output/ports/minecraft-bedrock/licenses/$f" \
            "https://raw.githubusercontent.com/impressivestay6355-cmyk/mcpelauncher-r36s/main/$f"; \
    done

COPY THIRD_PARTY.md /output/ports/minecraft-bedrock/THIRD_PARTY.md
COPY BUILD-INFO.txt /output/ports/minecraft-bedrock/build-info.txt

RUN printf 'Kendi Minecraft Bedrock APK dosyalarini bu klasore koy:\n  mcpe_launcher/Setup Apk/\n\nAPK yoksa menu acilir ama oynanacak surum listelenmez.\n' \
        > "/output/ports/minecraft-bedrock/mcpe_launcher/Setup Apk/PutApkHere.txt"

# --- package ---------------------------------------------------------------
WORKDIR /output
RUN zip -q -r -9 /minecraft-bedrock-port.zip . && \
    unzip -l /minecraft-bedrock-port.zip | tail -n 3

FROM scratch AS export
COPY --from=builder /minecraft-bedrock-port.zip /
