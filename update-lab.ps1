<#
.SYNOPSIS
  Update lab IAM yang SUDAH terbangun ke versi perbaikan - TANPA menghapus data/VM.

.DESCRIPTION
  Dipakai di PC peserta/fasilitator yang labnya sudah jalan, untuk menerapkan perbaikan modul dan
  infra tanpa Destroy/rebuild. Langkah:
    1. (Opsional) Salin folder builder versi baru menimpa yang lama - PERTAHANKAN folder .lab
       (cache, VM, log) dan Pelatihan_IAM (modul). Lalu jalankan skrip ini dari folder builder.
    2. Muat image Docker baru dari distribusi/offline-images/iam-images.tar (samba-dc SAN, attacker
       impacket 0.13, app-komentar scope, dll.).
    3. docker compose up -d -> hanya container dgn image/konfig berubah yang dibuat ulang; VOLUME
       (data Samba/Keycloak/OpenBao/dll.) dan VM VirtualBox TIDAK disentuh.
    4. Restart samba-dc -> entrypoint meregenerasi sertifikat LDAPS ber-SAN bila belum ada.
    5. git pull modul (dokumen + screenshot Sesi) bila folder Pelatihan_IAM ada.

  Jalankan di PowerShell Administrator dari folder builder:
    Set-ExecutionPolicy -Scope Process Bypass -Force
    .\update-lab.ps1
#>
[CmdletBinding()]
param([switch]$SkipImages, [switch]$SkipGit, [switch]$ClearWarpgateBlocks)
$ErrorActionPreference = 'Stop'
function Step($m){ Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "  [OK] $m" -ForegroundColor Green }
function Warn($m){ Write-Host "  [!]  $m" -ForegroundColor Yellow }
function Fail($m){ Write-Host "  [X]  $m" -ForegroundColor Red; throw $m }
function Invoke-Native($exe,$argList){
  $old=$ErrorActionPreference; $ErrorActionPreference='Continue'
  try { & $exe @argList 2>&1 | Out-Host } finally { $ErrorActionPreference=$old }
  return $LASTEXITCODE
}
# docker/git kadang menulis WARNING ke stderr (mis. "No blkio throttle...") -> dgn
# $ErrorActionPreference='Stop', PowerShell 5.1 membungkusnya jadi NativeCommandError yg
# MELEMPAR walau exit code 0. Helper ini menilai berdasarkan exit code, bukan stderr.
function Test-NativeOk($exe,$argList){
  $old=$ErrorActionPreference; $ErrorActionPreference='Continue'
  try { & $exe @argList 2>&1 | Out-Null } finally { $ErrorActionPreference=$old }
  return ($LASTEXITCODE -eq 0)
}
function Get-DockerVolumeName($docker,$pattern){
  $old=$ErrorActionPreference; $ErrorActionPreference='Continue'
  try { $m = & $docker volume ls --format '{{.Name}}' 2>&1 | Select-String -Pattern $pattern | Select-Object -First 1 }
  finally { $ErrorActionPreference=$old }
  if($m){ return $m.ToString().Trim() } else { return $null }
}
$Root=$PSScriptRoot
# Skrip ini butuh folder BUILDER (ada deploy/). Bila dijalankan dari subfolder modul
# (IAMLAB-BuildBag\Pelatihan_IAM, hasil git pull), naik satu level ke builder.
if(-not (Test-Path (Join-Path $Root 'deploy')) -and (Test-Path (Join-Path (Split-Path $Root -Parent) 'deploy'))){
  $Root=Split-Path $Root -Parent
}
$Deploy=Join-Path $Root 'deploy'
$Tar=Join-Path $Root 'distribusi\offline-images\iam-images.tar'
$docker=(Get-Command docker.exe -ErrorAction SilentlyContinue).Source
if(-not $docker){ Fail 'docker.exe tak ada - pastikan Docker Desktop terpasang dan berjalan.' }
if(-not (Test-NativeOk $docker @('info'))){ Fail 'Docker Desktop tidak berjalan.' }

Write-Host "Update Lab IAM (tanpa hapus data/VM)" -ForegroundColor White

if($ClearWarpgateBlocks){
  Step 'Bersihkan blokir IP brute-force Warpgate (lab)'
  # Warpgate memblokir IP sumber setelah banyak login gagal (umum saat uji-coba SSO / banyak klien
  # di balik satu NAT). Kosongkan tabel blokir di DB Warpgate, lalu restart.
  $vol = Get-DockerVolumeName $docker 'warpgate-data'
  if(-not $vol){ Warn 'volume warpgate-data tak ditemukan'; }
  else {
    Push-Location $Deploy; try { Invoke-Native $docker @('compose','stop','warpgate') | Out-Null } finally { Pop-Location }
    # SQL via STDIN agar tak ada quote bersarang yg di-mangle PowerShell
    $old=$ErrorActionPreference; $ErrorActionPreference='Continue'
    'DELETE FROM ip_blocks; DELETE FROM failed_login_attempts;' |
      & $docker run -i --rm -v "${vol}:/data" alpine sh -c 'apk add -q sqlite >/dev/null 2>&1; sqlite3 /data/db/db.sqlite3' 2>&1 | Out-Host
    $ErrorActionPreference=$old
    Push-Location $Deploy; try { Invoke-Native $docker @('compose','start','warpgate') | Out-Null } finally { Pop-Location }
    Ok 'blokir IP & percobaan gagal Warpgate dikosongkan; warpgate di-restart'
  }
  Write-Host '  (Selesai -ClearWarpgateBlocks)' -ForegroundColor Gray
  return
}

