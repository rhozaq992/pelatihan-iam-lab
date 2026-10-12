# Sesi 1 — Pengamanan Direktori Terpusat (AD/LDAP) & GPO

> Indikator 1.1 (hardening AD/LDAP) & 1.2 (GPO). Dikerjakan di VM **Windows Server 2025** (DC).
> Skrip provisioning ada di folder ini (`import-ad.ps1`, `users_dummy.csv`, `gen_dummy_users.py`).


**Tujuan:** direktori terstruktur & ter-hardening, bulk import, dan GPO berlaku.
Dikerjakan di **VM DC** (PowerShell + GPMC). Prioritas: OU/tiering, bulk import, kebijakan sandi, hardening inti. Sisanya lanjut mandiri.

## 1. OU, tiering, dan grup
```powershell
$dn = "DC=iamlab,DC=test"
"Tier0","Tier1-Servers","Pengguna","Grup","AkunLayanan" | % { New-ADOrganizationalUnit -Name $_ -Path $dn -ProtectedFromAccidentalDeletion $true -EA SilentlyContinue }
# grup unit + aplikasi + tier
$grpOU = "OU=Grup,$dn"
"GG-Pimpinan","GG-Keuangan","GG-SDM","GG-TI","GG-Operasional","GG-Layanan","GG-Hukum",`
"GG-App-Viewer","GG-App-Editor","GG-App-Admin","GG-Tier0-Admin","GG-Tier1-Admin" | % {
  New-ADGroup -Name $_ -GroupScope Global -Path $grpOU -EA SilentlyContinue }
```

## 1b. Akun layanan (WAJIB — dipakai Lab 2/3/4)
```powershell
$svcOU = "OU=AkunLayanan,$dn"
# svc-keycloak (bind LDAP Keycloak), svc-openbao (auth LDAP OpenBao), svc-app, svc-honey (umpan)
foreach ($s in "svc-keycloak","svc-openbao","svc-app","svc-honey") {
  New-ADUser -Name $s -SamAccountName $s -UserPrincipalName "$s@iamlab.test" `
    -Path $svcOU -AccountPassword (ConvertTo-SecureString "Svc#Lab2026!" -AsPlainText -Force) `
    -Enabled $true -PasswordNeverExpires $true -EA SilentlyContinue
}
# honey SPN untuk deteksi Kerberoasting (Lab 3)
setspn -S HTTP/honey.iamlab.test svc-honey
```
> Bila OVA sudah menyertakan akun layanan ini, langkah ini dilewati.

## 2. Bulk import 200 pengguna
```powershell
# skrip & CSV ada di folder sesi ini
.\import-ad.ps1 -Csv .\users_dummy.csv -UserOU "OU=Pengguna,$dn"
# latihan mandiri: tambah 20 user
.\import-ad.ps1 -Csv .\users_batch2.csv -UserOU "OU=Pengguna,$dn"
Get-ADUser -Filter * -SearchBase "OU=Pengguna,$dn" | Measure-Object
```

## 3. Akun admin terpisah & batasi Domain Admins
```powershell
New-ADUser -Name "adm-anda" -SamAccountName "adm-anda" -Path "OU=Tier0,$dn" `
  -AccountPassword (Read-Host -AsSecureString) -Enabled $true
Add-ADGroupMember -Identity "GG-Tier0-Admin" -Members "adm-anda"
# audit & kecilkan Domain Admins (sisakan ≤ 2)
Get-ADGroupMember "Domain Admins"
```

## 4. Kebijakan sandi domain + PSO (FGPP) untuk admin
```powershell
Set-ADDefaultDomainPasswordPolicy -Identity iamlab.test -MinPasswordLength 14 -ComplexityEnabled $true -LockoutThreshold 10
New-ADFineGrainedPasswordPolicy -Name "PSO-Admin" -Precedence 10 -MinPasswordLength 20 `
  -ComplexityEnabled $true -LockoutThreshold 5
