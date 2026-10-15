<#
.SYNOPSIS
  Update lab IAM yang SUDAH terbangun ke versi perbaikan — TANPA menghapus data/VM.

.DESCRIPTION
  Dipakai di PC peserta/fasilitator yang labnya sudah jalan, untuk menerapkan perbaikan modul &
  infra tanpa `Destroy`/rebuild. Langkah:
    1. (Opsional) Salin dulu folder builder versi baru menimpa yang lama — PERTAHANKAN folder `.lab`
       (cache, VM, log) dan `Pelatihan_IAM` (modul). Lalu jalankan skrip ini dari folder builder.
    2. Muat image Docker baru dari distribusi/offline-images/iam-images.tar (samba-dc SAN, attacker
       impacket 0.13, app-komentar scope, dll.).
    3. `docker compose up -d` -> hanya container dgn image/konfig berubah yang dibuat ulang;
       VOLUME (data Samba/Keycloak/OpenBao/dll.) & VM VirtualBox TIDAK disentuh.
    4. Restart samba-dc -> entrypoint meregenerasi sertifikat LDAPS ber-SAN bila belum ada.
    5. `git pull` modul (dokumen + screenshot Sesi) bila folder Pelatihan_IAM ada.

  Jalankan di PowerShell **Administrator** dari folder builder:
    Set-ExecutionPolicy -Scope Process Bypass -Force
    .\update-lab.ps1
#>
[CmdletBinding()]
param([switch]$SkipImages, [switch]$SkipGit)
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
if(-not $docker){ Fail 'docker.exe tak ada — pastikan Docker Desktop terpasang & berjalan.' }
& $docker info *> $null; if($LASTEXITCODE -ne 0){ Fail 'Docker Desktop tidak berjalan.' }

Write-Host "Update Lab IAM (tanpa hapus data/VM)" -ForegroundColor White

if(-not $SkipImages){
  Step '1. Muat image Docker baru (iam-images.tar)'
  if(Test-Path $Tar){ Invoke-Native $docker @('load','-i',$Tar) | Out-Null; Ok "image dimuat dari $([IO.Path]::GetFileName($Tar))" }
  else { Warn "iam-images.tar tak ada di $Tar — lewati (pakai -SkipImages bila disengaja)" }
} else { Ok 'lewati muat image (-SkipImages)' }

Step '2. Terapkan konfig & buat ulang container yang berubah (volume & VM aman)'
Push-Location $Deploy
try {
  if(-not (Test-Path (Join-Path $Deploy '.env')) -and (Test-Path (Join-Path $Deploy '.env.example'))){
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
    Step '4. Update modul (git pull) — dokumen & screenshot sesi'
    $git=(Get-Command git.exe -ErrorAction SilentlyContinue).Source
    if($git){ Push-Location $modul; try { Invoke-Native $git @('pull','--ff-only') | Out-Null; Ok 'modul diperbarui' } finally { Pop-Location } }
    else { Warn 'git tak ada — lewati update modul' }
  } else { Warn 'folder Pelatihan_IAM (modul) belum di-clone — lewati git pull' }
}

Step 'Selesai'
Write-Host '  Data (volume) & VM tetap utuh. Cek: .\build-lab.ps1 -Phase Status' -ForegroundColor Gray
Write-Host '  Catatan: perbaikan Sesi 1 (ntlmv2-only) & SSO Warpgate (CA Caddy/external_port/emailVerified)' -ForegroundColor Gray
Write-Host '           diterapkan peserta/fasilitator mengikuti README sesi terkait.' -ForegroundColor Gray
