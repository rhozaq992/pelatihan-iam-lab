<#
.SYNOPSIS
  Bangun Lab IAM di PC Windows: Docker Desktop (layanan IAM + Samba AD) + VirtualBox (VM Ubuntu).

.DESCRIPTION
  Fase (default All = Check -> Requirements -> Download -> Install -> Build):
    Check         cek sistem: edisi Windows, RAM, disk, virtualisasi, WSL2
    Requirements  cek kebutuhan: VirtualBox/VBoxManage, VC++ runtime, Docker Desktop, jaringan lab
    Download      unduh yang belum ada: VirtualBox, VC++ runtime, Docker Desktop, Ubuntu 24.04 cloud image
    Install       pasang yang belum ada (silent); bisa meminta REBOOT sekali (WSL2) -> jalankan ulang
    Build         jaringan Host-Only + firewall + hosts -> stack Docker -> VM srv1 & client1
    Start         nyalakan lab yang sudah dibangun (Docker stack + VM)
    Status        tampilkan kondisi lab
    Destroy       hapus VM lab, stack Docker, entri hosts & firewall lab

  Jalankan di PowerShell **sebagai Administrator** dari folder repo:
    Set-ExecutionPolicy -Scope Process Bypass -Force
    .\build-lab.ps1                    # semua fase
    .\build-lab.ps1 -Phase Status
    .\build-lab.ps1 -Phase Build -AutoJoin   # jalan pintas instruktur: VM langsung join domain

  Build butuh internet SEKALI (unduh paket/image). Setelah itu lab berjalan terisolasi
  di jaringan Host-Only 10.10.10.0/24 (host = 10.10.10.5).
