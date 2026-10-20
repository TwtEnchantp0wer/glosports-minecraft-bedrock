# glOSports: Minecraft Bedrock (mcpelauncher) for goodluckOS

`mcpelauncher-r36s` portunun **goodluckOS / GA36-MB (Allwinner A33)** sürümü.
Half-Life portuyla aynı fikri izler: Docker ile tek komut build, çıktı HOME
bölümünün köküne açılan tek bir zip, Puppy menüsünde tek girdi, oyun verisi
kullanıcıda kalır.

- Üst proje: <https://github.com/impressivestay6355-cmyk/mcpelauncher-r36s> (v1.7.0, GPL-3.0)
- Çekirdek: [minecraft-linux/mcpelauncher-manifest](https://github.com/minecraft-linux/mcpelauncher-manifest)
- Hedef: goodluckOS 0.1.x, 640×480, KMSDRM, armhf, Mali-400 MP2
- Upstream analizi ve tasarım kararları: [`ANALYSIS.md`](ANALYSIS.md)

> **Yasal:** Bu repoda Minecraft dosyası yoktur. Kendi Google Play hesabınızla
> satın aldığınız APK'yı kullanmanız gerekir. Mojang/Microsoft ile bağlantılı
> değildir.

---

## 1. Neden bu repo "sadece Dockerfile" değil?

Half-Life portunda upstream hazır bir armhf binary veriyordu; burada upstream
**PortMaster** için yazılmış bir bash betiği. goodluckOS'ta PortMaster'ın
sağladığı şeylerin hiçbiri yok:

| PortMaster varsayımı | goodluckOS gerçeği | Bu repodaki çözüm |
| --- | --- | --- |
| `/roms/ports/...` | `/home/player/ports/...` | `controlfolder` → port içi `shim/` |
| `control.txt`, `device_info.txt`, `get_controls` | yok | `shim/control.txt`, `shim/device_info.txt` |
| `bash` | BusyBox `ash` | betikler POSIX `sh`'e çevriliyor |
| `gptokeyb` | yok | menü `love.gamepadpressed`, oyun native gamepad kullanıyor |
| LÖVE 11.5 runtime | yok | `love/` altında armhf runtime + bağımlılıkları gömülü |
| `ESUDO` (root) | `doas` sadece appctl/poweroff/... izinli | `ESUDO=""`, gereksiz root satırları devre dışı |
| `/dev/tty1`'e banner | `player` yazamaz | banner stderr/log'a |
| Kendini güncelleme (`wget` + HTTPS + bash) | BusyBox wget HTTPS desteklemez | menüden kaldırıldı, güncelleme = yeniden build |
| SDL2 sistemden | Buildroot SDL2 KMSDRM | **sistem SDL2 kullanılır** (half-life ile aynı kural) |

---

## 2. Build

```bash
./build.sh
# ya da
docker buildx build --output type=local,dest=./out .
```

Çıktı: `out/minecraft-bedrock-port.zip`.

> Docker yoksa: repoyu GitHub'a atıp **Actions → build → Run workflow** çalıştır,
> `minecraft-bedrock-port` artifact'ını indir (`.github/workflows/build.yml`).

Girdiler SHA-256 ile pinli:

| Girdi | Sürüm/hash |
| --- | --- |
| `McpeLauncher-Port.zip` | 1.7.0 / `813df525…c564` |
| PortMaster LÖVE 11.5 armhf | `aae38077…6423` |

Build sırasında:

1. Upstream release zip'i indirilir, `ports/minecraft-bedrock/` altına açılır.
   `arm64/` (A33'te kullanılmaz), `UpdatePort.sh` ve `menu/update` silinir.
2. LÖVE 11.5 armhf + Debian bookworm armhf'ten bağımlılık kapanışı (`libluajit`,
   `libopenal`, `libmodplug`, `libmpg123`, `libvorbis`, `libtheora`, `libstdc++`…)
   `love/lib/` altına toplanır. **SDL2, glibc, EGL/GLES, gbm/drm ve freetype
   gömülmez** — bunlar goodluckOS'tan gelir. `libtheora` kaynaktan derlenir:
   Debian'ın paketi gereksiz yere `libcairo2` (→ X11/fontconfig) çekiyor.
3. `scripts/patch-port.sh` betikleri ash'e uyarlar (aşağıdaki bölüm).
4. `launcher/*.puppy` ve ikon HOME köküne yerleştirilir.
5. Lisans/notice dosyaları upstream etiketinden indirilir.
6. Her şey tek zip olarak paketlenir.

> Docker yoksa Windows'ta build edilemez; WSL2 + Docker Desktop yeterlidir.
> `build.sh` Linux/bash içindir (aynı half-life reposundaki gibi).

---

## 3. Kurulum (SD kart)

1. `out/minecraft-bedrock-port.zip` içeriğini HOME bölümünün **köküne** aç
   (içinde `ports/` ve `.local/` var; merge et).
2. APK'yı buraya koy (dosya adı menüde sürüm adı olur):

   ```
   ports/minecraft-bedrock/mcpe_launcher/Setup Apk/<sürüm>.apk
   ```

3. Puppy → **Ports → Minecraft Bedrock**.
4. Menüde `[ Setup Apk ]` → APK'yı seç → `ARM32` (A33 için tek seçenek).
5. Kurulum bitince sürüm listede görünür; seç ve başlat.

APK'yı kendiniz çıkarmanız gerekiyor: upstream `GETTING-APKS.md`
(`ports/minecraft-bedrock/licenses/` altında da var) veya
[mcbedrock-get](https://github.com/DankMiimer/mcbedrock-get) aracı.

---

## 4. Donanım gerçeği: A33'te ne çalışır?

GA36-MB / goodluckOS: **Cortex-A7 quad, Mali-400 MP2, 512 MB RAM, 640×480,
GLES 2.0 only, swap yok (zram)**.

| Konu | Sonuç |
| --- | --- |
| APK mimarisi | **Yalnızca `armeabi-v7a` (ARM32)**. `arm64-v8a` APK çalışmaz (kullanıcı alanı 32-bit). |
| GLES | Mali-400 **GLES 3.0 desteklemez**. RenderDragon tabanlı yeni sürümler (1.16.200+) sis/ışık/shader özelliklerinde patlayabilir veya siyah ekran verebilir. |
| RAM | 512 MB. Bedrock 1.16+ genelde 700 MB–1 GB ister; **OOM/kill** beklenir. 0.14–0.15 ve 1.1.x daha gerçekçi. |
| CPU | A33, R36S'in A53'ünden ~2–3× yavaş. R36S'te 3–4 chunk/30 FPS ise burada 1–2 chunk/10–15 FPS bekleyin. |
| Depolama | APK `assets/` ~200 MB–1 GB; SD'de yer açın. |
| 64-bit | Paketteki `mcpelauncher/arm64` bilinçli olarak silinir. |

**Önerilen ilk test:** `0.14.3`, `0.15.10` veya `1.1.5` gibi eski bir ARM32 APK.
Yeni sürümlerle uğraşmadan önce menünün, GLES2 context'inin ve sesin çalıştığını
doğrulayın (`TESTING.md`).

---

## 5. Upstream'den farklar (patch özeti)

`scripts/patch-port.sh` şunları yapar:

- `#!/bin/bash` → `#!/bin/sh`, tüm `bash` çağrıları → `sh`.
- `source` → `.` (BusyBox ash).
- `controlfolder="/roms/ports/PortMaster"` → `$SCRIPT_DIR/shim`.
- EmulationStation tuş-inversion tespiti (bash process substitution) kaldırılır;
  `A = onay` varsayılanı kullanılır.
- `MCPE_LANG_RESOLVED=C` → `C.UTF-8` (isim/world UTF-8).
- `SetupMcpe.sh` banner'ı `/dev/tty1` yerine stderr'e yazar
  (`set -e` + yazma izni yok = betik ölürdü).
- `drop_caches` gibi root gerektiren satırlar etkisizleştirilir.
- `menu/main.lua`: `[ Update Port ]` kaldırılır (güncelleme artık imajı yeniden
  build etmek demek).

Ek olarak `start.sh`:

- Windows/MTP kopyalamasında kaybolan `+x` bitlerini geri verir,
  `SDL_VIDEODRIVER=kmsdrm` ve `SDL_AUDIODRIVER=alsa` ayarlar.

---

## 6. Dosya yapısı (SD kartta)

```
ports/minecraft-bedrock/
  start.sh                      # Puppy'nin çağırdığı giriş noktası
  McpeLauncher.sh               # upstream + patch
  shim/                         # PortMaster yerine geçen sabitler
    control.txt
    device_info.txt
    runtimes/love_11.5/love.txt
  love/                         # gömülü LÖVE 11.5 armhf + lib/
  mcpe_launcher/
    mcpelauncher/armhf/         # mcpelauncher-client (prebuilt, glibc 2.30 tabanı)
    menu/                       # LÖVE menüsü (main.lua patchli)
    versions/<sürüm>/           # APK'dan çıkarılan lib + assets
    Setup Apk/                  # senin APK'ların
    Import Skins/
    home/                       # oyunun HOME'u (dünyalar, ayarlar)
    mcpelauncher/               # XDG_DATA_HOME (login, oyun verisi)
.local/share/applications/minecraft-bedrock.puppy
.local/share/icons/minecraft-bedrock.png
```

Oyun verisi port klasöründe kalır; `~/.local/share` kirlenmez.

---

## 7. Hata ayıklama

| Ne | Nerede |
| --- | --- |
| Başlatıcı + menü logu | `ports/minecraft-bedrock/mcpe_launcher/log.txt` |
| APK kurulum logu | `ports/minecraft-bedrock/mcpe_launcher/setup_log.txt` |
| appctl logu (stdout/stderr) | `/dev/shm/application/application.log` |
| Mesa/Lima hataları | aynı appctl logu (`MESA_DEBUG=1` ile daha ayrıntılı) |
| OOM | `dmesg \| grep -i oom` (USB TTY) |

Sık karşılaşılacak durumlar:

- **Menü açılmıyor / siyah ekran:** `love` binary'sinin `+x` olduğundan ve
  `LD_LIBRARY_PATH`'in `love/lib` içerdiğinden emin olun; `love/lib` boşsa
  `collect-libs.sh` build sırasında uyarı vermiş olabilir.
- **`Exec format error`:** APK `arm64-v8a`; ARM32 APK kullanın.
- **GLES hatası:** `MESA_GLES_VERSION_OVERRIDE` 2.0'da kalmalı; Mali-400'de 3.0
  istemek context oluşturmaz.
- **Oyun açılıp kapanıyor:** neredeyse her zaman RAM. Daha eski APK + daha düşük
  render distance.
- **Tuşlar ters:** `shim/control.txt` içindeki `sdl_controllerconfig` goodluckOS
  profilinden gelir; farklı donanımda `SDL_GAMECONTROLLERCONFIG`'i güncelleyin.

Çıkış: **START + SELECT** appctl'e SIGTERM gönderir. Bedrock dünyayı her zaman
düzgün kaydetmez — önce oyun içi menüden çıkın.

---

## 8. Sonraki adımlar

- [ ] Gerçek A33'te test (menü, setup, GLES2, ses, OOM eşiği).
- [ ] Çalışan en yeni APK sürümünü tabloya işle.
- [ ] `mcpelauncher-client` kaynaktan armhf derlenirse glibc bağımsız olur
      (şu an prebuilt, glibc 2.30 tabanı — goodluckOS'ta sorun değil).
- [ ] İsteğe bağlı: menüyü LÖVE yerine küçük bir SDL2/C binary'sine çevirmek
      (~20 MB kazanç, güncelleme derdi biter).

## Lisans

Bu repodaki Dockerfile/scripts: MIT. Gömülen bileşenler: mcpelauncher (GPL-3.0),
LÖVE (zlib), LÖVE bağımlılıkları (kendi lisansları), AOSP bionic shim'leri.
Ayrıntı: `THIRD_PARTY.md` ve port içindeki `licenses/`.
