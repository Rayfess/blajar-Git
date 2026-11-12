# Laporan Simulasi — Otomasi WSL2 + DDEV

Dokumen ini menjelaskan (dengan bahasa sederhana) bagaimana pengetesan simulasi
otomasi dilakukan tanpa menyentuh sistem utama, apa saja yang berubah di
komputer, hasilnya, dan batasannya.

Tanggal: 2026-11-13 · Terkait: `wsl-ddev-setup-prd.md`, `wsl-setup.ps1`,
`provision-wsl.sh`

## 1. Latar dan aturan main

Permintaan: hasil pengetesan otomasi **tanpa menjalankannya sungguhan** di
komputer (karena skripnya mengubah sistem: apt/dnf, docker, wsl.conf, chsh, dll).

Metode: jalankan `provision-wsl.sh` **sungguhan** — tetapi di dalam *sandbox*,
yaitu satu folder di Temp tempat "dunia" yang bisa disentuh skrip sudah
diganti semua menjadi versi palsu. Kode yang diuji tetap 100% asli; yang
diganti hanya lingkungannya.

Prinsip satu kalimat: program hanya mengenal dunia lewat (1) perintah yang
dipanggilnya, (2) path yang ia tulis, (3) lingkungan yang ia baca — ketiganya
dikunci sebelum eksekusi.

## 2. Tiga file yang berubah selama sesi simulasi

| File | Lokasi | Peran | Status |
|------|--------|-------|--------|
| `provision-wsl.sh` | repo | **Produk asli** — fix bug `USER: unbound variable` (+2 baris) | Di repo, uncommitted, **wajib dipertahankan** |
| `build_sim.sh` | `%TEMP%\wslsim` | "Pabrik dunia palsu": membangun sandbox (stub, fixture, salinan skrip ber-path-rewrite). Beberapa kali diedit karena bug di alat uji itu sendiri | Artefak uji, sekali buang, **tidak di-commit** |
| `ps_tests.ps1` | `%TEMP%\wslsim` | Soal ujian komponen `wsl-setup.ps1`: 12 assertion pass/fail | Artefak uji, sekali buang, **tidak di-commit** |

Kedua file di Temp sengaja tidak masuk repo: itu alat kerja, bukan produk.
Repo hanya berisi hal yang dipakai jangka panjang.

## 3. Cara kerja sandbox (bahasa sederhana)

1. **Penculikan perintah via PATH** — `sudo, apt-get, dnf, docker, curl, git,
   chsh, systemctl` diselesaikan shell lewat PATH dari kiri; stub ditaruh
   paling kiri, jadi perintah "berbahaya" jatuh ke skrip palsu yang hanya
   mencatat panggilan dan mengembalikan hasil realistis. Binary asli tidak
   pernah dijalankan. PATH juga dipotong dari direktori Windows agar tidak
   ada binary asli yang bocor masuk.
2. **Penulisan ulang path** — yang dieksekusi bukan file repo, melainkan
   salinan yang sudah di-sed: `/etc/wsl.conf` → `$sandbox/etc/wsl.conf`,
   `/usr/local/bin/mkcert` → `$sandbox/usr/local/bin/mkcert`. Perintah asli
   yang jinak (tee, cp, diff) menulis ke dalam sandbox.
3. **Intersepsi sudo** — stub sudo tidak meng-elevasi apa pun; ia mencatat
   lalu mengarahkan ke mock sesuai perintahnya.
4. **HOME palsu** — `~/.zshrc`, `~/.zsh/plugins`, `~/.bun` semuanya di dalam
   sandbox.
5. **Dunia palsu yang stateful** — fixture `/etc/os-release` per distro
   (Debian 12 / Fedora 42) + database palsu (`pkgdb` untuk paket terinstall,
   `docker.state` untuk container/image) sehingga logika skip-if-installed
   dan idempotency benar-benar teruji antar-run.

Contoh alur: `sudo apt-get install zsh` → stub sudo mencatat → mock_apt
mencatat "zsh terinstall" ke `pkgdb` → membuat stub zsh → skrip melihat
"zsh sudah ada" → task berikutnya skip. Semuanya di dalam folder Temp.

## 4. Hasil pengetesan

