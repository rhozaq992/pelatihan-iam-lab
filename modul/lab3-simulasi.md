# Lab 3 — Simulasi Terkendali & Mitigasi (25') · Indikator 1.1

**Tujuan:** mengenali sinyal Kerberoasting/PtH lalu **menutupnya**. Defensif — hanya
menguji deteksi/mitigasi pada target lab di jaringan Host-Only terisolasi.

## Etika & pagar
Runner `attack-sim/run.sh` hanya menerima target dari `TARGETS.lab` (iamlab.test /
10.10.10.0/24), wajib `IAMLAB_CONFIRM=1`, dan menolak bila ada rute internet.

## 1. Prasyarat
Akun layanan `svc-*` dan honey SPN `HTTP/honey.iamlab.test` sudah dibuat di Lab 1 (langkah 1b). Pastikan ada sebelum lanjut:
```powershell
setspn -L svc-honey        # harus menampilkan HTTP/honey.iamlab.test
```

## 2. Jalankan simulasi Kerberoasting
```bash
docker compose --profile attack up -d attacker
docker compose exec attacker env IAMLAB_CONFIRM=1 /attack-sim/run.sh dc1.iamlab.test kerberoast
# runner menunjukkan contoh perintah open source (Impacket GetUserSPNs) terhadap DC lab
```

## 3. Amati sinyal
- **Event Viewer DC** (atau Grafana bila Lab 5 sudah): Event **4769** dengan
  `TicketEncryptionType = 0x17` (RC4) dari akun non-mesin, dan permintaan untuk honey SPN.

## 4. Terapkan mitigasi lalu ulangi
```powershell
# AES-only pada akun layanan + reset sandi (kunci dibuat ulang)
Set-ADUser svc-app -KerberosEncryptionType AES128,AES256 ; Set-ADAccountPassword svc-app -Reset
```
Jalankan ulang simulasi → tiket kini AES (0x12), bukan RC4.

## (Opsional) Diskusi PtH
Tanpa langkah ofensif: tinjau mengapa **Windows LAPS** (sandi admin lokal unik),
**Protected Users**, dan isolasi tier memutus reuse hash NTLM.

## Hasil yang diharapkan
- Sebelum mitigasi: terlihat 4769 RC4; honey SPN memicu perhatian.
- Sesudah AES-only: permintaan tiket memakai AES; peserta menjelaskan mengapa mitigasi bekerja.

## Catatan notasi
`msDS-SupportedEncryptionTypes = 24` (bitmask AES). Field event `TicketEncryptionType`:
`0x17`=RC4-HMAC, `0x18`=RC4-HMAC-EXP (lemah); AES = `0x11/0x12`.
