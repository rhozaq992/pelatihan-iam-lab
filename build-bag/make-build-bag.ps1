<#
.SYNOPSIS
  Rakit "paket build" Lab IAM: HANYA aset berat untuk build (installer VirtualBox, Docker
  Desktop, WSL2, VC++; iam-images.tar; VM Ubuntu SIAP-PAKAI). Modul, skrip & konfigurasi TIDAK
  disertakan - peserta tetap `git clone` repo, lalu menyalin folder `distribusi\` dari paket ke
  repo hasil clone. Tujuan: build di PC peserta tanpa unduhan besar.

.DESCRIPTION
  Dijalankan di PC "penyiap" (ada internet + Docker Desktop + VirtualBox). Langkah:
    1. Unduh SEMUA installer Windows (VirtualBox, Docker Desktop, WSL2 MSI, VC++) ke cache --
       lewat `build-lab.ps1 -Phase Download -BundleAll` (tak peduli apa yang sudah terpasang).
    2. Bangun & simpan iam-images.tar (semua image Docker, termasuk Samba AD); tar usang dibangun ulang.
    3. (-BakeVMs) Ekspor VM `iamlab-srv1`/`iamlab-client1` yang sudah di-provision (dari
       .lab/vms) menjadi VDI siap-pakai di distribusi/vms/ -> peserta impor tanpa apt/internet.
    4. Tulis paket berstruktur sama dengan repo (distribusi\installer|offline-images|vms) +
       INSTALL.txt + SHA256SUMS.txt. Ubuntu cloud image & datastream CIS tidak disertakan: hanya
       dipakai saat provisioning VM, yang memang butuh internet (apt).

  Alur khas penyiap:
    .\build-lab.ps1                      # bangun lab sekali (VM ter-provision di .lab/vms)
    .\build-bag\make-build-bag.ps1 -BakeVMs -Zip

.EXAMPLE
  .\build-bag\make-build-bag.ps1 -BakeVMs
  .\build-bag\make-build-bag.ps1 -Out D:\IAMLAB-BuildBag -SkipImages
#>
[CmdletBinding()]
param(
  [string]$Out = (Join-Path $PSScriptRoot '..\..\IAMLAB-BuildBag'),   # di luar repo (aset tak masuk git)
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
# Jalankan program native tanpa menganggap stderr (mis. progres VBoxManage '0%..100%') fatal.
function Invoke-Quiet { param([string]$Exe,[string[]]$A)
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { & $Exe @A 2>&1 | Out-Null } finally { $ErrorActionPreference = $old }
  return $LASTEXITCODE
}
function Get-TarImages([string]$Path) {
  # daftar repo:tag di dalam arsip 'docker save' (dibaca dari manifest.json, tanpa memuat image)
  $m = & (Join-Path $env:SystemRoot 'System32\tar.exe') -xOf $Path manifest.json 2>$null
  if (-not $m) { return @() }
  return @(($m | Out-String | ConvertFrom-Json) | ForEach-Object { $_.RepoTags } | Where-Object { $_ })
}

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
  # tar lama (mis. dari arsitektur v1) bisa tak memuat image yang kini dipakai compose -> bangun ulang
  if ((Test-Path $Tar) -and $Docker) {
    Push-Location $Deploy
    try { $need = & $Docker compose --profile '*' config --images } finally { Pop-Location }
    $have = Get-TarImages $Tar
    $miss = @($need | ForEach-Object { if ($_ -notmatch ':[^/]+$') { "${_}:latest" } else { $_ } } | Where-Object { $have -notcontains $_ })
    if ($miss.Count) { Warn "iam-images.tar usang - tidak memuat: $($miss -join ', '); dibangun ulang"; Remove-Item $Tar -Force }
  }
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
    $info = & { $ErrorActionPreference='Continue'; & $vb showvminfo $name --machinereadable 2>$null }
    $st = ($info | Where-Object { $_ -match '^VMState=' }) -replace '^VMState="?','' -replace '"$',''
    if ($st -in 'running','paused') { Invoke-Quiet $vb @('controlvm',$name,'poweroff') | Out-Null; Start-Sleep 4 }
    $vdi = Join-Path $VmDir "$name\$name.vdi"
    if (-not (Test-Path $vdi)) { Warn "$name belum di-provision (.lab/vms kosong) - jalankan build-lab.ps1 dulu. Lewati."; continue }
    Invoke-Quiet $vb @('modifymedium','disk',$vdi,'--compact') | Out-Null
    Copy-Item $vdi (Join-Path $PrebakedDir "$name.vdi") -Force
    Ok "$name.vdi diekspor ($([math]::Round((Get-Item (Join-Path $PrebakedDir "$name.vdi")).Length/1GB,2)) GB)"
  }
} elseif (Get-ChildItem $PrebakedDir -Filter *.vdi -ErrorAction SilentlyContinue) {
  Ok 'pakai VDI siap-pakai yang sudah ada di distribusi/vms (ekspor ulang: -BakeVMs)'
} else { Warn 'tanpa VDI siap-pakai: VM di PC peserta akan di-provision (butuh internet untuk apt).' }

# 4. paket = HANYA aset build, berstruktur sama dengan repo (distribusi\...) -> disalin ke repo hasil clone
Step 'Tulis aset build ke paket'
# tata letak lama (salinan repo utuh di <Out>\Pelatihan_IAM) & aset usang dibuang dulu
foreach ($old in 'Pelatihan_IAM','distribusi') {
  $p = Join-Path $Out $old
  if (Test-Path $p) { Remove-Item $p -Recurse -Force; Ok "hapus isi paket lama: $old\" }
}
function Add-Asset([string]$Src, [string]$RelDir) {
  # hardlink bila satu volume (instan, hemat disk); salin bila beda volume (mis. -Out ke USB)
  $dir = Join-Path $Out $RelDir; New-Item -ItemType Directory -Force $dir | Out-Null
  $dst = Join-Path $dir (Split-Path $Src -Leaf)
  try { New-Item -ItemType HardLink -Path $dst -Target $Src -ErrorAction Stop | Out-Null }
  catch { Copy-Item $Src $dst -Force }
  Ok ("{0}\{1} ({2} GB)" -f $RelDir, (Split-Path $Src -Leaf), [math]::Round((Get-Item $Src).Length/1GB,2))
}
# installer Windows saja (tanpa Ubuntu cloud image / golden VDI di cache)
$inst = @(Get-ChildItem $Cache -File | Where-Object { $_.Name -match '^(VirtualBox-.*-Win\.exe|vc_redist\.x64\.exe|DockerDesktopInstaller\.exe|wsl-update\.msi)$' })
foreach ($n in 'VirtualBox-*-Win.exe','vc_redist.x64.exe','DockerDesktopInstaller.exe','wsl-update.msi') {
  if (-not ($inst | Where-Object Name -like $n)) { Fail "installer tak ada di cache: $n" }
}
# VirtualBox: hanya versi terbaru (sama dengan yang dipilih fase Install)
$vbOld = @($inst | Where-Object Name -like 'VirtualBox-*' | Sort-Object Name | Select-Object -SkipLast 1)
$inst | Where-Object { $vbOld -notcontains $_ } | ForEach-Object { Add-Asset $_.FullName 'distribusi\installer' }
if (-not $SkipImages) { Add-Asset $Tar 'distribusi\offline-images' }
Get-ChildItem $PrebakedDir -Filter *.vdi -ErrorAction SilentlyContinue | Where-Object { $VMs -contains $_.BaseName } |
  ForEach-Object { Add-Asset $_.FullName 'distribusi\vms' }

# 5. INSTALL.txt + checksum
Step 'Tulis INSTALL.txt & checksum'
$install = @'
==========================================================
  PAKET BUILD LAB IAM - Petunjuk untuk Panitia
==========================================================
Paket ini HANYA berisi aset berat untuk build (installer, image Docker, VM siap-pakai).
Modul & skrip lab diambil dari repo Git.

Prasyarat PC peserta: Windows 10/11 Pro, RAM 16 GB, disk kosong >= 80 GB,
virtualisasi (VT-x/AMD-V) AKTIF di BIOS/UEFI, hak Administrator, Git.

LANGKAH:
  1. Clone repo lab (mis. ke C:\Lab):
         git clone https://github.com/rhozaq992/pelatihan-iam-lab.git C:\Lab\Pelatihan_IAM
  2. Salin folder "distribusi" dari paket ini ke dalam repo hasil clone
     (gabungkan dengan distribusi\ yang sudah ada):
         robocopy <paket>\distribusi C:\Lab\Pelatihan_IAM\distribusi /E
  3. PowerShell sebagai ADMINISTRATOR:
         cd C:\Lab\Pelatihan_IAM
         Set-ExecutionPolicy -Scope Process Bypass -Force
         .\build-lab.ps1
  4. Bila diminta REBOOT (WSL2/Docker Desktop), reboot lalu jalankan lagi: .\build-lab.ps1
  5. Selesai saat "Lab siap". Cek: .\build-lab.ps1 -Phase Status

Isi paket:
  distribusi/installer/                      -> VirtualBox, Docker Desktop, WSL2 MSI, VC++ runtime
  distribusi/offline-images/iam-images.tar   -> semua image Docker lab (dimuat otomatis)
  distribusi/vms/*.vdi                       -> VM Ubuntu srv1 & client1 SIAP-PAKAI (diimpor otomatis)
  SHA256SUMS.txt                             -> checksum aset (cek sebelum build bila disalin via USB)

Catatan: bila distribusi/vms/ TIDAK ada, VM di-provision di PC peserta dan butuh internet
(Ubuntu cloud image + paket apt). Dengan distribusi/vms/, build berjalan tanpa unduhan.

Akun lab (sintetis): Administrator domain / Passw0rd#Lab2026 ; labadmin / Lab#Admin2026
Log bila bermasalah: .lab\logs\build-*.log (lihat baris "BERHENTI:")
==========================================================
'@
Set-Content (Join-Path $Out 'INSTALL.txt') $install -Encoding UTF8
Get-ChildItem (Join-Path $Out 'distribusi') -Recurse -File | Sort-Object FullName |
  ForEach-Object { "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash, ($_.FullName.Substring($Out.Length + 1) -replace '\\','/') } |
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