Add-ADFineGrainedPasswordPolicySubject "PSO-Admin" -Subjects "GG-Tier0-Admin"
```

## 5. Hardening inti
```powershell
# Akun layanan AES-only (contoh svc-keycloak), lalu RESET sandi agar kunci dibuat ulang
Set-ADUser svc-keycloak -KerberosEncryptionType AES128,AES256
Set-ADAccountPassword svc-keycloak -Reset
# Nonaktifkan SMBv1
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
# Advanced Audit Policy (via GPO di langkah 6) — contoh cepat lokal:
auditpol /set /subcategory:"Kerberos Service Ticket Operations" /success:enable /failure:enable
```
> LDAP signing/LDAPS & impor Microsoft Security Baseline: lihat `solutions/` (sebagian baseline sudah diimpor pada OVA).

## 6. GPO (buat → link → verifikasi)
1. **GPMC** (`gpmc.msc`) → buat GPO "SEC-Audit-Tier1" → edit: *Computer Config → Policies → Windows Settings → Security Settings → Advanced Audit Policy* (Logon/Logoff, Account Logon, DS Access).
2. Link ke `OU=Tier1-Servers`; atur *Security Filtering* (grup komputer).
3. Verifikasi dari DC/klien:
   ```powershell
   gpupdate /force
   gpresult /h C:\gpreport.html ; start C:\gpreport.html
   ```

## Hasil yang diharapkan
- `Get-ADUser` di OU Pengguna ≈ 220; `Domain Admins` ≤ 2.
- `Get-ADUser svc-keycloak -Properties msDS-SupportedEncryptionTypes` menunjukkan AES.
- SMBv1 nonaktif; GPO ter-link dan muncul di `gpresult`.
EOF
echo "lab1 ok"
---

## Simulasi Terkendali & Mitigasi (PtH & Kerberoasting)


**Tujuan:** mengenali sinyal Kerberoasting/PtH lalu **menutupnya**. Defensif — hanya
menguji deteksi/mitigasi pada target lab di jaringan Host-Only terisolasi.

### Etika & pagar
Runner `attack-sim/run.sh` hanya menerima target dari `TARGETS.lab` (iamlab.test /
10.10.10.0/24), wajib `IAMLAB_CONFIRM=1`, dan menolak bila ada rute internet.

### 1. Prasyarat
Akun layanan `svc-*` dan honey SPN `HTTP/honey.iamlab.test` sudah dibuat di Lab 1 (langkah 1b). Pastikan ada sebelum lanjut:
```powershell
setspn -L svc-honey        # harus menampilkan HTTP/honey.iamlab.test
```

### 2. Jalankan simulasi Kerberoasting
```bash
docker compose --profile attack up -d attacker
docker compose exec attacker env IAMLAB_CONFIRM=1 /attack-sim/run.sh dc1.iamlab.test kerberoast
# runner menunjukkan contoh perintah open source (Impacket GetUserSPNs) terhadap DC lab
```

### 3. Amati sinyal
- **Event Viewer DC** (atau Grafana bila Lab 5 sudah): Event **4769** dengan
  `TicketEncryptionType = 0x17` (RC4) dari akun non-mesin, dan permintaan untuk honey SPN.

### 4. Terapkan mitigasi lalu ulangi
```powershell
# AES-only pada akun layanan + reset sandi (kunci dibuat ulang)
Set-ADUser svc-app -KerberosEncryptionType AES128,AES256 ; Set-ADAccountPassword svc-app -Reset
```
Jalankan ulang simulasi → tiket kini AES (0x12), bukan RC4.

### (Opsional) Diskusi PtH
Tanpa langkah ofensif: tinjau mengapa **Windows LAPS** (sandi admin lokal unik),
**Protected Users**, dan isolasi tier memutus reuse hash NTLM.

### Hasil yang diharapkan
- Sebelum mitigasi: terlihat 4769 RC4; honey SPN memicu perhatian.
- Sesudah AES-only: permintaan tiket memakai AES; peserta menjelaskan mengapa mitigasi bekerja.

### Catatan notasi
`msDS-SupportedEncryptionTypes = 24` (bitmask AES). Field event `TicketEncryptionType`:
`0x17`=RC4-HMAC, `0x18`=RC4-HMAC-EXP (lemah); AES = `0x11/0x12`.
