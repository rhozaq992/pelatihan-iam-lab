# Sesi 1 — Pengamanan Direktori Terpusat (AD/LDAP) & GPO

Indikator 1.1 (hardening AD/LDAP) dan 1.2 (Group Policy). Dikerjakan pada VM
**Windows Server 2025** yang menjadi Domain Controller (DC) `iamlab.test`. Skrip
provisioning ada di folder ini (`import-ad.ps1`, `users_dummy.csv`, `gen_dummy_users.py`).

> Semua perintah di bawah bersifat nyata — jalankan berurutan dari atas ke bawah.
> Data pengguna bersifat sintetis (tidak ada data pribadi nyata).

## a. Tujuan Sesi

Peserta mampu:
- Menata direktori terpusat (OU, tiering, grup) dan melakukan _bulk import_ pengguna.
- Menerapkan kebijakan kata sandi domain dan PSO/FGPP untuk akun istimewa.
- Mengeraskan (_hardening_) direktori: LDAPS/signing, AES-only Kerberos, nonaktifkan protokol lemah.
- Membuat dan menerapkan **Group Policy Object (GPO)** keamanan, lalu memverifikasinya.
- Mengenali sinyal **Pass-the-Hash** & **Kerberoasting** pada log, lalu menutupnya dengan mitigasi.

## b. Output yang Diharapkan

- Direktori berisi ±220 pengguna di `OU=Pengguna`; anggota `Domain Admins` ≤ 2.
- Akun layanan (`svc-*`) memakai enkripsi **AES** (bukan RC4); SMBv1 nonaktif.
- GPO ter-_link_ ke OU dan tampil pada `gpresult`/RSoP.
- Pada simulasi terkendali: sebelum mitigasi terlihat tiket Kerberos RC4 (event 4769, enctype `0x17`);
  setelah AES-only, permintaan tiket memakai AES (`0x12`) dan akun umpan memicu perhatian.

## c. Teori dan Struktur Sistem

**Active Directory (AD)** adalah _control plane_ identitas Windows: menyimpan
pengguna/grup/komputer (LDAP), menerbitkan tiket **Kerberos** (KDC), menyediakan
DNS, dan menyebar kebijakan lewat **GPO** (disimpan di objek LDAP + SYSVOL).

- **Tiering / Enterprise Access Model (Microsoft).** Tier 0 (DC, AD CS, sinkronisasi
  identitas) adalah bidang kendali tertinggi; Tier 1 (server/aplikasi); Tier 2
  (perangkat pengguna). Prinsip: kredensial tier tinggi tidak boleh terpapar di
  tier rendah, agar kompromi bidang bawah tidak naik ke atas.
- **Pemrosesan GPO — LSDOU:** Local → Site → Domain → OU, dengan pewarisan,
  _Enforced_, _Block Inheritance_, _security filtering_, dan WMI filtering.
- **Pass-the-Hash (PtH):** penyerang yang menguasai sebuah host mengambil _hash_
  NTLM dari memori, lalu memakainya untuk autentikasi ke host lain tanpa tahu
  sandi aslinya. _Analogi:_ mencuri cetakan sidik jari lalu memakainya di
  pemindai lain. Mitigasi: sandi admin lokal unik (LAPS), isolasi tier,
  Protected Users/Credential Guard, kurangi NTLM.
- **Kerberoasting:** setiap akun domain boleh meminta tiket layanan (TGS) untuk
  akun layanan ber-SPN; bagian tiket terenkripsi dengan kunci turunan _sandi akun
  layanan_, lalu sandi ditebak **luring**. _Analogi:_ meminjam gembok resmi,
  membawanya pulang, mencoba ribuan kunci. Mitigasi: sandi akun layanan sangat
  panjang/acak atau gMSA, dan **Kerberos AES-only** sehingga tiket RC4 lemah tak terbit.

**Catatan notasi enctype:** atribut `msDS-SupportedEncryptionTypes = 24` memakai
_bitmask_ (24 = AES128+AES256). Field `TicketEncryptionType` pada event 4769
memakai nomor enctype Kerberos: `0x17`=RC4-HMAC, `0x18`=RC4-HMAC-EXP (lemah),
AES = `0x11/0x12`.

## d. Praktik: Instalasi dan Konfigurasi

### 1. Struktur OU, grup, dan akun layanan
```powershell
$dn = "DC=iamlab,DC=test"
"Tier0","Tier1-Servers","Pengguna","Grup","AkunLayanan" | % {
  New-ADOrganizationalUnit -Name $_ -Path $dn -ProtectedFromAccidentalDeletion $true -EA SilentlyContinue }
$grpOU = "OU=Grup,$dn"
"GG-Pimpinan","GG-Keuangan","GG-SDM","GG-TI","GG-Operasional","GG-Layanan","GG-Hukum",`
"GG-App-Viewer","GG-App-Editor","GG-App-Admin","GG-Tier0-Admin","GG-Tier1-Admin" | % {
  New-ADGroup -Name $_ -GroupScope Global -Path $grpOU -EA SilentlyContinue }
