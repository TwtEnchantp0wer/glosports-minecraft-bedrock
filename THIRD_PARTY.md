# Third-party components

This repository contains only build recipes and small shim scripts.
The produced zip contains the following third-party software:

| Component | Version | Licence | Source |
| --- | --- | --- | --- |
| mcpelauncher-r36s (launcher scripts, menu, PortMaster packaging) | 1.7.0 | GPL-3.0 | <https://github.com/impressivestay6355-cmyk/mcpelauncher-r36s> |
| mcpelauncher (`mcpelauncher-client`, `libc-shim`, bionic shims) | build shipped by the above | GPL-3.0 + AOSP notices | <https://github.com/minecraft-linux/mcpelauncher-manifest> |
| LÖVE | 11.5 (armhf, PortMaster runtime) | zlib | <https://love2d.org> |
| LuaJIT | 2.1 (Debian armhf) | MIT | <https://luajit.org> |
| OpenAL Soft | Debian bookworm armhf | LGPL-2.0-or-later | <https://openal-soft.org> |
| libmodplug | Debian bookworm armhf | Public domain | <https://modplug-xmms.sourceforge.net> |
| mpg123 | Debian bookworm armhf | LGPL-2.1 | <https://www.mpg123.de> |
| libogg / libvorbis | Debian bookworm armhf | BSD-3-Clause | <https://xiph.org> |
| libtheora | 1.1.1, built in the image (decoder only, no cairo/X11) | BSD-3-Clause | <https://xiph.org> |
| libstdc++ / libgcc_s | Debian bookworm armhf (GCC 12 runtime) | GPL-3.0 with GCC Runtime Library Exception | <https://gcc.gnu.org> |

The upstream release zip itself carries `licenses/`, `LEGAL.md`, `CREDITS.md`,
`THIRD_PARTY_NOTICES.md` and `TRADEMARKS.md`; the Dockerfile copies those from
the pinned tag into `ports/minecraft-bedrock/licenses/`.

**No Minecraft game files are included.** Minecraft is a trademark of Mojang
Studios / Microsoft. This port is not affiliated with or endorsed by them.
