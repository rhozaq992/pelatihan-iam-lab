<#
.SYNOPSIS
  Rakit "paket build" Lab IAM: satu folder berisi build-lab.ps1, repo lab, semua installer,
  dan iam-images.tar — siap diserahkan ke panitia (USB/share) untuk dipasang di PC peserta.

.DESCRIPTION
  Dijalankan di PC "penyiap" yang punya internet dan Docker Desktop. Langkah:
    1. Pastikan iam-images.tar ada (build & docker save bila belum) — semua image offline.
    2. Unduh installer (VirtualBox, VC++, Docker Desktop) + Ubuntu cloud image ke cache
       (memanggil build-lab.ps1 -Phase Download).
    3. Salin repo lab (tanpa .git, .lab, node_modules) + build-lab.ps1 + installer + image
       ke folder keluaran, plus INSTALL.txt & checksum.
  Hasil: folder <Out> (default .\IAMLAB-BuildBag) yang di-zip/USB-kan ke panitia.
  Di PC peserta, panitia cukup: ekstrak, lalu jalankan build-lab.ps1 (lihat INSTALL.txt).

.EXAMPLE
  .\build-bag\make-build-bag.ps1
  .\build-bag\make-build-bag.ps1 -Out D:\IAMLAB-BuildBag -SkipImages
#>
[CmdletBinding()]
param(
  [string]$Out = (Join-Path $PSScriptRoot '..\IAMLAB-BuildBag'),
  [switch]$SkipImages,       # jangan bangun/sertakan iam-images.tar (akan diunduh saat build di PC peserta)
  [switch]$Zip               # buat juga <Out>.zip
)
$ErrorActionPreference = 'Stop'
function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Fail($m) { Write-Host "  [X] $m" -ForegroundColor Red; throw $m }

$Repo   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Deploy = Join-Path $Repo 'deploy'
$Cache  = Join-Path $Repo '.lab\cache'
$Tar    = Join-Path $Repo 'distribusi\offline-images\iam-images.tar'
$Docker = (Get-Command docker.exe -ErrorAction SilentlyContinue).Source
$Out    = [IO.Path]::GetFullPath($Out)

Step "Paket build Lab IAM -> $Out"
New-Item -ItemType Directory -Force $Out | Out-Null

# 1. image offline
if (-not $SkipImages) {
  if (-not (Test-Path $Tar)) {
    if (-not $Docker) { Fail 'Docker tak ada; jalankan dengan -SkipImages atau pasang Docker Desktop.' }
    & $Docker info *> $null; if ($LASTEXITCODE -ne 0) { Fail 'Docker Desktop tidak berjalan.' }
    Step 'Bangun & simpan iam-images.tar (semua image, ~3-4 GB)'
    New-Item -ItemType Directory -Force (Split-Path $Tar) | Out-Null
    Push-Location $Deploy
    try {
      & $Docker compose --profile '*' pull --ignore-buildable
      & $Docker compose --profile '*' build
      $imgs = & $Docker compose --profile '*' config --images
      & $Docker save $imgs -o $Tar
    } finally { Pop-Location }
  }
  Ok "iam-images.tar ($([math]::Round((Get-Item $Tar).Length/1GB,2)) GB)"
} else { Ok 'lewati image (-SkipImages)' }

# 2. installer + cloud image ke cache (lewat build-lab.ps1)
Step 'Unduh installer & Ubuntu cloud image ke cache'
& (Join-Path $Repo 'build-lab.ps1') -Phase Download
Ok 'cache siap'

