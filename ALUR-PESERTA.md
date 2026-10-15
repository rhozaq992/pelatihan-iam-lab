# Alur Peserta (Storyboard) — Lab IAM

Peta langkah peserta dari awal sampai akhir, dikaitkan ke **topologi** (Sesi 0) dan dilengkapi
**validasi / output yang diharapkan** tiap langkah. Dipakai sebagai panduan cepat; detail dan
tangkapan layar ada di README tiap sesi.

## Pemeran & lokasi (topologi)

| Node | Peran | Alamat | Penanda |
|------|-------|--------|---------|
| **PC lab** (Windows) | Disiapkan fasilitator: VirtualBox + Docker Desktop + lab sudah berjalan; browser | adapter Host-Only `10.10.10.5` | 🪟 PowerShell host · 🖥️ terminal host |
| **samba-dc** (container, `dc1`) | AD/LDAP: direktori, Kerberos, LDAPS | `dc1.iamlab.test` = `10.10.10.5` | 🐳 `docker compose exec samba-dc` |
| Layanan IAM (container) | Caddy, Keycloak+Postgres, OpenBao, Warpgate, Mailpit, Grafana/Loki/Alloy, App-Komentar/SAML | `*.iamlab.test` → `10.10.10.5` | 🐳 / 🌐 web UI |
| **VM `srv1`** (Ubuntu Server) | Anggota domain; target SSH/bastion; CIS *server* | `srv1.iamlab.test` = `10.10.10.20` | 🖥️ di `srv1` |
| **VM `client1`** (Ubuntu Desktop) | Anggota domain; login GUI pengguna; CIS *workstation*. Layar login (GDM) muncul ±3–5 mnt setelah VM nyala; pesan `vmwgfx` di konsol normal | `client1.iamlab.test` = `10.10.10.30` | 🖥️ di `client1` |

Domain sintetis `iamlab.test`. Jaringan Host-Only `10.10.10.0/24`, tanpa internet (terisolasi).
Akun: Administrator domain `Passw0rd#Lab2026` · admin lokal VM `labadmin` / `Lab#Admin2026`.

---

## Babak 0 — Mulai (Sesi 0)

> **Lab dibangun fasilitator sebelum kelas** (memakai paket `IAMLAB-BuildBag`). Peserta tidak
> membangun lab, cukup mengambil modul lalu memverifikasi lab sudah jalan. Bila belum jalan,
> hubungi fasilitator.
>
> 🛠️ **Catatan fasilitator — kapan `update-lab.ps1` dijalankan.** Hanya untuk lab yang **sudah
> terbangun** lalu perlu menyerap perbaikan modul/infra (hasil QA) **tanpa** `Destroy`/rebuild —
> data (volume) dan VM tetap utuh. Jalankan dari folder builder (PowerShell Administrator):
> `.\update-lab.ps1`. Langkahnya: muat image baru → `compose up -d` (hanya service berubah) →
> regen cert **LDAPS ber-SAN** (perbaikan OpenBao Sesi 3) → `git pull` modul. Untuk lab **baru**,
> tetap pakai `build-lab.ps1` (bukan skrip ini). Opsi: `-SkipImages`, `-SkipGit`,
> `-ClearWarpgateBlocks` (kosongkan blokir IP brute-force Warpgate).

| # | Peserta melakukan | Perintah | ✅ Validasi / output |
|---|-------------------|----------|----------------------|
| 0.1 | 🪟 Masuk folder builder & ambil modul | `cd C:\Lab\IAMLAB-BuildBag; git clone <url-repo> Pelatihan_IAM; cd Pelatihan_IAM` | Folder `Pelatihan_IAM` berisi `sesi-0..4`. Tata letak: `IAMLAB-BuildBag\{deploy,...}` + `IAMLAB-BuildBag\Pelatihan_IAM`. |
| 0.2 | 🪟 Pastikan lab (buatan fasilitator) jalan | `cd ..\deploy; docker compose ps` (atau `..\build-lab.ps1 -Phase Status`) | Stack Docker `running`/`healthy`; VM `srv1`/`client1` `running`; port `389/636/443` di `10.10.10.5` terbuka. |
| 0.3 | 🌐 Buka layanan | Browser → `https://kc.iamlab.test` | Halaman *Welcome to Keycloak*. `https://grafana.iamlab.test` → Grafana. |

