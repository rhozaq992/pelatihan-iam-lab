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
$Root=$PSScriptRoot; $Deploy=Join-Path $Root 'deploy'
$Tar=Join-Path $Root 'distribusi\offline-images\iam-images.tar'
$docker=(Get-Command docker.exe -ErrorAction SilentlyContinue).Source
if(-not $docker){ Fail 'docker.exe tak ada - pastikan Docker Desktop terpasang dan berjalan.' }
& $docker info *> $null; if($LASTEXITCODE -ne 0){ Fail 'Docker Desktop tidak berjalan.' }

Write-Host "Update Lab IAM (tanpa hapus data/VM)" -ForegroundColor White

if($ClearWarpgateBlocks){
  Step 'Bersihkan blokir IP brute-force Warpgate (lab)'
  # Warpgate memblokir IP sumber setelah banyak login gagal (umum saat uji-coba SSO / banyak klien
  # di balik satu NAT). Kosongkan tabel blokir di DB Warpgate, lalu restart.
  $vol = (& $docker volume ls --format '{{.Name}}' | Select-String -Pattern 'warpgate-data' | Select-Object -First 1).ToString().Trim()
  if(-not $vol){ Warn 'volume warpgate-data tak ditemukan'; }
  else {
    Push-Location $Deploy; try { Invoke-Native $docker @('compose','stop','warpgate') | Out-Null } finally { Pop-Location }
    Invoke-Native $docker @('run','--rm','-v',"${vol}:/data",'alpine','sh','-c','apk add -q sqlite >/dev/null 2>&1; sqlite3 /data/db/db.sqlite3 "DELETE FROM ip_blocks; DELETE FROM failed_login_attempts;" 2>/dev/null; echo cleared') | Out-Null
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
  Step '3. Restart samba-dc (regen sertifikat LDAPS ber-SAN bila perlu)'
  Invoke-Native $docker @('compose','restart','samba-dc') | Out-Null; Ok 'samba-dc di-restart'
} finally { Pop-Location }

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