#>
[CmdletBinding()]
param(
  [ValidateSet('All','Check','Requirements','Download','Install','Build','Start','Status','Destroy')]
  [string]$Phase = 'All',
  [switch]$AutoJoin,     # srv1/client1 langsung join domain saat build (default: peserta join di Sesi 1)
  [switch]$Rebuild,      # hapus & bangun ulang VM yang sudah ada
  [switch]$Gui,          # tampilkan jendela VM (bukan headless) saat provisioning — untuk QA/demo
  [switch]$Purge,        # Destroy: ikut hapus volume data Docker
  [switch]$Yes           # jangan tanya konfirmasi
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ============================ KONFIGURASI LAB ============================
$Root   = $PSScriptRoot
$LabDir = Join-Path $Root '.lab'
$Cache  = Join-Path $LabDir 'cache'
$VmDir  = Join-Path $LabDir 'vms'
$Logs   = Join-Path $LabDir 'logs'
$Deploy = Join-Path $Root 'deploy'
$Tar    = Join-Path $env:SystemRoot 'System32\tar.exe'    # bsdtar bawaan Windows (bukan tar Git/MSYS)
$Curl   = Join-Path $env:SystemRoot 'System32\curl.exe'

$Cfg = [ordered]@{
  Domain       = 'iamlab.test'
  HostIP       = '10.10.10.5'      # adapter Host-Only di Windows = host Docker = dc1
  Subnet       = '10.10.10.0/24'
  DomainAdminPass = 'Passw0rd#Lab2026'
  LabAdmin     = 'labadmin'
  LabAdminPass = 'Lab#Admin2026'
  WslMemory    = '6GB'            # batas RAM Docker Desktop (WSL2)
  WslCpus      = 2
  MinRamGB     = 15               # 16 GB fisik terbaca +/-15.8 GB
  MinDiskGB    = 80
  UbuntuOva    = 'https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.ova'
  UbuntuSums   = 'https://cloud-images.ubuntu.com/releases/24.04/release/SHA256SUMS'
  VBoxBase     = 'https://download.virtualbox.org/virtualbox'
  VcRedist     = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
  DockerDesktop= 'https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe'
  TcpPorts     = @(80,443,2222,1025,3100,8089,88,389,464,636,3268,3269)
  UdpPorts     = @(88,389,464)
}
$VMs = @(
  [pscustomobject]@{ Name='iamlab-srv1';    Host='srv1';    IP='10.10.10.20'; Mac1='080027AA0020'; Mac2='080027AA0120'
              RamMB=1024; Cpus=1; DiskMB=12288; Role='server';  Vram=16;  Start='headless'; TimeoutMin=45 },
  [pscustomobject]@{ Name='iamlab-client1'; Host='client1'; IP='10.10.10.30'; Mac1='080027AA0030'; Mac2='080027AA0130'
              RamMB=3072; Cpus=2; DiskMB=25600; Role='desktop'; Vram=128; Start='gui';      TimeoutMin=90 }
)
$HostsNames = @(
  "$($Cfg.HostIP) dc1.iamlab.test kc.iamlab.test app.iamlab.test saml.iamlab.test grafana.iamlab.test bao.iamlab.test mail.iamlab.test pam.iamlab.test",
  '10.10.10.20 srv1.iamlab.test',
  '10.10.10.30 client1.iamlab.test'
)

# ============================ UTILITAS ============================
function Step($m)  { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)    { Write-Host "  [OK] $m" -ForegroundColor Green }
function Warn($m)  { Write-Host "  [!]  $m" -ForegroundColor Yellow }
function Fail($m)  { Write-Host "  [X]  $m" -ForegroundColor Red; throw $m }
function Info($m)  { Write-Host "       $m" }

function Test-Admin {
  $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Invoke-Quiet {
  # Jalankan program native, buang semua output, kembalikan exit code. Di Windows PowerShell 5.1
  # stderr yang dialihkan menjadi ErrorRecord -> fatal bila ErrorActionPreference=Stop; matikan lokal.
  param([string]$Exe, [string[]]$ArgList)
  $ErrorActionPreference = 'Continue'
  & $Exe @ArgList *> $null
  return $LASTEXITCODE
}
function Invoke-Exe {
  param([string]$Exe, [string[]]$ArgList, [switch]$Quiet, [switch]$AllowFail)
  $ErrorActionPreference = 'Continue'
  if ($Quiet) { $out = & $Exe @ArgList 2>$null } else { $out = & $Exe @ArgList }
  if (-not $AllowFail -and $LASTEXITCODE -ne 0) { Fail "$([IO.Path]::GetFileName($Exe)) $($ArgList -join ' ') (exit $LASTEXITCODE)" }
  return $out
}
function Get-File($Url, $Dest) {
  if (Test-Path $Dest) { Ok "sudah ada: $([IO.Path]::GetFileName($Dest))"; return }
  Info "unduh $Url"
  $tmp = "$Dest.part"
  & $Curl -L --fail --retry 3 -o $tmp $Url
  if ($LASTEXITCODE -ne 0) { Remove-Item $tmp -ErrorAction SilentlyContinue; Fail "gagal unduh $Url" }
  Move-Item $tmp $Dest -Force
  Ok "tersimpan: $Dest"
}
function Write-Utf8NoBom($Path, $Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
}

# --- lokasi alat ---
function Get-VBoxManage {
  $c = Get-Command VBoxManage.exe -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  $cands = @("$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe")
  $reg = Get-ItemProperty 'HKLM:\SOFTWARE\Oracle\VirtualBox' -ErrorAction SilentlyContinue
  if ($reg -and $reg.InstallDir) { $cands = @((Join-Path $reg.InstallDir 'VBoxManage.exe')) + $cands }
  foreach ($p in $cands) { if (Test-Path $p) { return $p } }
  return $null
}
function Get-DockerDesktopExe {
  foreach ($p in @("$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
                   "$env:LOCALAPPDATA\Programs\DockerDesktop\Docker Desktop.exe")) {
    if (Test-Path $p) { return $p }
  }
  return $null
}
function Get-DockerCli {
  $c = Get-Command docker.exe -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  $dd = Get-DockerDesktopExe
  if ($dd) { $p = Join-Path (Split-Path $dd) 'resources\bin\docker.exe'; if (Test-Path $p) { return $p } }
  return $null
}
function Test-VcRedist {
  $k = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' -ErrorAction SilentlyContinue
  return [bool]($k -and $k.Installed -eq 1)
}
function Test-Wsl {
  return ((Invoke-Quiet 'wsl.exe' @('--status')) -eq 0)
}
function Test-DockerUp {
  $d = Get-DockerCli; if (-not $d) { return $false }
  return ((Invoke-Quiet $d @('info')) -eq 0)
}

# ============================ FASE: CHECK ============================
function Invoke-Check {
  Step '1. Cek sistem'
  $os = Get-CimInstance Win32_OperatingSystem
  $cs = Get-CimInstance Win32_ComputerSystem
  if ($os.Caption -match 'Pro|Enterprise|Education') { Ok "$($os.Caption) (build $($os.BuildNumber))" }
  else { Warn "$($os.Caption): disarankan Windows Pro/Enterprise (WSL2 + VirtualBox)" }
  if ([int]$os.BuildNumber -lt 19045) { Warn 'Windows terlalu lama - perbarui ke Windows 10 22H2 / Windows 11.' }

  $ram = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
  if ($ram -ge $Cfg.MinRamGB) { Ok "RAM $ram GB" } else { Fail "RAM $ram GB - minimal 16 GB." }
  $used = ($VMs | Measure-Object -Property RamMB -Sum).Sum / 1024
  Info ("alokasi lab: VM {0} GB + Docker Desktop {1} = sisa untuk Windows +/-{2} GB" -f $used, $Cfg.WslMemory,
        [math]::Round($ram - $used - [double]($Cfg.WslMemory -replace 'GB',''), 1))

  $drive = (Get-Item $Root).PSDrive
  $free = [math]::Round($drive.Free / 1GB, 0)
  if ($free -ge $Cfg.MinDiskGB) { Ok "disk ${drive}: kosong $free GB" } else { Fail "disk ${drive}: kosong $free GB - butuh >= $($Cfg.MinDiskGB) GB." }

  $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
  if ($cs.HypervisorPresent -or $cpu.VirtualizationFirmwareEnabled) { Ok "virtualisasi CPU aktif ($($cpu.Name.Trim()))" }
  else { Fail 'Virtualisasi (VT-x/AMD-V) mati di BIOS/UEFI - aktifkan dulu.' }
  if ($cs.HypervisorPresent) { Warn 'Hyper-V/WSL2 aktif: VirtualBox berjalan di atas Hyper-V (sedikit lebih lambat) - normal untuk Docker Desktop.' }

  if (Test-Wsl) { Ok 'WSL2 tersedia' } else { Warn 'WSL2 belum terpasang - dipasang di fase Install (butuh reboot).' }
}

# ============================ FASE: REQUIREMENTS ============================
$script:Missing = @{}
function Invoke-Requirements {
  Step '2. Cek kebutuhan'
  $script:Missing = @{}
  $vb = Get-VBoxManage
  if ($vb) {
    $ver = (Invoke-Exe $vb @('--version') -Quiet) -replace 'r\d+$',''
    if ([version]($ver -replace '[^\d\.].*$','') -ge [version]'7.0') { Ok "VirtualBox $ver" }
    else { Warn "VirtualBox $ver terlalu lama (butuh 7.x)"; $script:Missing.VirtualBox = $true }
  } else { Warn 'VirtualBox belum terpasang'; $script:Missing.VirtualBox = $true }

  if (Test-VcRedist) { Ok 'Microsoft VC++ runtime (x64)' } else { Warn 'VC++ runtime belum ada (dibutuhkan VirtualBox 7.1+)'; $script:Missing.VcRedist = $true }
  if (-not (Test-Wsl)) { $script:Missing.Wsl = $true }

  if (Get-DockerDesktopExe) {
    if (Test-DockerUp) { Ok 'Docker Desktop terpasang & berjalan' } else { Ok 'Docker Desktop terpasang (belum berjalan - dinyalakan saat Build)' }
  } else { Warn 'Docker Desktop belum terpasang'; $script:Missing.Docker = $true }

  if (-not (Test-Path $Curl)) { Fail 'curl.exe tak ada di System32 (Windows 10 1803+ menyediakannya).' }
  if (-not (Test-Path $Tar))  { Fail 'tar.exe tak ada di System32 (Windows 10 1803+ menyediakannya).' }
  Ok 'curl.exe & tar.exe (System32) tersedia'

  if ($vb) {
    $if = Get-LabHostOnly
    if ($if) { Ok "jaringan lab Host-Only: '$if' ($($Cfg.HostIP))" } else { Info "jaringan lab Host-Only $($Cfg.HostIP)/24 akan dibuat saat Build" }
  }
  # port yang dipakai stack lab di host
  $busy = foreach ($p in $Cfg.TcpPorts) {
    Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue | ForEach-Object {
      $pn = (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName
      if ($pn -and $pn -notmatch 'com\.docker|wslrelay|vpnkit|docker') { "$p ($pn)" } }
  }
  if ($busy) { Warn "port lab dipakai aplikasi lain: $($busy -join ', ') - hentikan dulu (mis. layanan VMware/IIS)."; }
  else { Ok 'port lab bebas' }
}

# ============================ FASE: DOWNLOAD ============================
function Invoke-Download {
  Step '3. Unduh kebutuhan'
  New-Item -ItemType Directory -Force $Cache | Out-Null
  if ($script:Missing.VirtualBox) {
    $ver = ((Invoke-WebRequest -UseBasicParsing "$($Cfg.VBoxBase)/LATEST-STABLE.TXT").Content).Trim()
    $idx = (Invoke-WebRequest -UseBasicParsing "$($Cfg.VBoxBase)/$ver/").Content
    $m = [regex]::Match($idx, "VirtualBox-$([regex]::Escape($ver))-\d+-Win\.exe")
    if (-not $m.Success) { Fail "installer VirtualBox $ver tak ditemukan" }
    Get-File "$($Cfg.VBoxBase)/$ver/$($m.Value)" (Join-Path $Cache $m.Value)
  }
  if ($script:Missing.VcRedist -or $script:Missing.VirtualBox) { Get-File $Cfg.VcRedist (Join-Path $Cache 'vc_redist.x64.exe') }
  if ($script:Missing.Docker) { Get-File $Cfg.DockerDesktop (Join-Path $Cache 'DockerDesktopInstaller.exe') }

  $ova = Join-Path $Cache 'ubuntu-24.04-server-cloudimg-amd64.ova'
  $fresh = -not (Test-Path $ova)
  Get-File $Cfg.UbuntuOva $ova
  if ($fresh) {
    $sums = (Invoke-WebRequest -UseBasicParsing $Cfg.UbuntuSums).Content -split "`n"
    $want = ($sums | Where-Object { $_ -match 'server-cloudimg-amd64\.ova$' } | Select-Object -First 1) -split '\s+' | Select-Object -First 1
    $got = (Get-FileHash $ova -Algorithm SHA256).Hash.ToLower()
    if ($want -and $got -ne $want) { Remove-Item $ova; Fail 'checksum Ubuntu cloud image tidak cocok - unduh ulang.' }
    Ok 'checksum Ubuntu cloud image cocok'
  }
}

# ============================ FASE: INSTALL ============================
$script:NeedReboot = $false
function Invoke-Install {
  Step '4. Pasang kebutuhan'
  if ($script:Missing.VcRedist -or ($script:Missing.VirtualBox -and -not (Test-VcRedist))) {
    Info 'pasang VC++ runtime...'
    Start-Process (Join-Path $Cache 'vc_redist.x64.exe') -ArgumentList '/install','/quiet','/norestart' -Wait
    Ok 'VC++ runtime'
  }
  if ($script:Missing.VirtualBox) {
    $inst = Get-ChildItem $Cache -Filter 'VirtualBox-*-Win.exe' | Sort-Object Name | Select-Object -Last 1
    Info "pasang $($inst.Name) (silent)..."
    $p = Start-Process $inst.FullName -ArgumentList '--silent','--ignore-reboot' -Wait -PassThru
    if ($p.ExitCode -ne 0) { Fail "instalasi VirtualBox gagal (exit $($p.ExitCode))" }
    Ok 'VirtualBox terpasang'
  }
  if ($script:Missing.Wsl) {
    Info 'pasang WSL2 (tanpa distro)...'
    & wsl.exe --install --no-distribution
    $script:NeedReboot = $true
  }
  if ($script:Missing.Docker) {
    Info 'pasang Docker Desktop (silent, backend WSL2)...'
    $p = Start-Process (Join-Path $Cache 'DockerDesktopInstaller.exe') -ArgumentList 'install','--quiet','--accept-license','--backend=wsl-2','--always-run-service' -Wait -PassThru
    if ($p.ExitCode -ne 0) { Fail "instalasi Docker Desktop gagal (exit $($p.ExitCode))" }
    $u = "$env:USERDOMAIN\$env:USERNAME"
    try { Add-LocalGroupMember -Group 'docker-users' -Member $u -ErrorAction Stop; Ok "$u ditambahkan ke grup docker-users" } catch { }
    Ok 'Docker Desktop terpasang'
    $script:NeedReboot = $true
  }
  if (-not ($script:Missing.Keys.Count)) { Ok 'semua kebutuhan sudah terpasang' }
  if ($script:NeedReboot) {
    Warn 'REBOOT diperlukan (WSL2/Docker Desktop). Setelah reboot jalankan lagi: .\build-lab.ps1'
    exit 3010
  }
}

# ============================ FASE: BUILD ============================
function Get-LabHostOnly {
  $vb = Get-VBoxManage
  $cur = $null; $res = $null
  foreach ($l in (Invoke-Exe $vb @('list','hostonlyifs') -Quiet)) {
    if ($l -match '^Name:\s+(.+)$') { $cur = $Matches[1].Trim() }
    elseif ($l -match '^IPAddress:\s+(.+)$' -and $Matches[1].Trim() -eq $Cfg.HostIP) { $res = $cur }
  }
  return $res
}
function Initialize-Network {
  Step '5a. Jaringan lab (Host-Only, firewall, hosts)'
  $vb = Get-VBoxManage
  $if = Get-LabHostOnly
  if (-not $if) {
    # pakai ulang adapter yang sudah di subnet 10.10.10.x, bila ada; jika tidak buat baru
    $cur = $null
    foreach ($l in (Invoke-Exe $vb @('list','hostonlyifs') -Quiet)) {
      if ($l -match '^Name:\s+(.+)$') { $cur = $Matches[1].Trim() }
      elseif ($l -match '^IPAddress:\s+10\.10\.10\.\d+' -and -not $if) { $if = $cur }
    }
    if (-not $if) {
      $out = Invoke-Exe $vb @('hostonlyif','create')
      $m = [regex]::Match(($out -join "`n"), "Interface '(.+?)' was successfully created")
      if (-not $m.Success) { Fail 'gagal membuat adapter Host-Only' }
      $if = $m.Groups[1].Value
    }
    Invoke-Exe $vb @('hostonlyif','ipconfig',$if,'--ip',$Cfg.HostIP,'--netmask','255.255.255.0') | Out-Null
  }
  # DHCP VirtualBox dimatikan: semua IP lab statis
  Invoke-Quiet $vb @('dhcpserver','modify',"--interface=$if",'--disable') | Out-Null
  Ok "Host-Only '$if' = $($Cfg.HostIP)/24"
  $script:HostOnlyIf = $if

  $na = Get-NetAdapter | Where-Object InterfaceDescription -eq $if | Select-Object -First 1
  if ($na) {
    try { Set-NetConnectionProfile -InterfaceAlias $na.Name -NetworkCategory Private -ErrorAction Stop; Ok "profil jaringan '$($na.Name)' = Private" }
    catch { Warn "profil jaringan '$($na.Name)' tak bisa diubah (aturan firewall tetap berlaku utk semua profil)" }
  }
  Get-NetFirewallRule -Group 'IAMLAB' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  New-NetFirewallRule -DisplayName 'IAMLAB lab (TCP)' -Group 'IAMLAB' -Direction Inbound -Protocol TCP `
    -LocalPort $Cfg.TcpPorts -RemoteAddress $Cfg.Subnet -Action Allow -Profile Any | Out-Null
  New-NetFirewallRule -DisplayName 'IAMLAB lab (UDP)' -Group 'IAMLAB' -Direction Inbound -Protocol UDP `
    -LocalPort $Cfg.UdpPorts -RemoteAddress $Cfg.Subnet -Action Allow -Profile Any | Out-Null
  Ok "firewall: izinkan $($Cfg.Subnet) -> port lab"

  Set-HostsBlock -Lines $HostsNames
  Ok 'hosts Windows: *.iamlab.test -> 10.10.10.5, srv1, client1'

  # batas RAM Docker Desktop (WSL2)
  $wc = Join-Path $env:USERPROFILE '.wslconfig'
  $txt = ''; if (Test-Path $wc) { $txt = Get-Content $wc -Raw }
  $new = $txt
  if ($new -notmatch '(?m)^\[wsl2\]') { $new = $new.TrimEnd() + "`r`n[wsl2]`r`n" }
  foreach ($kv in @(@('memory',$Cfg.WslMemory), @('processors',$Cfg.WslCpus))) {
    if ($new -match "(?m)^$($kv[0])\s*=.*$") { $new = $new -replace "(?m)^$($kv[0])\s*=.*$", "$($kv[0])=$($kv[1])" }
    else { $new = $new -replace '(?m)^\[wsl2\]\s*$', "[wsl2]`r`n$($kv[0])=$($kv[1])" }
  }
  if ($new -ne $txt) {
    if (Test-Path $wc) { Copy-Item $wc "$wc.bak-iamlab" -Force }
    Set-Content $wc $new.Trim() -Encoding ASCII
    Ok ".wslconfig: memory=$($Cfg.WslMemory), processors=$($Cfg.WslCpus) (berlaku setelah WSL restart)"
    $script:WslChanged = $true
  } else { Ok '.wslconfig sudah sesuai' }
}
function Set-HostsBlock {
  param([string[]]$Lines)
  $hf = "$env:SystemRoot\System32\drivers\etc\hosts"
  $s = '# >>> lab-iam (build-lab.ps1)'; $e = '# <<< lab-iam'
  $old = Get-Content $hf -ErrorAction SilentlyContinue
  $keep = New-Object System.Collections.Generic.List[string]; $skip = $false
  foreach ($l in $old) { if ($l -eq $s) { $skip = $true; continue }; if ($l -eq $e) { $skip = $false; continue }; if (-not $skip) { $keep.Add($l) } }
  if ($Lines) { $keep.Add($s); $Lines | ForEach-Object { $keep.Add($_) }; $keep.Add($e) }
  Set-Content $hf $keep -Encoding ASCII
}

function Start-DockerDesktop {
  if (Test-DockerUp) { Ok 'Docker Desktop berjalan'; return }
  if ($script:WslChanged) { Invoke-Quiet 'wsl.exe' @('--shutdown') | Out-Null }
  $dd = Get-DockerDesktopExe; if (-not $dd) { Fail 'Docker Desktop tak ditemukan - jalankan fase Install.' }
  Info 'menyalakan Docker Desktop...'
  Start-Process $dd
  $t = 0
  while (-not (Test-DockerUp)) { Start-Sleep 5; $t += 5; if ($t -ge 300) { Fail 'Docker Desktop tak siap dalam 5 menit.' } }
  Ok 'Docker Desktop siap'
}
function Invoke-Compose {
  param([string[]]$ArgList, [switch]$AllowFail)
  $d = Get-DockerCli
  Push-Location $Deploy
  try { Invoke-Exe $d (@('compose') + $ArgList) -AllowFail:$AllowFail } finally { Pop-Location }
}
function Initialize-DockerStack {
  Step '5b. Stack Docker (layanan IAM + Samba AD dc1)'
  Start-DockerDesktop
  $env_ = Join-Path $Deploy '.env'
  if (-not (Test-Path $env_)) { Copy-Item (Join-Path $Deploy '.env.example') $env_; Ok 'deploy/.env dibuat dari .env.example' }
  (Get-Content $env_) -replace '^DC_IP=.*', "DC_IP=$($Cfg.HostIP)" | Set-Content $env_ -Encoding ASCII
  $tar = Join-Path $Root 'distribusi\offline-images\iam-images.tar'
  if (Test-Path $tar) {
    Info 'muat image offline (distribusi/offline-images/iam-images.tar)...'
    Invoke-Exe (Get-DockerCli) @('load','-i',$tar) | Select-Object -Last 3 | ForEach-Object { Info $_ }
    Invoke-Compose @('up','-d','--no-build') | Out-Null
  } else {
    Info 'unduh & bangun image (butuh internet, +/-10-20 menit pertama kali)...'
    Invoke-Compose @('--profile','*','pull','--ignore-buildable') | Out-Null
    Invoke-Compose @('--profile','*','build') | Out-Null
    Invoke-Compose @('up','-d') | Out-Null
  }
  Info 'menunggu Samba AD (dc1) siap...'
  $cid = (Invoke-Compose @('ps','-q','samba-dc') | Select-Object -First 1)
  $t = 0
  do {
    Start-Sleep 5; $t += 5
    $h = Invoke-Exe (Get-DockerCli) @('inspect','-f','{{.State.Health.Status}}',"$cid") -Quiet -AllowFail
    if ($t -ge 300) { Fail "samba-dc belum healthy ($h) - cek: docker compose logs samba-dc" }
  } while ($h -ne 'healthy')
  Ok 'samba-dc healthy (dc1.iamlab.test)'
  $tn = Test-NetConnection $Cfg.HostIP -Port 389 -WarningAction SilentlyContinue
  if ($tn.TcpTestSucceeded) { Ok "LDAP terjangkau di $($Cfg.HostIP):389 (jalur VM -> DC)" } else { Warn "LDAP $($Cfg.HostIP):389 belum terjangkau - cek Docker Desktop & firewall" }
}

# --- ISO seed cloud-init (IMAPI2FS bawaan Windows) ---
function New-IsoFile {
  param([string]$SourceDir, [string]$Path, [string]$Label)
  if (-not ('IamlabIso' -as [type])) {
    $src = @'
public class IamlabIso {
  public unsafe static void Create(string path, object stream, int blockSize, int totalBlocks) {
    int bytes = 0; byte[] buf = new byte[blockSize]; var ptr = (System.IntPtr)(&bytes);
    var o = System.IO.File.OpenWrite(path);
    var i = stream as System.Runtime.InteropServices.ComTypes.IStream;
    while (totalBlocks-- > 0) { i.Read(buf, blockSize, ptr); o.Write(buf, 0, bytes); }
    o.Flush(); o.Close();
  }
}
'@
    if ($PSVersionTable.PSEdition -eq 'Core') { Add-Type -TypeDefinition $src -CompilerOptions '/unsafe' }
    else {
      $cp = New-Object CodeDom.Compiler.CompilerParameters; $cp.CompilerOptions = '/unsafe'
      Add-Type -TypeDefinition $src -CompilerParameters $cp
    }
  }
  if (Test-Path $Path) { Remove-Item $Path -Force }
  $fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
  $fsi.FileSystemsToCreate = 3          # ISO9660 + Joliet (nama berkas huruf kecil terjaga)
  $fsi.VolumeName = $Label
  $fsi.Root.AddTree($SourceDir, $false)
  $r = $fsi.CreateResultImage()
  [IamlabIso]::Create($Path, $r.ImageStream, $r.BlockSize, $r.TotalBlocks)
}
function Format-Mac($m) { (($m.ToLower()) -split '(..)' | Where-Object { $_ }) -join ':' }

function Get-BaseDisk {
  # Hasilkan "golden" VDI SEKALI dari cloud image, lalu lepas dari media registry VirtualBox
  # (berkas tetap). Tiap VM menyalin golden ini + beri UUID baru -> idempoten, tanpa clonemedium
  # berulang yang menimbulkan bentrok UUID di registry saat build ulang.
  $vb = Get-VBoxManage
  $dir = Join-Path $Cache 'ubuntu-base'
  $golden = Join-Path $dir 'golden.vdi'
  if (Test-Path $golden) { return $golden }
  $ova = Join-Path $Cache 'ubuntu-24.04-server-cloudimg-amd64.ova'
  if (-not (Test-Path $ova)) { Fail 'cloud image belum diunduh - jalankan fase Download.' }
  New-Item -ItemType Directory -Force $dir | Out-Null
  $vmdk = Get-ChildItem $dir -Filter *.vmdk -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $vmdk) {
    & $Tar -xf $ova -C $dir
    $vmdk = Get-ChildItem $dir -Filter *.vmdk | Select-Object -First 1
    if (-not $vmdk) { Fail 'VMDK tak ditemukan di dalam OVA' }
  }
  Invoke-Exe $vb @('clonemedium','disk',$vmdk.FullName,$golden,'--format','VDI') | Out-Null
  # lepas vmdk & golden dari registry (berkas tetap) agar tak mengunci build berikutnya
  Invoke-Quiet $vb @('closemedium','disk',$vmdk.FullName) | Out-Null
  Invoke-Quiet $vb @('closemedium','disk',$golden) | Out-Null
  Ok "golden VDI dasar dibuat (sekali)"
  return $golden
}
function Get-VmState($name) {
  $vb = Get-VBoxManage
  $info = Invoke-Exe $vb @('showvminfo',$name,'--machinereadable') -Quiet -AllowFail
  if ($LASTEXITCODE -ne 0) { return $null }
  $l = $info | Where-Object { $_ -match '^VMState=' } | Select-Object -First 1
  return ($l -replace '^VMState="?','' -replace '"$','')
}
function New-LabVm($vm) {
  $vb = Get-VBoxManage
  $name = $vm.Name
  $state = Get-VmState $name
  if ($state) {
    if (-not $Rebuild) { Ok "$name sudah ada ($state) - lewati (pakai -Rebuild untuk bangun ulang)"; return }
    Remove-LabVm $name
  }
  Step "5c. VM $name ($($vm.Role), $($vm.IP), $($vm.RamMB) MB)"
  $dir = Join-Path $VmDir $name
  if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
  New-Item -ItemType Directory -Force $dir | Out-Null

  # disk: salin golden VDI (file) + UUID baru, lalu perbesar (cloud-init memperluas partisi).
  # Salin-file + sethduuid menghindari pendaftaran ganda sumber di media registry (idempoten).
  $vdi = Join-Path $dir "$name.vdi"
  Copy-Item (Get-BaseDisk) $vdi -Force
  Invoke-Exe $vb @('internalcommands','sethduuid',$vdi) | Out-Null
  Invoke-Exe $vb @('modifymedium','disk',$vdi,'--resize',"$($vm.DiskMB)") | Out-Null

  # seed cloud-init
  $seed = Join-Path $dir 'seed'; New-Item -ItemType Directory -Force $seed | Out-Null
  $vars = @{ HOSTNAME=$vm.Host; ROLE=$vm.Role; IP=$vm.IP; MAC1=(Format-Mac $vm.Mac1); MAC2=(Format-Mac $vm.Mac2)
             LABADMIN=$Cfg.LabAdmin; LABADMIN_PASS=$Cfg.LabAdminPass; ADMIN_PASS=$Cfg.DomainAdminPass
             AUTOJOIN=$(if ($AutoJoin) { '1' } else { '0' }) }
  foreach ($f in @(@('user-data.yaml','user-data'), @('network-config.yaml','network-config'))) {
    $t = Get-Content (Join-Path $Root "lab\cloud-init\$($f[0])") -Raw
    foreach ($k in $vars.Keys) { $t = $t.Replace("{{$k}}", [string]$vars[$k]) }
    Write-Utf8NoBom (Join-Path $seed $f[1]) $t
  }
  Write-Utf8NoBom (Join-Path $seed 'meta-data') "instance-id: $name-$(Get-Date -Format yyyyMMddHHmmss)`nlocal-hostname: $($vm.Host)`n"
  & $Tar -cf (Join-Path $seed 'payload.tar') -C $Root lab
  if ($LASTEXITCODE -ne 0) { Fail 'gagal membuat payload.tar' }
  $iso = Join-Path $dir 'seed.iso'
  New-IsoFile -SourceDir $seed -Path $iso -Label 'cidata'

  # VM
  $serial = Join-Path $Logs "$($vm.Host)-serial.log"
  if (Test-Path $serial) { Remove-Item $serial -Force }
  Invoke-Exe $vb @('createvm','--name',$name,'--ostype','Ubuntu_64','--basefolder',$VmDir,'--register') | Out-Null
  Invoke-Exe $vb @('modifyvm',$name,'--memory',"$($vm.RamMB)",'--cpus',"$($vm.Cpus)",'--vram',"$($vm.Vram)",
    '--graphicscontroller','vmsvga','--firmware','bios','--rtcuseutc','on','--ioapic','on','--mouse','usbtablet',
    '--nic1','hostonly','--hostonlyadapter1',$script:HostOnlyIf,'--macaddress1',$vm.Mac1,
    '--nic2','nat','--macaddress2',$vm.Mac2,
    '--uart1','0x3F8','4','--uartmode1','file',$serial,
    '--boot1','disk','--boot2','dvd','--boot3','none','--boot4','none') | Out-Null
  Invoke-Exe $vb @('storagectl',$name,'--name','SATA','--add','sata','--controller','IntelAhci','--portcount','2') | Out-Null
  Invoke-Exe $vb @('storageattach',$name,'--storagectl','SATA','--port','0','--device','0','--type','hdd','--medium',$vdi) | Out-Null
  Invoke-Exe $vb @('storageattach',$name,'--storagectl','SATA','--port','1','--device','0','--type','dvddrive','--medium',$iso) | Out-Null

  # provisioning (NAT aktif) -> VM mati sendiri bila selesai
  $provType = if ($Gui) { 'gui' } else { 'headless' }
  Invoke-Exe $vb @('startvm',$name,'--type',$provType) | Out-Null
  Info "provisioning berjalan (maks $($vm.TimeoutMin) menit; log: $serial)..."
  $deadline = (Get-Date).AddMinutes($vm.TimeoutMin); $seen = 0; $result = $null
  while ((Get-Date) -lt $deadline) {
    Start-Sleep 10
    if (Test-Path $serial) {
      $lines = @(Get-Content $serial -ErrorAction SilentlyContinue)
      for ($i = $seen; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '\[provision\]') { Info ($lines[$i] -replace '^.*\[provision\]','') } }
      $seen = $lines.Count
      if ($lines -match 'IAMLAB_PROVISION_FAIL') { $result = 'FAIL' }
      elseif ($lines -match 'IAMLAB_PROVISION_DONE') { $result = 'DONE' }
    }
    if ($result -and (Get-VmState $name) -eq 'poweroff') { break }
  }
  if (-not $result) { Fail "${name}: provisioning melewati batas waktu - lihat $serial" }
  if ($result -eq 'FAIL') { Fail "${name}: provisioning GAGAL - lihat $serial (dan /var/log/iamlab-provision.log di VM)" }
  if ((Get-VmState $name) -ne 'poweroff') { Invoke-Quiet $vb @('controlvm',$name,'acpipowerbutton') | Out-Null; Start-Sleep 20 }

  # isolasi: lepas NAT & seed
  Invoke-Exe $vb @('modifyvm',$name,'--nic2','none') | Out-Null
  Invoke-Exe $vb @('storageattach',$name,'--storagectl','SATA','--port','1','--device','0','--type','dvddrive','--medium','emptydrive') | Out-Null
  Ok "$name siap (NAT dilepas - hanya Host-Only)"
}
function Remove-LabVm($name) {
  $vb = Get-VBoxManage
  if ((Get-VmState $name) -in @('running','paused')) { Invoke-Quiet $vb @('controlvm',$name,'poweroff') | Out-Null; Start-Sleep 3 }
  Invoke-Quiet $vb @('unregistervm',$name,'--delete') | Out-Null
  $d = Join-Path $VmDir $name; if (Test-Path $d) { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
  Ok "$name dihapus"
}
function Start-LabVms {
  $vb = Get-VBoxManage
  foreach ($vm in $VMs) {
    $st = Get-VmState $vm.Name
    if (-not $st) { Warn "$($vm.Name) belum dibangun"; continue }
    if ($st -eq 'running') { Ok "$($vm.Name) sudah berjalan"; continue }
    Invoke-Exe $vb @('startvm',$vm.Name,'--type',$vm.Start) | Out-Null
    Ok "$($vm.Name) dinyalakan ($($vm.Start))"
  }
}
function Invoke-Build {
  New-Item -ItemType Directory -Force $VmDir, $Logs | Out-Null
  if (-not (Get-VBoxManage)) { Fail 'VirtualBox belum terpasang - jalankan fase Install.' }
  Initialize-Network
  Initialize-DockerStack
  foreach ($vm in $VMs) { New-LabVm $vm }
  Step '5d. Nyalakan VM'
  Start-LabVms
  Show-Summary
}

# ============================ START / STATUS / DESTROY ============================
function Invoke-Start {
  Step 'Nyalakan lab'
  $script:HostOnlyIf = Get-LabHostOnly
  if (-not $script:HostOnlyIf) { Fail 'jaringan lab belum ada - jalankan fase Build.' }
  Start-DockerDesktop
  Invoke-Compose @('up','-d') | Out-Null
  Ok 'stack Docker menyala'
  Start-LabVms
  Show-Summary
}
function Invoke-Status {
  Step 'Status lab'
  $vb = Get-VBoxManage
  if ($vb) {
    $if = Get-LabHostOnly
    if ($if) { Ok "Host-Only '$if' = $($Cfg.HostIP)" } else { Warn 'jaringan lab belum dibuat' }
    foreach ($vm in $VMs) {
      $st = Get-VmState $vm.Name
      if (-not $st) { Warn "$($vm.Name): belum dibangun"; continue }
      $ping = Test-Connection $vm.IP -Count 1 -Quiet -ErrorAction SilentlyContinue
      Info ("{0,-16} {1,-10} {2,-12} ping={3}" -f $vm.Name, $st, $vm.IP, $ping)
    }
  } else { Warn 'VirtualBox belum terpasang' }
  if (Test-DockerUp) { Invoke-Compose @('ps','--format','table {{.Service}}\t{{.Status}}') -AllowFail | ForEach-Object { Info $_ } }
  else { Warn 'Docker Desktop tidak berjalan'; return }
  foreach ($p in 389, 636, 443, 3100) {
    $ok = (Test-NetConnection $Cfg.HostIP -Port $p -WarningAction SilentlyContinue).TcpTestSucceeded
    Info ("port {0,-5} di {1}: {2}" -f $p, $Cfg.HostIP, $(if ($ok) { 'terbuka' } else { 'tertutup' }))
  }
}
function Invoke-Destroy {
  Step 'Hapus lab'
  if (-not $Yes) {
    $a = Read-Host 'Hapus VM lab, stack Docker, entri hosts & firewall lab? ketik YA'
    if ($a -ne 'YA') { Warn 'dibatalkan'; return }
  }
  if (Get-VBoxManage) { foreach ($vm in $VMs) { if (Get-VmState $vm.Name) { Remove-LabVm $vm.Name } } }
  if (Test-DockerUp) {
    $a = @('--profile','*','down'); if ($Purge) { $a += '-v' }
    Invoke-Compose $a -AllowFail | Out-Null; Ok "stack Docker dihentikan$(if ($Purge) { ' + volume dihapus' })"
  }
  Set-HostsBlock -Lines @(); Ok 'entri hosts lab dihapus'
  Get-NetFirewallRule -Group 'IAMLAB' -ErrorAction SilentlyContinue | Remove-NetFirewallRule; Ok 'aturan firewall lab dihapus'
  Info 'Adapter Host-Only & cache unduhan (.lab\cache) dibiarkan untuk build berikutnya.'
}
function Show-Summary {
  Step 'Lab siap'
  Info 'Browser Windows : https://kc.iamlab.test | https://grafana.iamlab.test | https://pam.iamlab.test | https://mail.iamlab.test'
  Info "VM            : srv1 10.10.10.20 (ssh $($Cfg.LabAdmin)@srv1.iamlab.test) | client1 10.10.10.30 (jendela VirtualBox, GUI)"
  Info "Akun lokal VM : $($Cfg.LabAdmin) / $($Cfg.LabAdminPass)   |   Domain: Administrator / $($Cfg.DomainAdminPass)"
  if ($AutoJoin) { Info 'VM sudah join domain (-AutoJoin).' } else { Info 'Berikutnya: Sesi 1 -> tata direktori, lalu "sudo join-domain.sh" di srv1 & client1.' }
}

# ============================ MAIN ============================
# Dot-source (. .\build-lab.ps1) hanya memuat fungsi tanpa menjalankan fase — berguna untuk QA.
if ($MyInvocation.InvocationName -eq '.') { return }
New-Item -ItemType Directory -Force $Logs | Out-Null
$log = Join-Path $Logs ("build-{0}.log" -f (Get-Date -Format yyyyMMdd-HHmmss))
Start-Transcript -Path $log -Append | Out-Null
try {
  Write-Host "Lab IAM - build-lab.ps1 (fase: $Phase)" -ForegroundColor White
  $needAdmin = $Phase -in @('All','Install','Build','Start','Destroy')
  if ($needAdmin -and -not (Test-Admin)) { Fail 'Jalankan PowerShell sebagai Administrator.' }
  switch ($Phase) {
    'All'          { Invoke-Check; Invoke-Requirements; Invoke-Download; Invoke-Install; Invoke-Build }
    'Check'        { Invoke-Check }
    'Requirements' { Invoke-Requirements }
    'Download'     { Invoke-Requirements; Invoke-Download }
    'Install'      { Invoke-Requirements; Invoke-Install }
    'Build'        { Invoke-Requirements; Invoke-Download; Invoke-Build }
    'Start'        { Invoke-Start }
    'Status'       { Invoke-Status }
    'Destroy'      { Invoke-Destroy }
  }
} catch {
  Write-Host "`nBERHENTI: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "Log lengkap: $log"
  exit 1
} finally {
  Stop-Transcript | Out-Null
}
