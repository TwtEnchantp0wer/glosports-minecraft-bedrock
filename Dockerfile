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
# --- mcpelauncher-client for ARMv7 -----------------------------------------
# Upstream ships an armhf client compiled for Cortex-A35 (ARMv8-A in AArch32
# mode). The A33's Cortex-A7 is plain ARMv7-A, so that binary dies with
# "Illegal instruction" (SIGILL) before it prints anything.
# We rebuild the client natively in an armhf userland (QEMU) and let Debian's
# default armv7 toolchain do the work. SDL3 is vendored by the project and is
# built with the KMSDRM backend goodluckOS needs.
FROM --platform=linux/arm/v7 debian:bookworm AS mcpelauncher-armhf

ARG MCPELAUNCHER_REF=91220f0f7ccfd460090d14056ab1bf12e82869b1

# Upstream's CI builds with clang; GCC 12 rejects the bionic headers
# (_Atomic in C++ / -fpermissive diagnostics) that libc-shim and the linker use.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates git cmake make g++ clang libatomic1 pkg-config \
        libssl-dev zlib1g-dev libpng-dev libdrm-dev libgbm-dev \
        libegl1-mesa-dev libgles2-mesa-dev libudev-dev libevdev-dev \
        libasound2-dev libdbus-1-dev libzip-dev libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/minecraft-linux/mcpelauncher-manifest /src && \
    cd /src && \
    git checkout "${MCPELAUNCHER_REF}" && \
    git submodule update --init --recursive --depth 1

RUN cmake -S /src -B /build -G "Unix Makefiles" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER=clang \
        -DCMAKE_CXX_COMPILER=clang++ \
        -DCMAKE_ASM_FLAGS="-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard" \
        -DCMAKE_C_FLAGS="-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard" \
        -DCMAKE_CXX_FLAGS="-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard" \
        -DCMAKE_EXE_LINKER_FLAGS=-latomic \
        -DBUILD_UI=OFF \
        -DBUILD_WEBVIEW=OFF \
        -DGAMEWINDOW_SYSTEM=SDL3 \
        -DUSE_SDL3_AUDIO=ON \
        -DSDL_KMSDRM=ON \
        -DSDL_X11=OFF \
        -DSDL_WAYLAND=OFF \
        -DSDL_UNIX_CONSOLE_BUILD=ON \
        -DSDL_TESTS=OFF \
        -DSDL_EXAMPLES=OFF \
        -DUSE_GAMECONTROLLERDB=OFF \
        -DENABLE_DEV_PATHS=OFF && \
    ( cfg=$(grep -rls --include='SDL_build_config.h' 'define SDL_VIDEO_DRIVER_KMSDRM 1' /build | head -n 1); \
      if [ -n "$cfg" ]; then echo "KMSDRM enabled: $cfg"; \
      else echo 'ERROR: SDL3 KMSDRM disabled (needs libdrm + gbm + EGL)'; exit 1; fi ) && \
    cmake --build /build --target mcpelauncher-client -j"$(nproc)"

RUN install -Dm755 /build/mcpelauncher-client/mcpelauncher-client \
        /opt/mcpelauncher/mcpelauncher-client ; \
    echo '=== readelf -A ===' ; \
    readelf -A /opt/mcpelauncher/mcpelauncher-client ; \
    echo '=== kmsdrm matches ===' ; \
    strings /opt/mcpelauncher/mcpelauncher-client | grep -ci kmsdrm ; \
    echo '=== cortex matches ===' ; \
    strings /opt/mcpelauncher/mcpelauncher-client | grep -ci cortex ; \
    echo '=== assert ===' ; \
    readelf -A /opt/mcpelauncher/mcpelauncher-client | grep -q 'Tag_CPU_arch: v7' && \
    strings /opt/mcpelauncher/mcpelauncher-client | grep -qi 'kmsdrm'

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
        libgcc-s1:armhf \
        libatomic1:armhf \
        libssl3:armhf \
        libpng16-16:armhf && \
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
           /output/ports/minecraft-bedrock/mcpe_launcher/UpdatePort.sh \
           /output/ports/minecraft-bedrock/mcpe_launcher/lib/armhf-system \
           /output/ports/minecraft-bedrock/mcpe_launcher/lib/armeabi-v7a/libgbm.so.1 \
           /output/ports/minecraft-bedrock/mcpe_launcher/lib/armeabi-v7a/libgbm.so.1.0.0

COPY overlay/ /tmp/overlay/
COPY scripts/ /tmp/scripts/
COPY --from=mcpelauncher-armhf /opt/mcpelauncher/mcpelauncher-client /tmp/mcpelauncher-client

RUN set -eu; \
    ROOT=/output/ports/minecraft-bedrock; \
    install -m 0755 /tmp/mcpelauncher-client \
        "$ROOT/mcpe_launcher/mcpelauncher/armhf/mcpelauncher-client"; \
    PROFILE=client sh /tmp/scripts/collect-libs.sh \
        "$ROOT/mcpe_launcher/mcpelauncher/armhf/mcpelauncher-client" \
        "$ROOT/mcpe_launcher/lib/armhf-system"; \
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
    CLIENT="$ROOT/mcpe_launcher/mcpelauncher/armhf/mcpelauncher-client"; \
    arm-linux-gnueabihf-readelf -A "$CLIENT" | grep -q 'Tag_CPU_arch: v7' || { \
        echo "ERROR: mcpelauncher-client is not ARMv7 (would SIGILL on Cortex-A7)" >&2; exit 1; }; \
    for bad in libc.so.6 libm.so.6 ld-linux-armhf.so.3 libSDL2-2.0.so.0 \
               libEGL.so.1 libGLESv2.so.2 libgbm.so.1 libdrm.so.2 libasound.so.2; do \
        if [ -e "$ROOT/mcpe_launcher/lib/armhf-system/$bad" ]; then \
            echo "ERROR: $bad must not be bundled (client)" >&2; exit 1; \
        fi; \
    done; \
    for n in $(arm-linux-gnueabihf-objdump -p "$CLIENT" | awk '/NEEDED/ { print $2 }'); do \
        case "$n" in \
            libc.so.6|libm.so.6|libpthread.so.0|libdl.so.2|librt.so.1) continue ;; \
            ld-linux-armhf.so.3|libEGL.so.1|libGLESv2.so.2|libgbm.so.1) continue ;; \
            libdrm.so.2|libasound.so.2) continue ;; \
        esac; \
        if [ ! -e "$ROOT/mcpe_launcher/lib/armhf-system/$n" ]; then \
            echo "ERROR: client needs $n but it is not bundled" >&2; missing=1; \
        fi; \
    done; \
    [ "$missing" = 0 ] || exit 1; \
    sh /tmp/scripts/patch-port.sh "$ROOT"; \
    cp /tmp/overlay/McpeLauncher.sh "$ROOT/McpeLauncher.sh"; \
    cp /tmp/overlay/SetupMcpe.sh "$ROOT/mcpe_launcher/SetupMcpe.sh"; \
    cp /tmp/overlay/netrun.sh "$ROOT/mcpe_launcher/netrun.sh"; \
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