if(-not $SkipImages){
  Step '1. Muat image Docker baru (iam-images.tar)'
  if(Test-Path $Tar){ Invoke-Native $docker @('load','-i',$Tar) | Out-Null; Ok "image dimuat dari $([IO.Path]::GetFileName($Tar))" }
  else { Warn "iam-images.tar tak ada di $Tar - lewati" }
} else { Ok 'lewati muat image (-SkipImages)' }

Step '2. Terapkan konfig dan buat ulang container yang berubah (volume dan VM aman)'
Push-Location $Deploy
try {
  if((-not (Test-Path (Join-Path $Deploy '.env'))) -and (Test-Path (Join-Path $Deploy '.env.example'))){
    Copy-Item (Join-Path $Deploy '.env.example') (Join-Path $Deploy '.env'); Ok 'deploy/.env dibuat dari .env.example'
  }
  Invoke-Native $docker @('compose','up','-d','--no-build') | Out-Null
  Ok 'compose up -d (hanya service berubah yang dibuat ulang)'
} finally { Pop-Location }

Step '3. Pastikan sertifikat LDAPS Samba ber-SAN (perbaikan OpenBao Sesi 3)'
# Lab LAMA: cert LDAPS sering CN-only (tanpa SAN) -> OpenBao (Go) menolak. Regen cert ber-SAN
# via helper alpine (tak bergantung openssl/entrypoint di image samba lama), pakai volume samba.
$sambaVol = Get-DockerVolumeName $docker 'samba-data'
if ($sambaVol) {
  # skrip sh TANPA tanda kutip ganda (hindari mangling PowerShell); deteksi SAN via grep kata 'Alternative'
  $gen = 'apk add -q openssl >/dev/null 2>&1; cd /d/private/tls 2>/dev/null || exit 0; ' +
         'openssl x509 -in cert.pem -noout -text 2>/dev/null | grep -q Alternative && { echo has-san; exit 0; }; ' +
         'openssl req -x509 -newkey rsa:4096 -keyout key.new -out cert.new -days 3650 -nodes ' +
         '-subj /O=iamlab/CN=DC1.iamlab.test -addext subjectAltName=DNS:dc1.iamlab.test,IP:10.10.10.5 >/dev/null 2>&1; ' +
         'mv cert.new cert.pem; mv key.new key.pem; cp cert.pem ca.pem; chmod 600 key.pem; chmod 644 cert.pem ca.pem; echo regenerated'
  $o = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $res = & $docker run --rm -v "${sambaVol}:/d" alpine sh -c $gen 2>&1 | Out-String
  $ErrorActionPreference = $o
  if ($res -match 'regenerated') {
    Ok 'cert LDAPS ber-SAN dibuat; restart samba-dc + re-ekspor CA + recreate keycloak/openbao'
    Push-Location $Deploy
    try {
      Invoke-Native $docker @('compose','restart','samba-dc') | Out-Null
      Start-Sleep -Seconds 8
      Invoke-Native $docker @('compose','cp','samba-dc:/var/lib/samba/private/tls/ca.pem','certs/ad-ca.pem') | Out-Null
      Invoke-Native $docker @('compose','up','-d','--force-recreate','keycloak','openbao') | Out-Null
    } finally { Pop-Location }
  } else { Ok 'cert LDAPS sudah ber-SAN (tak perlu regen); restart samba-dc' ; Push-Location $Deploy; try { Invoke-Native $docker @('compose','restart','samba-dc') | Out-Null } finally { Pop-Location } }
} else { Warn 'volume samba-data tak ditemukan - lewati pengecekan SAN' }

if(-not $SkipGit){
  $modul=Join-Path $Root 'Pelatihan_IAM'
  if(Test-Path (Join-Path $modul '.git')){
    Step '4. Update modul (git pull): dokumen dan screenshot sesi'
    $git=(Get-Command git.exe -ErrorAction SilentlyContinue).Source
    if($git){ Push-Location $modul; try { Invoke-Native $git @('pull','--ff-only') | Out-Null; Ok 'modul diperbarui' } finally { Pop-Location } }
    else { Warn 'git tak ada - lewati update modul' }
  } else { Warn 'folder Pelatihan_IAM (modul) belum di-clone - lewati git pull' }
}

Step 'Selesai'
Write-Host '  Data (volume) dan VM tetap utuh. Cek: .\build-lab.ps1 -Phase Status' -ForegroundColor Gray
Write-Host '  Catatan: perbaikan Sesi 1 (ntlmv2-only) dan SSO Warpgate (CA Caddy, external_port,' -ForegroundColor Gray
Write-Host '           emailVerified) diterapkan mengikuti README sesi terkait.' -ForegroundColor Gray