> Semua perintah `docker compose …` di modul dijalankan dari `IAMLAB-BuildBag\deploy`
> (dari folder modul: `cd ..\deploy`). File modul yang disalin ke container dirujuk sebagai
> `../Pelatihan_IAM/sesi-…`.

---

## Babak 1 — Direktori, Join Domain & CIS (Sesi 1)

| # | Peserta melakukan | Perintah (ringkas) | ✅ Validasi / output |
|---|-------------------|--------------------|----------------------|
| 1.1 | 🐳 Tata OU, grup, akun layanan, SPN | `docker compose exec samba-dc bash` lalu `samba-tool ou create…`, `group add…`, `user create svc-*…`, `spn add…` | Tiap perintah: `Added ou…` / `User '…' added successfully`. `samba-tool spn list svc-app` memuat `HTTP/app.iamlab.test`. |
| 1.2 | 🐳 Bulk import ±220 pengguna | `docker compose cp ../Pelatihan_IAM/sesi-1-direktori-akses-cis samba-dc:/tmp/sesi1` → `bash /tmp/sesi1/import-ad.sh --csv …users_dummy.csv --send-email` | `Selesai: dibuat 200 …` (batch2: `dibuat 20`). `samba-tool user show dewi.puspita001` → `pwdLastSet: 0`. Email di Mailpit. |
| 1.3 | 🐳 Kebijakan sandi + PSO | `samba-tool domain passwordsettings set/pso …` | `Minimum password length: 14`, `Password complexity: on`; PSO-Admin min 20. |
| 1.4 | 🐳 Hardening (AES-only, NTLM off) + 🐳🖥️ LDAPS (ekspor CA) | `samba-tool user setpassword svc-keycloak…`; `docker compose cp samba-dc:/var/lib/samba/private/tls/ca.pem certs/ad-ca.pem`; `up -d --force-recreate keycloak openbao` | `openssl s_client -connect 10.10.10.5:636` → cert CN `DC1.iamlab.test` **ber-SAN** (`DNS:dc1.iamlab.test, IP:10.10.10.5` — wajib untuk OpenBao Sesi 3; lab lama regen via §5b). Catat sandi baru `svc-keycloak` (dipakai Sesi 2). |
| 1.5 | 🖥️ Join `srv1` & `client1` | di tiap VM: `sudo join-domain.sh` lalu `id dewi.puspita001` | `akun domain terbaca: …`; `id` memuat grup `gg-pimpinan`, `gg-app-viewer`. Di `client1`: login GDM sebagai `dewi.puspita001`. |
| 1.6 | 🖥️ Kebijakan akses terpusat | edit `sssd.conf` (`access_provider=simple`, `simple_allow_groups`), sudoers grup AD, `systemctl restart sssd` | Di `srv1`: SSH pimpinan **ditolak**, `adm-t1-anda` **diterima** + `sudo -l` berisi izin. |
| 1.7 | 🖥️ CIS Benchmark + remediasi | `sudo cis-scan.sh` → `--list-fail` → `--fix <rule>` → `sudo cis-scan.sh` | Baris JSON di `/var/log/cis/summary.log` (`pass/fail/score`); skor scan **kedua > pertama**; laporan HTML di `/var/log/cis/report-latest.html`. |
| 1.8 | 🐳 Simulasi Kerberoasting → mitigasi | `docker compose --profile attack up -d attacker`; runner cetak perintah Impacket; terapkan AES-only; ulang | Hash tiket `$krb5tgs$23$` (RC4) **→ `$krb5tgs$18$` (AES)** setelah AES-only. |

---

## Babak 2 — SSO & MFA (Sesi 2)

| # | Peserta melakukan | Di mana | ✅ Validasi / output |
|---|-------------------|---------|----------------------|
| 2.1 | Realm `iamlab` + federasi LDAP ke Samba | 🌐 Keycloak admin | Vendor *Active Directory*, `ldaps://dc1.iamlab.test:636`, bind `svc-keycloak` (sandi baru 1.4). **Test connection & authentication** → sukses; **Sync users** menarik ±220 user. |
| 2.2 | Client OIDC `app-komentar` + `warpgate`, client SAML | 🌐 Keycloak admin → 🖥️ isi `APP_OIDC_CLIENT_SECRET` di `.env`, `up -d app-komentar` | App-Komentar bisa login SSO; `warpgate` client secret dicatat (Sesi 3). |
| 2.3 | MFA bersyarat + brute force + events | 🌐 Keycloak admin | Admin dipaksa pindai OTP; akun terkunci setelah >10 gagal; events login tercatat. |
| 2.4 | Uji RBAC App-Komentar | 🌐 `https://app.iamlab.test` 3 akun | Viewer hanya lihat; Editor tulis/hapus miliknya; Admin hapus semua. Penolakan **ditegakkan server** (API 403 untuk peran tak berhak). |

