<#
.SYNOPSIS
  Rakit "paket build" Lab IAM: satu folder berisi build-lab.ps1, repo lab, SEMUA installer
  (VirtualBox, Docker Desktop, WSL2, VC++), Ubuntu cloud image, iam-images.tar, datastream CIS,
  dan (opsional) VM Ubuntu SIAP-PAKAI - siap diserahkan ke panitia. Tujuan: di PC peserta
  TIDAK perlu unduh apa pun.

.DESCRIPTION
  Dijalankan di PC "penyiap" (ada internet + Docker Desktop + VirtualBox). Langkah:
    1. Unduh SEMUA installer Windows (VirtualBox, Docker Desktop, WSL2 MSI, VC++) + Ubuntu cloud
       image ke cache -- lewat `build-lab.ps1 -Phase Download -BundleAll` (tak peduli apa yang
       sudah terpasang di PC penyiap).
    2. Bangun & simpan iam-images.tar (semua image Docker, termasuk Samba AD).
    3. (-BakeVMs) Ekspor VM `iamlab-srv1`/`iamlab-client1` yang sudah di-provision (dari
       .lab/vms) menjadi VDI siap-pakai di distribusi/vms/ -> peserta impor tanpa apt/internet.
    4. Salin repo lab + semua aset ke folder keluaran, tulis INSTALL.txt + checksum.

  Alur khas penyiap:
    .\build-lab.ps1                      # bangun lab sekali (VM ter-provision di .lab/vms)
    .\build-bag\make-build-bag.ps1 -BakeVMs -Zip

.EXAMPLE
  .\build-bag\make-build-bag.ps1 -BakeVMs
  .\build-bag\make-build-bag.ps1 -Out D:\IAMLAB-BuildBag -SkipImages
#>
[CmdletBinding()]
param(
  [string]$Out = (Join-Path $PSScriptRoot '..\IAMLAB-BuildBag'),
  [switch]$SkipImages,   # jangan sertakan iam-images.tar
  [switch]$BakeVMs,      # ekspor VM siap-pakai (VDI) dari .lab/vms -> distribusi/vms
  [switch]$Zip
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!] $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "  [X] $m" -ForegroundColor Red; throw $m }

