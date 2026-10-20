# Test planı — goodluckOS / GA36-MB (A33)

Her adımı sırayla işaretle. Bir adım patlarsa logları ekle:
`ports/minecraft-bedrock/mcpe_launcher/log.txt`,
`setup_log.txt`, `/dev/shm/application/application.log`.

## 0. Ön koşullar

- [ ] goodluckOS 0.1.x, 640×480 panel
- [ ] `ports/minecraft-bedrock/` HOME kökünde
- [ ] `love/love` ve `mcpelauncher-client` dosyaları mevcut
- [ ] En az 2 GB boş alan (APK + assets + dünya)
- [ ] Elinde **ARM32 (armeabi-v7a)** APK var (örn. 0.14.3)

## 1. Menü (LÖVE / KMSDRM)

- [ ] Puppy → Ports → Minecraft Bedrock açılıyor
- [ ] 640×480 tam ekran, imleç yok
- [ ] D-pad yukarı/aşağı seçim yapıyor
- [ ] A = onay, B = geri
- [ ] `Exit` menüyü kapatıp Puppy'e dönüyor

Başarısızsa: `log.txt` içinde `love` / `libGL` / `kmsdrm` satırları.

## 2. APK kurulumu

- [ ] `Setup Apk` APK'yı listeliyor
- [ ] Tek mimarili APK doğrudan kuruluyor
- [ ] Çift mimarili APK'da `ARM32` seçilebiliyor
- [ ] `versions/<ad>/lib/armeabi-v7a` ve `assets/` doldu
- [ ] Yer bitince anlaşılır hata veriyor
- [ ] Kurulu sürüm `X` ile silinebiliyor

## 3. Oyun — ilk açılış

- [ ] `log.txt` içinde `Illegal instruction` **yok**
      (varsa istemci hâlâ Cortex-A35 sürümüdür; bu pakette olmamalı)
- [ ] Sürüm seçilince `mcpelauncher-client` başlıyor
- [ ] Ekran siyah kalmıyor (EGL/GLES2 context)
- [ ] Mojang logosu / ana menü görünüyor
- [ ] 60 sn içinde çökme yok
- [ ] `free -m` ile RSS < 450 MB

## 4. Oynanış

- [ ] Yeni dünya oluşturuluyor (en düşük render distance)
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

- ARM64 APK desteklenmez (32-bit kullanıcı alanı).
- GLES3 / RenderDragon sürümleri Mali-400'de desteklenmez.
- 512 MB RAM: 1.16+ sürümler büyük olasılıkla OOM.
- Kendini güncelleme yok; güncelleme = yeni imaj build'i.