---

## Babak 3 — PAM: Vault & Bastion (Sesi 3)

| # | Peserta melakukan | Di mana | ✅ Validasi / output |
|---|-------------------|---------|----------------------|
| 3.1 | Init/unseal OpenBao, audit, auth LDAP, policy, KV, SSH CA | 🐳 `openbao` | `bao status` → `Initialized true, Sealed false, 3/2`; `bao audit list` → `file/` + `stdout/`; login `-method=ldap` `adm-t1-anda` → `policies [admin-t1 default]`; baru cabut root. |
| 3.2 | `srv1` memercayai SSH CA, matikan sandi | 🖥️ di `srv1` | `TrustedUserCAKeys` + `PasswordAuthentication no`; `systemctl restart ssh`. |
| 3.3 | Warpgate setup + SSO Keycloak + target `srv1` | 🖥️ host + 🌐 admin | `unattended-setup` sukses; `ps warpgate` → `healthy`; SSO via `warpgate.yaml` (client Sesi 2.2). |
| 3.4 | Akses `srv1` via bastion (terekam) | 🖥️ `ssh -p 2222 <user>:srv1@pam.iamlab.test` | Diminta SSO/MFA; sesi tembus ke `srv1` sebagai `labadmin`; rekaman tampil di web UI. |

---

## Babak 4 — Audit, Monitoring & Trace User (Sesi 4)

| # | Peserta melakukan | Di mana | ✅ Validasi / output |
|---|-------------------|---------|----------------------|
| 4.1 | Pastikan pipeline hidup | 🐳 `loki`/`grafana` | `/ready` → `ready`; `label/service/values` memuat `samba-dc, keycloak, caddy, openbao, warpgate, …` + `job="host"` dari `srv1`/`client1`. |
| 4.2 | Lengkapi Alloy (OpenBao/Warpgate/sshd) | 🐳 edit `config.alloy`, `restart alloy` | Label `event` muncul untuk sumber baru. |
| 4.3 | Dashboard **Identity Audit** | 🌐 Grafana | Panel jumlah user, user aktif, login sukses/gagal, top IP gagal terisi data. |
| 4.4 | Dashboard **User Activity Trace** + **Logs Drilldown** | 🌐 Grafana | Pilih variabel `host` + `user` → panel menyaring ke aktivitas satu pengguna (login/sudo/perintah, login Keycloak, perubahan grup, skor CIS). Explore → Drilldown → Logs untuk *discovery*. |
| 4.5 | Alert + capstone (Locust) | 🖥️ host | `LAB_PROFILE=spray … up -d locust` → alert brute-force terpicu, email di Mailpit. |
| 4.6 | Respons insiden (kunci akun terpusat) | 🐳 + 🌐 | `samba-tool user disable <user>`; Keycloak logout-all; `bao token revoke`; Warpgate cabut akses. Laporan insiden dgn bukti LogQL. |

---

## Checklist validasi akhir (ringkas)

- [ ] `build-lab.ps1 -Phase Status`: 2 VM `running`, stack `healthy`.
- [ ] `samba-tool user list` memuat 220 pengguna impor + svc-* + Administrator/krbtgt/Guest.
- [ ] `id dewi.puspita001` di `srv1` **dan** `client1` menampilkan grup domain.
- [ ] `cis-scan.sh` kedua: skor naik; `summary.log` terkirim ke Grafana.
- [ ] Keycloak: Test LDAP sukses; App-Komentar RBAC 3 peran; MFA aktif.
- [ ] OpenBao unsealed, root dicabut; SSH ke `srv1` **hanya** via bastion (terekam).
- [ ] Grafana: Identity Audit berdata; User Activity Trace bisa pilih `user` dan menyaring.
- [ ] Kerberoasting: enctype tiket berpindah RC4 → AES setelah mitigasi.