# 3. salin repo (bersih) + aset
Step 'Salin repo lab (tanpa .git/.lab/node_modules)'
$repoOut = Join-Path $Out 'Pelatihan_IAM'
$exclude = @('.git', '.lab', 'node_modules', 'IAMLAB-BuildBag')
& robocopy $Repo $repoOut /E /NFL /NDL /NJH /NJS /NP /XD @exclude ($Deploy + '\caddy\data') ($Deploy + '\caddy\config') | Out-Null
if ($LASTEXITCODE -ge 8) { Fail "robocopy gagal (kode $LASTEXITCODE)" }
# sertakan image di dalam paket repo agar build-lab.ps1 menemukannya otomatis
if (-not $SkipImages) {
  New-Item -ItemType Directory -Force (Join-Path $repoOut 'distribusi\offline-images') | Out-Null
  Copy-Item $Tar (Join-Path $repoOut 'distribusi\offline-images\iam-images.tar') -Force
}
# installer VirtualBox/Docker/VC++ + cloud image
$instOut = Join-Path $repoOut 'distribusi\installer'
New-Item -ItemType Directory -Force $instOut | Out-Null
Copy-Item (Join-Path $Cache '*') $instOut -Recurse -Force -ErrorAction SilentlyContinue
Ok "repo + aset tersalin"

# 4. INSTALL.txt + checksum
Step 'Tulis INSTALL.txt & checksum'
$install = @'
==========================================================
  PAKET BUILD LAB IAM — Petunjuk untuk Panitia
==========================================================
Prasyarat PC peserta: Windows 10/11 Pro, RAM 16 GB, disk kosong >= 80 GB,
virtualisasi (VT-x/AMD-V) AKTIF di BIOS/UEFI. Hak Administrator.

LANGKAH:
  1. Salin folder "Pelatihan_IAM" ini ke PC peserta (mis. C:\Lab\Pelatihan_IAM).
  2. Buka PowerShell sebagai ADMINISTRATOR, lalu:
         cd C:\Lab\Pelatihan_IAM
         Set-ExecutionPolicy -Scope Process Bypass -Force
         .\build-lab.ps1
  3. Bila skrip minta REBOOT (pemasangan WSL2/Docker Desktop), reboot lalu jalankan lagi:
         .\build-lab.ps1
  4. Tunggu hingga "Lab siap". Cek: .\build-lab.ps1 -Phase Status

Seluruh image & installer sudah disertakan (offline). Internet TIDAK diperlukan,
kecuali build pertama VM mengunduh paket Ubuntu bila cache APT tidak disertakan.

Isi penting:
  build-lab.ps1                         -> pembangun lab (jalankan ini)
  distribusi/offline-images/iam-images.tar -> semua image Docker (dimuat otomatis)
  distribusi/installer/                 -> VirtualBox, Docker Desktop, VC++, Ubuntu cloud image
  sesi-0-pengantar/ .. sesi-4-...       -> modul pelatihan

Akun lab (sintetis): Administrator domain / Passw0rd#Lab2026 ; labadmin / Lab#Admin2026
Masalah & log: .lab\logs\build-*.log  (lihat baris "BERHENTI:")
==========================================================
'@
Set-Content (Join-Path $Out 'INSTALL.txt') $install -Encoding UTF8
# checksum ringkas aset berat
Get-ChildItem $repoOut\distribusi -Recurse -File -Include *.tar,*.ova,*.exe -ErrorAction SilentlyContinue |
  ForEach-Object { "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash, $_.Name } |
  Set-Content (Join-Path $Out 'SHA256SUMS.txt') -Encoding ASCII
Ok 'INSTALL.txt + SHA256SUMS.txt'

if ($Zip) {
  Step 'Buat arsip .zip'
  $zip = "$Out.zip"; if (Test-Path $zip) { Remove-Item $zip }
  Compress-Archive -Path (Join-Path $Out '*') -DestinationPath $zip
  Ok $zip
}
$size = [math]::Round(((Get-ChildItem $Out -Recurse -File | Measure-Object Length -Sum).Sum)/1GB, 2)
Write-Host "`nSelesai. Paket build: $Out  (~$size GB)" -ForegroundColor Green
Write-Host "Serahkan folder ini (atau .zip) ke panitia. Di PC peserta: baca INSTALL.txt."