| # | Skenario | Exit | CHG/SKIP | Hasil |
|---|----------|------|----------|-------|
| 1 | Fresh Debian 12 | 0 | 16/9 | PASS — 13/13 task; docker, ddev, portainer PASS |
| 2 | Rerun Debian (idempotency) | 0 | 2/10 | PASS — marker wsl.conf, image hello-world, container portainer dikenali; tidak ada reinstall |
| 3 | Fresh Fedora 42 (jalur dnf) | 0 | 16/9 | PASS — `gcc gcc-c++ make`, repo Docker via `config-manager addrepo`, podman di-WARN bukan dihapus |
| 4 | Debian + `--upgrade --with-zsh-completions` | 0 | 17/8 | PASS — upgrade jalan; `fpath` completions sebelum compinit |

Component test `wsl-setup.ps1`: **12/12 PASS** — pembersih null-byte UTF-16,
konversi path `D:\`→`/mnt/d/`, parser `wsl --list --online` + filter
Debian/Fedora, aturan 1-distro, ambang FR-04 (WSL <2.0, build <22621).

Bukti lain: inventory fresh mendeteksi semua "not installed" (valid); block
`.zshrc` tepat sesuai spesifikasi (syntax-highlighting paling akhir); startup
zsh terukur 75–76 ms (target <150 ms); laporan akhir memuat `docker ps -a`
(hello-world exited + portainer running).

## 5. Bug yang ditemukan

**Bug nyata di produk (sudah diperbaiki):**
- `$USER` dipakai di FR-09/FR-11 tanpa guard di bawah `set -u`; konteks
  `wsl -e bash` non-login bisa tidak membawa `USER` → skrip mati di tengah.
  Fix di `provision-wsl.sh` (dekat baris atas):
  ```bash
  USER="${USER:-$(id -un)}"
  ```

**Bug di alat uji (semua diperbaiki, tidak memengaruhi produk):**
- Shim `curl` lupa dipasang → installer bun asli sempat ter-download ke
  HOME palsu di sandbox (satu-satunya tulisan keluar sandbox; HOME saat itu
  sudah ter-sandbox, jadi tidak menyentuh registry/sistem; terhapus saat
  rebuild).
- Template stub tercemar run sebelumnya (glob `stubs-*` tidak menghapus
  `stubs` polos) → state bocor antar skenario.
- `mock_dnf` tidak menangani flag leading `-q -y` → jalur install Fedora
  tidak pernah dieksekusi.
- Stub sudo keluar tanpa membaca stdin → SIGPIPE (exit 141) pada pipe
  nodesource.

Insiden bun mendemonstrasikan batas sandbox ini: isolasinya *by
construction* (pintu dikunci satu per satu), bukan VM. Setelah insiden,
semua pintu keluar diaudit ulang dan dikunci sebelum run diulang.

## 6. Yang TIDAK tercakup simulasi (jujur)

- Interaksi nyata `wsl.exe`: Branch 2/3 `wsl-setup.ps1` saat runtime,
  parsing `.wslconfig` oleh WSL, `wslinfo --networking-mode`.
- Download & GPG sungguhan (apt/dnf), binary mkcert asli, import certutil
  ke Windows, ddev/Docker sungguhan, first-launch distro.
- Perilaku versi spesifik `dnf5` di Fedora (hanya jalur sintaks + fallback
  dnf4 yang terverifikasi).

Kesimpulan: alur kontrol, urutan task, idempotency, adaptasi distro, dan
definition of done terverifikasi di kedua distro; satu bug kritis produk
ditemukan dan diperbaiki. Verifikasi penuh tetap membutuhkan run pertama
yang sungguhan.

## 7. Keadaan komputer setelah simulasi

- Yang tersisa: `%TEMP%\wslsim\` (≈359 KB: stubs, logs, salinan sandbox) —
  sekali buang.
- Yang berubah di repo: `provision-wsl.sh` (fix bug) — uncommitted.
- Yang TIDAK tersentuh: registry, PATH Windows, WSL, `.wslconfig` (belum
  pernah dibuat), layanan/scheduled task, instalasi asli apa pun
  (diverifikasi: ddev/docker/zsh/mkcert tidak ada di sistem).

Membersihkan artefak (opsional):
```bash
rm -rf "$(cygpath -u "$TEMP")/wslsim"
```
atau hapus folder `wslsim` lewat File Explorer di
`C:\Users\<user>\AppData\Local\Temp\`.

Menjalankan ulang simulasi (jika folder masih ada):
```bash
bash "C:\Users\<user>\AppData\Local\Temp\wslsim\build_sim.sh"
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\<user>\AppData\Local\Temp\wslsim\ps_tests.ps1"
```
Catatan: alat uji tidak di-commit ke repo, jadi jika folder Temp sudah
terhapus, simulasi perlu dibangun ulang dari dokumentasi ini.
