<#
.SYNOPSIS
  Update lab IAM yang SUDAH terbangun ke versi perbaikan - TANPA menghapus data/VM.

.DESCRIPTION
  Dipakai di PC peserta/fasilitator yang labnya sudah jalan, untuk menerapkan perbaikan modul dan
  infra tanpa Destroy/rebuild. Langkah:
    1. Verifikasi SHA256 iam-images.tar (cocok SHA256SUMS.txt = image versi perbaikan) lalu muat.
    2. docker compose up -d -> hanya container dgn image/konfig berubah yang dibuat ulang; VOLUME
       (data Samba/Keycloak/OpenBao/dll.) dan VM VirtualBox TIDAK disentuh.
    3. Pastikan sertifikat LDAPS Samba ber-SAN (perbaikan OpenBao Sesi 3).
    4. git pull modul (dokumen + screenshot Sesi) bila folder Pelatihan_IAM ada.
    5. VALIDASI hasil update (hash image, health container, LDAPS SAN, commit modul) +
       tulis LAPORAN yang bisa dikirim ke fasilitator.

  Seluruh proses direkam ke:
    .lab\logs\update-<stamp>.log          (transcript lengkap)
    .lab\logs\update-report-<stamp>.txt   (laporan ringkas utk dikirim/dicek)

  Jalankan di PowerShell Administrator dari folder builder (atau subfolder modul):
    Set-ExecutionPolicy -Scope Process Bypass -Force
    .\update-lab.ps1
  Opsi: -SkipImages  -SkipGit  -ClearWarpgateBlocks  -ExpectedTarSha <SHA256>
