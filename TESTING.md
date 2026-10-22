# Test planı — goodluckOS / GA36-MB (A33)

Her adımı sırayla işaretle. Bir adım patlarsa logları ekle:
`ports/minecraft-bedrock/mcpe_launcher/log.txt`,
`runlog-<sürüm>.txt`, `setup_log.txt`, `/dev/shm/application/application.log`.
Ayrıntılı tanı için `mcpe_launcher/debug.txt` oluştur (`perf.log`/`net.log`).

## 0. Ön koşullar

- [ ] goodluckOS 0.1.x, 640×480 panel
- [ ] `ports/minecraft-bedrock/` HOME kökünde
- [ ] `love/love` ve `mcpelauncher-client` dosyaları mevcut
- [ ] En az 2 GB boş alan (APK + assets + dünya)
- [ ] Elinde **ARM32 (armeabi-v7a)** veya universal APK var.
      Önerilen: **1.17.41**. `1.16.20.03` apksum APK'sı arm64-only olduğu için
      A33'te kullanılamaz.

## 1. Menü (LÖVE / KMSDRM)

- [x] Puppy → Ports → Minecraft Bedrock açılıyor
- [x] 640×480 tam ekran, imleç yok
- [ ] D-pad yukarı/aşağı seçim yapıyor
- [ ] A = onay, B = geri
- [ ] `Exit` menüyü kapatıp Puppy'e dönüyor

Başarısızsa: `log.txt` içinde `love` / `libGL` / `kmsdrm` satırları.

## 2. APK kurulumu

- [ ] `Setup Apk` APK'yı listeliyor
- [ ] Tek mimarili (armeabi-v7a) APK doğrudan kuruluyor
- [ ] Çift mimarili APK'da `ARM32` seçilebiliyor
- [ ] Yalnızca `arm64-v8a` APK net hatayla reddediliyor
- [ ] `versions/<ad>/lib/armeabi-v7a`, `assets/` ve `AndroidManifest.xml` doldu
- [ ] Kurulum sonunda `sync` tamamlanıyor (log: `Setup completed`)
- [ ] Yer bitince anlaşılır hata veriyor
- [ ] Kurulu sürüm `X` ile silinebiliyor

## 3. Oyun — ilk açılış

- [x] `log.txt` içinde `Illegal instruction` **yok**
      (varsa istemci hâlâ Cortex-A35 sürümüdür; bu pakette olmamalı)
- [x] Sürüm seçilince `mcpelauncher-client` başlıyor
- [x] Ekran siyah kalmıyor (EGL/GLES2 context)
- [x] Mojang logosu / ana menü görünüyor (`1.17.41`)
- [x] İlk açılışta çökme yok
- [ ] `free -m` ile RSS < 450 MB
- [ ] `options.txt` içinde `mp_server_visible:1` ve hızlı varsayılanlar
      (`gfx_viewdistance:48`, `gfx_msaa:0`, `gfx_vsync:0`) var

## 4. Oynanış

- [ ] Yeni dünya oluşturuluyor (3 chunk / `gfx_viewdistance:48`, MSAA kapalı)
- [ ] "Building terrain"/"Loading world" birkaç dakika sürse de çökme yok
- [ ] Sol stick yürüyor, sağ stick bakıyor
- [ ] A/B/X/Y ve trigger'lar Bedrock eşlemesinde
- [ ] Ses var (hoparlör; FN+DOWN ile kulaklık)
- [ ] 10+ FPS, chunk yüklerken donma kabul edilebilir
- [ ] 5 dakika oynadıktan sonra OOM yok (`dmesg`)

## 5. Kayıt / çıkış

- [ ] Oyundan normal şekilde çıkılıyor
- [ ] Dünya yeniden açıldığında değişiklikler duruyor
- [ ] START+SELECT zorla çıkışta süreç ölüyor, Puppy geri geliyor
- [ ] Zorla çıkış sonrası dünya bozulmuyor (uyarı: her zaman değil)

## 6. Regresyon

- [ ] Tekrar açılışta giriş (Microsoft hesabı) korunuyor
- [ ] Skin içe aktarma çalışıyor (`Import Skins/`)
- [ ] Menüden çıkıp tekrar girmek sorunsuz

## Bilinen sınırlar

- ARM64 APK desteklenmez (32-bit kullanıcı alanı). `1.16.20.03` apksum APK'sı
  yalnızca arm64-v8a içerdiği için A33'te kurulamaz/çalışmaz.
- GLES3 / RenderDragon sürümleri Mali-400'de desteklenmez.
- 512 MB RAM: `1.17.41` ana menüye ulaştı; dünya yükleme ve uzun oyun OOM
  açısından hâlâ riskli. 3 chunk + MSAA kapalı ile test edin.
- Kendini güncelleme yok; güncelleme = yeni imaj build'i.
- Tanılama döngüleri normalde kapalı; `mcpe_launcher/debug.txt` ile açılır.
