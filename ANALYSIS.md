# Upstream analizi: `impressivestay6355-cmyk/mcpelauncher-r36s`

Bu belge, portun neden bu kadar "shim" gerektirdiğini ve hangi kararların
nereden geldiğini kayıt altına alır. Kod tarafı için `Dockerfile`,
`scripts/` ve `overlay/` klasörlerine bakın.

## 1. Upstream ne gönderiyor?

Sürüm **1.7.0** (13 MB `McpeLauncher-Port.zip`), 41 dosya:

```
McpeLauncher.sh                    21 KB  bash, tüm akış
mcpe_launcher/
  SetupMcpe.sh                     APK -> versions/<ad>/{lib,assets}
  UpdatePort.sh                    kendi kendini güncelleme (GitHub release)
  mcpelauncher/armhf/mcpelauncher-client   9.4 MB, ELF32 ARM hard-float
  mcpelauncher/armhf/lib/.../libc.so, libm.so, libsqliteX.so
  mcpelauncher/arm64/...           9.7 MB (A33'te gereksiz)
  lib/armeabi-v7a/libc++_shared.so 543 KB
  lib/armeabi-v7a/libgbm.so.1      gerçek gbm sarmalayıcı (10 KB)
  lib/armhf-system/                libcrypto/libssl 3, libatomic, libgcc_s
  menu/                            LÖVE 11.x Lua menüsü
  menu/wait/                       APK çıkarma splash'i
  menu/update/                     güncelleme UI'ı
  Setup Apk/, Import Skins/
```

### Çalışma akışı

1. `McpeLauncher.sh` PortMaster'ın `control.txt` / `device_info.txt` /
   `get_controls` fonksiyonlarını source eder, `$ESUDO`, `$GPTOKEYB`,
   `$sdl_controllerconfig`, `$DISPLAY_*` değerlerini alır.
2. `love.${DEVICE_ARCH}` (PortMaster runtime) ile `menu/` açılır; kullanıcı
   sürüm seçer veya `Setup Apk` ile APK kurar.
3. Seçim `menu/selected_version.txt` dosyasına yazılır, LÖVE çıkar.
4. `SetupMcpe.sh`: APK'dan `lib/armeabi-v7a/*` + `assets/*` çıkarır, bionic
   `libc.so`/`libm.so` shim'lerini kopyalar.
5. `mcpelauncher-client`, `-dg versions/<ad>` ile başlatılır:
   `XDG_DATA_HOME`, `HOME`, `LD_LIBRARY_PATH`, `SDL_GAMECONTROLLERCONFIG`,
   KMSDRM ve Mesa değişkenleri set edilir.

## 2. Binary gerçekleri (doğrulandı)

`ELF` başlıkları ve `DT_NEEDED` tabloları okunarak:

| Binary | Sınıf | ABI | İstediği glibc | Not |
| --- | --- | --- | --- | --- |
| `mcpelauncher-client` (armhf) | ELF32 ARM | hard-float | ≤ **2.30** | sadece `libc, libm, libpthread, libdl`; EGL/GLES/gbm/drm **dlopen** |
| `love.armhf` (PortMaster) | ELF32 ARM | hard-float | ≤ **2.33** | SDL2, freetype, openal, luajit, modplug, mpg123, theora, vorbis |
| `libc-shim.so` | ELF32 ARM | — | — | bionic libc shim (guest APK için) |

goodluckOS'un Buildroot 2026.08 glibc'si bunların ikisinden de yeni olduğu için
prebuilt binary'ler doğrudan çalışır. **Yine de** LÖVE'ün ses/kodek
bağımlılıkları goodluckOS'ta yok; bu yüzden `love/lib` altında taşınıyor.

`mcpelauncher-client` içindeki string'ler KMSDRM yolunu doğruluyor:

```
gbm_create_device / drmModeAddFB2 / eglGetPlatformDisplay / EGL_PLATFORM_GBM
"Disabling ImGui Overlay due to OpenGLES 2"
```

Yani oyun SDL'yi video için kullanmıyor; doğrudan GBM + EGL + GLES2 ile
konuşuyor. Mali-400/lima için doğru yol bu.

