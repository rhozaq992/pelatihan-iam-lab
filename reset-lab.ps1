<#
.SYNOPSIS
  Reset total Lab IAM: hapus deployment lalu bangun ulang dari awal.

.DESCRIPTION
  Dihapus : VM lab (srv1, client1), container + VOLUME DATA Docker (user AD Samba, realm
            Keycloak, OpenBao, Warpgate, log Loki, Grafana), state Caddy (CA HTTPS),
            CA AD hasil ekspor (deploy\certs\*.pem|*.cer), entri hosts & firewall lab.
  Dipertahankan : image Docker, cache unduhan (.lab\cache), adapter Host-Only, deploy\.env.
  Lalu fase Build build-lab.ps1 dijalankan ulang + validasi service running & port terjangkau di 10.10.10.5.

  PowerShell sebagai Administrator, dari IAMLAB-BuildBag atau IAMLAB-BuildBag\Pelatihan_IAM:
    Set-ExecutionPolicy -Scope Process Bypass -Force
    .\reset-lab.ps1                # tanya konfirmasi
    .\reset-lab.ps1 -Yes           # tanpa tanya
    .\reset-lab.ps1 -Yes -AutoJoin # VM langsung join domain (jalan pintas instruktur)

  Sesudah reset: peserta mulai lagi dari Sesi 1 (ekspor ulang ad-ca.pem, init/unseal OpenBao,
  setup Warpgate). Bila CA Caddy sempat diimpor ke browser/Windows, impor ulang yang baru.
#>
[CmdletBinding()]
param([switch]$Yes, [switch]$AutoJoin, [switch]$Gui)
$ErrorActionPreference = 'Stop'

if (-not $Yes) {
  Write-Host 'RESET TOTAL: VM, container, VOLUME DATA & sertifikat lab DIHAPUS lalu dibangun ulang.' -ForegroundColor Yellow
  if ((Read-Host 'Lanjut? ketik YA') -ne 'YA') { Write-Host 'dibatalkan'; exit 0 }
}

# Muat fungsi & konfigurasi build-lab.ps1 tanpa menjalankan fase (dot-source). Dijalankan dari
# folder builder ATAU dari folder modul (IAMLAB-BuildBag\Pelatihan_IAM) -> naik satu level.
$bl = Join-Path $PSScriptRoot 'build-lab.ps1'
if (-not (Test-Path $bl)) { $bl = Join-Path (Split-Path $PSScriptRoot -Parent) 'build-lab.ps1' }
if (-not (Test-Path $bl)) { Write-Host 'build-lab.ps1 tak ditemukan (jalankan dari IAMLAB-BuildBag atau IAMLAB-BuildBag\Pelatihan_IAM)' -ForegroundColor Red; exit 1 }
. $bl -Purge -Yes -Rebuild -AutoJoin:$AutoJoin -Gui:$Gui