#>
[CmdletBinding()]
param([switch]$SkipImages, [switch]$SkipGit, [switch]$ClearWarpgateBlocks, [string]$ExpectedTarSha)
$ErrorActionPreference = 'Stop'
function Step($m){ Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "  [OK] $m" -ForegroundColor Green }
function Warn($m){ Write-Host "  [!]  $m" -ForegroundColor Yellow }
function Fail($m){ Write-Host "  [X]  $m" -ForegroundColor Red; throw $m }
function Invoke-Native($exe,$argList){
  # 2>&1 menggabung stderr native sbg ErrorRecord; render tiap baris sbg TEKS biasa (Write-Host)
  # agar progres docker (mis. "Container ... Running", ditulis ke stderr) tidak tampil sbg blok
  # merah NativeCommandError yang menakutkan. ErrorActionPreference='Continue' cegah terminasi.
  $old=$ErrorActionPreference; $ErrorActionPreference='Continue'
  try { & $exe @argList 2>&1 | ForEach-Object { Write-Host "$_" } } finally { $ErrorActionPreference=$old }
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
# Ambil output native sbg array baris, tahan stderr (tak melempar).
function Get-NativeOut($exe,$argList){
  $old=$ErrorActionPreference; $ErrorActionPreference='Continue'
  try { $out = & $exe @argList 2>$null } finally { $ErrorActionPreference=$old }
  return $out
}
function Get-DockerVolumeName($docker,$pattern){
  $old=$ErrorActionPreference; $ErrorActionPreference='Continue'
  try { $m = & $docker volume ls --format '{{.Name}}' 2>&1 | Select-String -Pattern $pattern | Select-Object -First 1 }
  finally { $ErrorActionPreference=$old }
  if($m){ return $m.ToString().Trim() } else { return $null }
}
function Get-Sha256($path){ if(Test-Path $path){ return (Get-FileHash -Algorithm SHA256 -Path $path).Hash.ToUpperInvariant() } return $null }

# --- akumulasi hasil validasi & laporan ---
$script:Issues = @()
$script:Report = @()
$script:TarSha = $null; $script:TarExp = $null; $script:HashVerdict = '-'
function Rep($line){ $script:Report += ,$line }

$Root=$PSScriptRoot
# Skrip ini butuh folder BUILDER (ada deploy/). Bila dijalankan dari subfolder modul
# (IAMLAB-BuildBag\Pelatihan_IAM, hasil git pull), naik satu level ke builder.
if(-not (Test-Path (Join-Path $Root 'deploy')) -and (Test-Path (Join-Path (Split-Path $Root -Parent) 'deploy'))){
  $Root=Split-Path $Root -Parent
}
$Deploy=Join-Path $Root 'deploy'
$Tar=Join-Path $Root 'distribusi\offline-images\iam-images.tar'
$Sums=Join-Path $Root 'SHA256SUMS.txt'
$docker=(Get-Command docker.exe -ErrorAction SilentlyContinue).Source
if(-not $docker){ Fail 'docker.exe tak ada - pastikan Docker Desktop terpasang dan berjalan.' }
if(-not (Test-NativeOk $docker @('info'))){ Fail 'Docker Desktop tidak berjalan.' }

# --- logging: transcript + laporan ---
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogDir = Join-Path $Root '.lab\logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir "update-$Stamp.log"
$ReportFile = Join-Path $LogDir "update-report-$Stamp.txt"
$transcribing = $false
try { Start-Transcript -Path $LogFile -Force | Out-Null; $transcribing = $true } catch { Warn "transcript tak aktif: $($_.Exception.Message)" }

try {
  Write-Host "Update Lab IAM (tanpa hapus data/VM)" -ForegroundColor White
  Write-Host "  Log transcript : $LogFile" -ForegroundColor Gray

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
        & $docker run -i --rm -v "${vol}:/data" alpine sh -c 'apk add -q sqlite >/dev/null 2>&1; sqlite3 /data/db/db.sqlite3' 2>&1 | ForEach-Object { Write-Host "$_" }
      $ErrorActionPreference=$old
      Push-Location $Deploy; try { Invoke-Native $docker @('compose','start','warpgate') | Out-Null } finally { Pop-Location }
      Ok 'blokir IP & percobaan gagal Warpgate dikosongkan; warpgate di-restart'
    }
    Write-Host '  (Selesai -ClearWarpgateBlocks)' -ForegroundColor Gray
    return
  }

  if(-not $SkipImages){
    Step '1. Verifikasi hash & muat image Docker (iam-images.tar)'
    if(Test-Path $Tar){
      $script:TarSha = Get-Sha256 $Tar
      Write-Host "    SHA256 iam-images.tar: $($script:TarSha)"
      if($ExpectedTarSha){ $script:TarExp = $ExpectedTarSha.ToUpperInvariant() }
      elseif(Test-Path $Sums){
        $l = Get-Content $Sums | Where-Object { $_ -match 'offline-images/iam-images\.tar' } | Select-Object -First 1
        if($l){ $script:TarExp = (($l -split '\s+')[0]).ToUpperInvariant() }
      }
      if($script:TarExp){
        Write-Host "    SHA256 diharapkan   : $($script:TarExp)"
        if($script:TarSha -eq $script:TarExp){ Ok 'hash image COCOK dengan SHA256SUMS.txt (image = versi perbaikan)'; $script:HashVerdict='COCOK' }
        else { Warn "hash image TIDAK COCOK - image mungkin BUKAN versi perbaikan terbaru"; $script:HashVerdict='TIDAK COCOK'; $script:Issues += 'hash image tidak cocok dengan SHA256SUMS.txt' }
      } else { Warn 'SHA256SUMS.txt / -ExpectedTarSha tak ada - verifikasi hash dilewati'; $script:HashVerdict='DILEWATI (tak ada acuan)' }
      Invoke-Native $docker @('load','-i',$Tar) | Out-Null; Ok 'image dimuat'
    } else { Warn "iam-images.tar tak ada di $Tar - lewati"; $script:Issues += 'iam-images.tar tak ada'; $script:HashVerdict='TAR TAK ADA' }
  } else { Ok 'lewati muat image (-SkipImages)'; $script:HashVerdict='DILEWATI (-SkipImages)' }

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

  # ======================= 5. VALIDASI HASIL UPDATE =======================
  Step '5. Validasi hasil update (+ tulis laporan)'
  Rep "===== LAPORAN UPDATE LAB IAM ====="
  Rep ("Waktu         : " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
  Rep ("Host / User   : $env:COMPUTERNAME / $env:USERNAME")
  try { Rep ("OS            : " + (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption) } catch {}
  Rep ("Builder root  : $Root")
  Rep ""
  # 5a. hash image
  if($script:TarSha){ Rep ("SHA256 image  : " + $script:TarSha) } else { Rep "SHA256 image  : <tar tak ada / dilewati>" }
  if($script:TarExp){ Rep ("SHA256 acuan  : " + $script:TarExp) }
  Rep ("Verifikasi hash: " + $script:HashVerdict)
  # 5b. daftar image termuat (fingerprint tambahan)
  $imgs = Get-NativeOut $docker @('images','--format','{{.Repository}}:{{.Tag}}  {{.ID}}')
  $imgs = $imgs | Where-Object { $_ -match '(?i)iamlab|keycloak|openbao|warpgate|samba|alloy|loki|grafana|mailpit|caddy|komentar|saml|locust|attacker|postgres|impacket' }
  Rep ""; Rep "Image lab termuat (Repository:Tag  ID):"
  if($imgs){ $imgs | ForEach-Object { Rep ("  " + $_) } } else { Rep "  <tak ada / gagal baca>" }
  # 5c. status container
  Push-Location $Deploy; try { $psText = Get-NativeOut $docker @('compose','ps') } finally { Pop-Location }
  Rep ""; Rep "docker compose ps:"
  if($psText){ $psText | ForEach-Object { Rep ("  " + $_) } } else { Rep "  <gagal baca>" }
  $bad = @(); if($psText){ $bad = $psText | Where-Object { $_ -match '(?i)\b(exited|restarting|unhealthy|dead|created|paused)\b' } }
  if($bad.Count -gt 0){ $script:Issues += "ada container tidak sehat ($($bad.Count))"; Warn "ada container tidak sehat (lihat laporan)" } else { Ok 'semua container tampak running/healthy' }
  # 5d. LDAPS SAN
  $sanOk = $false
  if($sambaVol){
    $san = Get-NativeOut $docker @('run','--rm','-v',"${sambaVol}:/d",'alpine','sh','-c','apk add -q openssl >/dev/null 2>&1; openssl x509 -in /d/private/tls/cert.pem -noout -ext subjectAltName 2>/dev/null')
    if(($san -join ' ') -match 'dc1\.iamlab\.test'){ $sanOk = $true }
  }
  if($sanOk){ Ok 'LDAPS cert ber-SAN (DNS:dc1.iamlab.test) - OK'; Rep ""; Rep 'LDAPS SAN     : OK (DNS:dc1.iamlab.test)' }
  else { Warn 'LDAPS cert ber-SAN TIDAK terdeteksi'; Rep ""; Rep 'LDAPS SAN     : TIDAK TERDETEKSI'; $script:Issues += 'LDAPS SAN tidak terdeteksi' }
  # 5e. commit modul
  $modul = Join-Path $Root 'Pelatihan_IAM'
  if(Test-Path (Join-Path $modul '.git')){
    $git=(Get-Command git.exe -ErrorAction SilentlyContinue).Source
    if($git){ $c = (Get-NativeOut $git @('-C',$modul,'rev-parse','--short','HEAD')) -join ''; Rep ("Modul commit  : " + $c) }
  }
  # verdict
  Rep ""
  if($script:Issues.Count -eq 0){ Rep 'HASIL         : PASS - semua validasi lolos'; Ok 'VALIDASI: PASS' }
  else { Rep ('HASIL         : PERLU DICEK -> ' + ($script:Issues -join '; ')); Warn ('VALIDASI: PERLU DICEK -> ' + ($script:Issues -join '; ')) }
  Rep "================================="
  # tulis laporan
  try { $script:Report | Set-Content -Path $ReportFile -Encoding UTF8; Ok "Laporan ditulis: $ReportFile" }
  catch { Warn "gagal menulis laporan: $($_.Exception.Message)" }

  Step 'Selesai'
  Write-Host '  Data (volume) dan VM tetap utuh. Cek juga: .\build-lab.ps1 -Phase Status' -ForegroundColor Gray
}
finally {
  if($transcribing){ try { Stop-Transcript | Out-Null } catch {} }
  Write-Host ""
  Write-Host "  >> Kirim berkas ini ke fasilitator untuk dicek:" -ForegroundColor Cyan
  Write-Host "     Laporan ringkas : $ReportFile" -ForegroundColor White
  Write-Host "     Log lengkap     : $LogFile" -ForegroundColor White
}