$Repo   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Deploy = Join-Path $Repo 'deploy'
$Cache  = Join-Path $Repo '.lab\cache'
$VmDir  = Join-Path $Repo '.lab\vms'
$Tar    = Join-Path $Repo 'distribusi\offline-images\iam-images.tar'
$PrebakedDir = Join-Path $Repo 'distribusi\vms'
$Docker = (Get-Command docker.exe -ErrorAction SilentlyContinue).Source
$vb = @("$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
$Out    = [IO.Path]::GetFullPath($Out)
$VMs = @('iamlab-srv1','iamlab-client1')

Step "Paket build Lab IAM -> $Out"
New-Item -ItemType Directory -Force $Out | Out-Null

# 1. installer + cloud image (SEMUA, via BundleAll)
Step 'Unduh SEMUA installer Windows + Ubuntu cloud image (offline bundle)'
& (Join-Path $Repo 'build-lab.ps1') -Phase Download -BundleAll
Ok 'cache installer siap'

# 2. image Docker offline
if (-not $SkipImages) {
  if (-not (Test-Path $Tar)) {
    if (-not $Docker) { Fail 'Docker tak ada; pakai -SkipImages atau pasang Docker Desktop.' }
    & $Docker info *> $null; if ($LASTEXITCODE -ne 0) { Fail 'Docker Desktop tidak berjalan.' }
    Step 'Bangun & simpan iam-images.tar (semua image, ~3-4 GB)'
    New-Item -ItemType Directory -Force (Split-Path $Tar) | Out-Null
    Push-Location $Deploy
    try {
      & $Docker compose --profile '*' pull --ignore-buildable
      & $Docker compose --profile '*' build
      & $Docker save (& $Docker compose --profile '*' config --images) -o $Tar
    } finally { Pop-Location }
  }
  Ok "iam-images.tar ($([math]::Round((Get-Item $Tar).Length/1GB,2)) GB)"
} else { Ok 'lewati image (-SkipImages)' }

# 3. (opsional) ekspor VM siap-pakai
if ($BakeVMs) {
  Step 'Ekspor VM siap-pakai (VDI ter-provision) -> distribusi/vms'
  if (-not $vb) { Fail 'VBoxManage tak ada untuk ekspor VM.' }
  New-Item -ItemType Directory -Force $PrebakedDir | Out-Null
  foreach ($name in $VMs) {
    $st = (& $vb showvminfo $name --machinereadable 2>$null | Where-Object { $_ -match '^VMState=' }) -replace '^VMState="?','' -replace '"$',''
    if ($st -in 'running','paused') { & $vb controlvm $name poweroff *> $null; Start-Sleep 4 }
    $vdi = Join-Path $VmDir "$name\$name.vdi"
    if (-not (Test-Path $vdi)) { Warn "$name belum di-provision (.lab/vms kosong) - jalankan build-lab.ps1 dulu. Lewati."; continue }
    & $vb modifymedium disk $vdi --compact *> $null
    Copy-Item $vdi (Join-Path $PrebakedDir "$name.vdi") -Force
    Ok "$name.vdi diekspor ($([math]::Round((Get-Item (Join-Path $PrebakedDir "$name.vdi")).Length/1GB,2)) GB)"
  }
} else { Warn 'tanpa -BakeVMs: VM di PC peserta akan di-provision (butuh internet sekali untuk apt).' }

# 4. salin repo (bersih) + aset
Step 'Salin repo lab + aset ke paket'
$repoOut = Join-Path $Out 'Pelatihan_IAM'
$exTmp = @('.git','.lab','node_modules','IAMLAB-BuildBag')
& robocopy $Repo $repoOut /E /NFL /NDL /NJH /NJS /NP /XD @exTmp (Join-Path $Deploy 'caddy\data') (Join-Path $Deploy 'caddy\config') | Out-Null
if ($LASTEXITCODE -ge 8) { Fail "robocopy gagal (kode $LASTEXITCODE)" }
# installer (termasuk WSL MSI) ke distribusi/installer
$instOut = Join-Path $repoOut 'distribusi\installer'
New-Item -ItemType Directory -Force $instOut | Out-Null
Copy-Item (Join-Path $Cache '*') $instOut -Recurse -Force -ErrorAction SilentlyContinue
# ubuntu cloud image dipindah ke installer (hindari ganda di cache)
# iam-images.tar
if (-not $SkipImages) {
  New-Item -ItemType Directory -Force (Join-Path $repoOut 'distribusi\offline-images') | Out-Null
  Copy-Item $Tar (Join-Path $repoOut 'distribusi\offline-images\iam-images.tar') -Force
}
Ok 'repo + aset tersalin'

# 5. INSTALL.txt + checksum
Step 'Tulis INSTALL.txt & checksum'
$install = @'
==========================================================
  PAKET BUILD LAB IAM - Petunjuk untuk Panitia (OFFLINE)
==========================================================
Prasyarat PC peserta: Windows 10/11 Pro, RAM 16 GB, disk kosong >= 80 GB,
virtualisasi (VT-x/AMD-V) AKTIF di BIOS/UEFI. Hak Administrator.
TIDAK perlu internet: semua installer, image, dan (bila disertakan) VM siap-pakai ada di paket.

LANGKAH:
  1. Salin folder "Pelatihan_IAM" ke PC peserta (mis. C:\Lab\Pelatihan_IAM).
  2. PowerShell sebagai ADMINISTRATOR:
         cd C:\Lab\Pelatihan_IAM
         Set-ExecutionPolicy -Scope Process Bypass -Force
         .\build-lab.ps1
  3. Bila diminta REBOOT (WSL2/Docker Desktop), reboot lalu jalankan lagi: .\build-lab.ps1
  4. Selesai saat "Lab siap". Cek: .\build-lab.ps1 -Phase Status

Isi paket:
  build-lab.ps1                              -> pembangun lab (jalankan ini)
  distribusi/installer/                      -> VirtualBox, Docker Desktop, WSL2 MSI, VC++, Ubuntu cloud image
  distribusi/offline-images/iam-images.tar   -> semua image Docker (dimuat otomatis)
  distribusi/vms/*.vdi                        -> VM Ubuntu SIAP-PAKAI (bila ada; diimpor tanpa provisioning)
  lab/cis/ssg-ubuntu2404-ds.xml               -> datastream CIS (OpenSCAP) offline
  sesi-0-pengantar/ .. sesi-4-...             -> modul pelatihan

Catatan: bila distribusi/vms/ TIDAK ada, VM di-provision di PC peserta dan butuh internet
SEKALI untuk unduh paket Ubuntu (sssd/auditd/OpenSCAP/Alloy/desktop). Dengan distribusi/vms/
(paket dibuat dengan -BakeVMs), VM diimpor langsung -> tanpa internet sama sekali.

Akun lab (sintetis): Administrator domain / Passw0rd#Lab2026 ; labadmin / Lab#Admin2026
Log bila bermasalah: .lab\logs\build-*.log (lihat baris "BERHENTI:")
==========================================================
'@
Set-Content (Join-Path $Out 'INSTALL.txt') $install -Encoding UTF8
Get-ChildItem (Join-Path $repoOut 'distribusi') -Recurse -File -Include *.tar,*.vdi,*.ova,*.exe,*.msi -ErrorAction SilentlyContinue |
  ForEach-Object { "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash, $_.Name } |
  Set-Content (Join-Path $Out 'SHA256SUMS.txt') -Encoding ASCII
Ok 'INSTALL.txt + SHA256SUMS.txt'

if ($Zip) {
  Step 'Buat arsip .zip (bisa lama utk paket besar)'
  $zip = "$Out.zip"; if (Test-Path $zip) { Remove-Item $zip }
  Compress-Archive -Path (Join-Path $Out '*') -DestinationPath $zip
  Ok $zip
}
$size = [math]::Round(((Get-ChildItem $Out -Recurse -File | Measure-Object Length -Sum).Sum)/1GB, 2)
Write-Host "`nSelesai. Paket build: $Out  (~$size GB)" -ForegroundColor Green
Write-Host "Serahkan folder ini (atau .zip) ke panitia. Di PC peserta: baca INSTALL.txt."