# akun layanan (dipakai Sesi 2/3) + honey SPN (deteksi Kerberoasting)
$svcOU = "OU=AkunLayanan,$dn"
foreach ($s in "svc-keycloak","svc-openbao","svc-app","svc-honey") {
  New-ADUser -Name $s -SamAccountName $s -UserPrincipalName "$s@iamlab.test" -Path $svcOU `
    -AccountPassword (ConvertTo-SecureString "Svc#Lab2026!" -AsPlainText -Force) `
    -Enabled $true -PasswordNeverExpires $true -EA SilentlyContinue }
setspn -S HTTP/honey.iamlab.test svc-honey
```

### 2. Bulk import pengguna (skrip di folder ini)
```powershell
.\import-ad.ps1 -Csv .\users_dummy.csv -UserOU "OU=Pengguna,$dn"
.\import-ad.ps1 -Csv .\users_batch2.csv -UserOU "OU=Pengguna,$dn"   # latihan mandiri +20
Get-ADUser -Filter * -SearchBase "OU=Pengguna,$dn" | Measure-Object
```
> `gen_dummy_users.py` membangkitkan CSV sintetis deterministik bila perlu data ulang:
> `python3 gen_dummy_users.py --count 200 --out users_dummy.csv`.

### 3. Akun admin terpisah & batasi Domain Admins
```powershell
New-ADUser -Name "adm-anda" -SamAccountName "adm-anda" -Path "OU=Tier0,$dn" `
  -AccountPassword (Read-Host -AsSecureString) -Enabled $true
Add-ADGroupMember -Identity "GG-Tier0-Admin" -Members "adm-anda"
Get-ADGroupMember "Domain Admins"        # sisakan ≤ 2
```

### 4. Kebijakan kata sandi + PSO untuk admin
```powershell
Set-ADDefaultDomainPasswordPolicy -Identity iamlab.test -MinPasswordLength 14 -ComplexityEnabled $true -LockoutThreshold 10
New-ADFineGrainedPasswordPolicy -Name "PSO-Admin" -Precedence 10 -MinPasswordLength 20 -ComplexityEnabled $true -LockoutThreshold 5
Add-ADFineGrainedPasswordPolicySubject "PSO-Admin" -Subjects "GG-Tier0-Admin"
```

### 5. Hardening inti
```powershell
Set-ADUser svc-keycloak -KerberosEncryptionType AES128,AES256 ; Set-ADAccountPassword svc-keycloak -Reset
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
auditpol /set /subcategory:"Kerberos Service Ticket Operations" /success:enable /failure:enable
```
> LDAP signing/LDAPS dan impor **Microsoft Security Baseline Windows Server 2025**
> (Security Compliance Toolkit) dilakukan lewat GPO pada langkah berikut.

### 6. GPO: buat → link → verifikasi

> Tangkapan layar GUI Windows (GPMC, ADUC, gpresult) disimpan di [`gambar/`](gambar/)
> dan diambil langsung di VM DC saat lab berjalan.

1. Buka **GPMC** (`gpmc.msc`), buat GPO `SEC-Audit-Tier1`, edit:
   _Computer Config → Policies → Windows Settings → Security Settings → Advanced Audit Policy_
   (Account Logon, Logon/Logoff, DS Access).
2. _Link_ ke `OU=Tier1-Servers`; atur **Security Filtering** (grup komputer).
3. Verifikasi:
   ```powershell
   gpupdate /force
   gpresult /h C:\gpreport.html ; start C:\gpreport.html
   ```

---

## Simulasi Terkendali & Mitigasi (PtH & Kerberoasting)

Defensif — hanya menguji **deteksi** dan **mitigasi** pada target lab di jaringan
Host-Only terisolasi. Runner `attack-sim/run.sh` mengunci target ke allowlist
`iamlab.test`, mewajibkan `IAMLAB_CONFIRM=1`, dan menolak bila internet terjangkau.

### Alur
1. Pastikan akun umpan ada: `setspn -L svc-honey` menampilkan `HTTP/honey.iamlab.test`.
2. Jalankan simulasi Kerberoasting (perkakas _open source_ Impacket) terhadap DC lab.
3. Amati **Event 4769** dengan `TicketEncryptionType = 0x17` (RC4) dari akun non-mesin,
   dan permintaan untuk honey SPN (di Event Viewer DC atau dashboard Grafana pada Sesi 4).
4. Terapkan mitigasi, lalu ulangi — tiket kini AES:
   ```powershell
   Set-ADUser svc-app -KerberosEncryptionType AES128,AES256 ; Set-ADAccountPassword svc-app -Reset
   ```
5. **Diskusi PtH (tanpa langkah ofensif):** mengapa Windows LAPS, Protected Users,
   dan isolasi tier memutus pemakaian ulang hash NTLM.

**Hasil yang diharapkan:** sebelum mitigasi terlihat 4769 RC4; setelah AES-only,
permintaan tiket memakai AES; peserta dapat menjelaskan mengapa mitigasi bekerja.