New-Item -ItemType Directory -Force $Logs | Out-Null
$log = Join-Path $Logs ("reset-{0}.log" -f (Get-Date -Format yyyyMMdd-HHmmss))
Start-Transcript -Path $log -Append | Out-Null
try {
  Write-Host 'Reset Lab IAM (hapus + bangun ulang dari awal)' -ForegroundColor White
  if (-not (Test-Admin)) { Fail 'Jalankan PowerShell sebagai Administrator.' }

  # 0. Pra-cek: Docker Engine "ip": "127.0.0.1" membuat SEMUA port hanya di localhost -> VM tak
  #    bisa menjangkau 10.10.10.5 (join domain, LDAPS Sesi 1 5.3, bastion). Gagal SEBELUM menghapus.
  $dj = Join-Path $env:USERPROFILE '.docker\daemon.json'
  if ((Test-Path $dj) -and ((Get-Content $dj -Raw) -match '"ip"\s*:\s*"127\.0\.0\.1"')) {
    Fail "Docker Engine memublikasikan port hanya di 127.0.0.1 ($dj). Docker Desktop -> Settings -> Docker Engine: hapus baris `"ip`": `"127.0.0.1`", Apply & restart, lalu jalankan lagi."
  }

  # 1. Hapus. Docker dinyalakan dulu: Invoke-Destroy melewati 'down -v' bila Docker mati.
  Start-DockerDesktop
  Invoke-Destroy
  $proj = (Invoke-Compose @('config','--format','json') | Out-String | ConvertFrom-Json).name
  Invoke-Compose @('--profile','*','down','-v','--remove-orphans') -AllowFail | Out-Null
  # volume sisa compose versi lama (tak lagi dideklarasikan -> tak tersentuh 'down -v'); hanya milik proyek ini
  $d = Get-DockerCli
  $left = @(Invoke-Exe $d @('volume','ls','-q','--filter',"label=com.docker.compose.project=$proj") -Quiet -AllowFail | Where-Object { $_ })
  if ($left.Count) { Invoke-Exe $d (@('volume','rm','-f') + $left) -AllowFail | Out-Null; Ok "volume sisa dihapus: $($left -join ', ')" }

  Step 'Hapus state lokal di luar volume'
  foreach ($p in 'caddy\data','caddy\config') {
    $x = Join-Path $Deploy $p
    if (Test-Path $x) { Remove-Item $x -Recurse -Force; Ok "deploy\$p dihapus (CA HTTPS dibuat baru)" }
  }
  Get-ChildItem (Join-Path $Deploy 'certs\*') -Include *.pem,*.cer -File -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item $_.FullName -Force; Ok "deploy\certs\$($_.Name) dihapus (ekspor ulang di Sesi 1)" }

  # 2. Bangun ulang (sama dengan: .\build-lab.ps1 -Phase Build -Rebuild)
  Invoke-Requirements
  Invoke-Download
  Invoke-Build

  # 3. Validasi: setiap service default compose harus RUNNING (bukan sekadar tercantum di 'ps').
  Step 'Validasi service'
  $want = @(Invoke-Compose @('config','--services') | Where-Object { $_ })
  Start-Sleep 20   # beri waktu service yang crash-loop untuk terlihat berhenti
  $run = @(Invoke-Compose @('ps','--status','running','--services') | Where-Object { $_ })
  $miss = @($want | Where-Object { $_ -notin $run })
  if ($miss.Count) {
    foreach ($s in $miss) {
      Warn "$s TIDAK running - 20 baris log terakhir:"
      Invoke-Compose @('logs','--tail','20',$s) -AllowFail | ForEach-Object { Info $_ }
    }
    Fail "service tidak running: $($miss -join ', ')"
  }
  Ok "semua service running: $($want -join ', ')"

  # 4. Port lab harus terjangkau di IP lab (bukan cuma 127.0.0.1) - jalur VM -> host.
  Step "Validasi port di $($Cfg.HostIP)"
  $closed = @(foreach ($p in 88, 389, 636, 443, 2222) {
    if (-not (Test-NetConnection $Cfg.HostIP -Port $p -WarningAction SilentlyContinue).TcpTestSucceeded) { $p } })
  if ($closed.Count) {
    Invoke-Compose @('port','samba-dc','636') -AllowFail | ForEach-Object { Info "samba-dc 636 dipublikasikan di: $_" }
    Fail ("port tertutup di $($Cfg.HostIP): $($closed -join ', '). Bila tertulis 127.0.0.1 di atas: Docker Desktop -> Settings -> " +
          'Docker Engine (hapus "ip": "127.0.0.1") atau Resources -> Network, Apply & restart, lalu: docker compose up -d --force-recreate')
  }
  Ok "port 88/389/636/443/2222 terjangkau di $($Cfg.HostIP)"
  Ok "RESET SELESAI - log: $log"
} catch {
  Write-Host "`nBERHENTI: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "Log lengkap: $log"
  exit 1
} finally {
  Stop-Transcript | Out-Null
}