LÖVE tarafında `LOVE_GRAPHICS_USE_OPENGLES`, `essl1`, `glsl1on3` string'leri var:
PortMaster runtime'ı GLES'e düşebiliyor (Mali blob'lu cihazlarda desktop GL yok).

## 3. goodluckOS'ta kırılan varsayımlar

| Upstream varsayımı | goodluckOS | Etki | Çözüm |
| --- | --- | --- | --- |
| `#!/bin/bash`, `[[`, `< <(...)` | BusyBox ash | betik hiç başlamaz | `sh`'e çevir, process substitution bloğunu sil |
| `source` | ash'te yok | betik kaynağı yüklenmez | `.` |
| `/roms/ports`, `/opt/system/Tools/PortMaster` | yok | controlfolder bulunamaz | `$SCRIPT_DIR/shim` |
| `$ESUDO` = `sudo`/`doas` | doas sadece appctl/poweroff/... | root işlemleri sessizce fail | `ESUDO=""`, gereksizleri `:` yap |
| `$GPTOKEYB` | yok | komut bulunamaz | `GPTOKEYB=":"`, LÖVE native gamepad |
| `/dev/tty1` banner | `player` yazamaz | `set -e` yüzünden setup ölür | banner → stderr/log |
| `wget`/`curl` HTTPS | BusyBox wget TLS'siz | güncelleme çalışmaz | menüden kaldır, imajı yeniden build et |
| `stat` | BusyBox'ta yok | sadece boş alan kontrolü atlanır | upstream `|| echo 0` zaten var |
| `pkill` | yok | hata log'a düşer | `2>/dev/null` yeterli |
| `locale` | yok | `LANG=C` | `C.UTF-8` zorla |
| LÖVE runtime | yok | menü açılmaz | `love/` altında gömülü |

## 4. Alınan tasarım kararları

1. **Sistem SDL2/glibc/EGL/GLES/gbm/freetype kullanılır**, port içinde
   taşınmaz. Half-Life portundaki `rm -f libSDL*` kuralının devamı.
2. **LÖVE ve kodek bağımlılıkları gömülür** çünkü goodluckOS'ta hiçbiri yok.
   Kapanış `objdump -p` ile hesaplanır (`scripts/collect-libs.sh`), böylece
   Debian sürümü değişse bile eksik lib kalmaz.
3. **Kendini güncelleme kaldırılır.** Bir sonraki sürüm = yeni Docker build.
   Böylece hash-pin'li, tekrarlanabilir çıktı korunur.
4. **arm64 dizini silinir.** A33 kullanıcı alanı 32-bit; yanlışlıkla arm64 APK
   kurulmasını menü zaten engelliyor, diskte 12 MB taşımaya gerek yok.
5. **`chmod -R 777` her açılışta atlanır.** ext4'te gereksiz; 1 GB asset
   ağacında açılışı dakikalarca geciktiriyordu.
6. **`start.sh` exec bitlerini onarır.** Windows/MTP kopyalaması `+x` bırakmaz.

## 5. Fizibilite: A33 vs R36S

| | R36S (RK3326) | GA36-MB (A33) |
| --- | --- | --- |
| CPU | 4× Cortex-A53 1.3 GHz | 4× Cortex-A7 1.2 GHz |
| GPU | Mali-G31 (GLES3.2) | Mali-400 MP2 (GLES2.0) |
| RAM | 1 GB | 512 MB |
| APK | arm64 veya armhf | **sadece armhf** |
| Bedrock sürümü | 1.16+ (RenderDragon) denenebilir | 0.12–1.1.x gerçekçi |
| Beklenen FPS | 20–40 | 5–15 |

A33'te bu portun **çalışması** teknik olarak mümkün (glibc, GLES2, GBM yolları
uygun); **oynanabilir olması** yalnızca eski ve hafif APK'larla mümkün. Bu
yüzden `TESTING.md` önce menü + 0.14.x doğrulamasını istiyor.

## 6. Açık riskler

1. **LÖVE'ün KMSDRM/GLES yolu** lima'da test edilmedi. Mali blob'da çalışıyor;
   lima hem GL 2.1 hem GLES2 sunduğu için iki yoldan biri tutmalı.
2. **EGL/GBM mod seçimi**: mcpelauncher `-ww/-wh 640x480` alıyor; DRM'nin
   gerçek modu farklıysa (panel 1/2) siyah ekran olabilir. Log'da
   `gbm_surface_create` / `eglCreateWindowSurface` hatalarına bakın.
3. **RAM**: 512 MB'ta 1.16+ sürümler OOM. Bu bir yazılım hatası değil.
4. **Ses**: mcpelauncher `SDL_AUDIODRIVER=alsa` kullanıyor; goodluckOS'ta
   Pulse/PipeWire yok, doğrudan ALSA var. Bedrock 0.14'te ses yolu farklı
   olabilir.
5. **Zorla çıkış**: appctl cgroup'u SIGKILL ederse dünya kaydı bozulabilir.

## 7. Kaynaklar

- <https://github.com/impressivestay6355-cmyk/mcpelauncher-r36s>
- <https://github.com/minecraft-linux/mcpelauncher-manifest>
- <https://github.com/CodeZombie/goodluckOS>
- <https://github.com/CodeZombie/glOSports-half-life> (şablon)
- <https://github.com/PortsMaster/PortMaster-New> (LÖVE 11.5 armhf runtime)
