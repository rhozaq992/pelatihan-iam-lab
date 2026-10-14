#!/usr/bin/env bash
# =============================================================================
# prep-windows-server.sh — Siapkan bahan VM Windows Server 2025 (x86-64) sebagai
# Domain Controller dc1.iamlab.test.
#
# Windows Server TIDAK dapat diredistribusikan; ISO evaluasi diunduh dari Microsoft
# Evaluation Center (butuh form). Skrip ini:
#   1) Memverifikasi/menunjuk ISO WS2025 x86-64 di distribusi/iso/.
#   2) Menghasilkan 'autounattend.xml' (instalasi tanpa interaksi) + 'Install-DC.ps1'
#      (promosikan jadi DC iamlab.test) di distribusi/iso/windows/ untuk dilampirkan
#      sebagai disk kedua / dimuat saat first-logon.
# Build OVA Windows TIDAK otomatis (perlu boot installer + lisensi) — instruktur membuat
# VM di VMware dari ISO + autounattend, lalu jalankan skrip Sesi 1. Hanya x86-64 (tak ada arm).
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO_DIR="$HERE/iso"; WIN_DIR="$ISO_DIR/windows"; mkdir -p "$WIN_DIR"
EVAL_URL="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025"
say(){ printf '\033[1m==> %s\033[0m\n' "$*"; }

say "1. ISO Windows Server 2025 (x86-64)"
ISO="$(ls "$ISO_DIR"/*[Ss]erver*2025*.iso "$ISO_DIR"/*25398*.iso "$ISO_DIR"/*WS2025*.iso 2>/dev/null | head -1 || true)"
if [ -n "$ISO" ]; then
  echo "  ✓ ISO ditemukan: $(basename "$ISO")"
else
  echo "  ! ISO belum ada. Unduh evaluasi (x86-64) — butuh form Microsoft:"
  echo "    $EVAL_URL"
  echo "    Simpan sebagai: $ISO_DIR/WindowsServer2025_eval_x64.iso"
fi

say "2. autounattend.xml (instalasi tanpa interaksi, x86-64)"
cat > "$WIN_DIR/autounattend.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <SetupUILanguage><UILanguage>en-US</UILanguage></SetupUILanguage>
      <InputLocale>en-US</InputLocale><SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage><UserLocale>en-US</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <UserData><AcceptEula>true</AcceptEula><FullName>Lab</FullName><Organization>IAMLAB</Organization></UserData>
      <ImageInstall><OSImage><InstallFrom><MetaData wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
        <Key>/IMAGE/NAME</Key><Value>Windows Server 2025 SERVERDATACENTER</Value></MetaData></InstallFrom></OSImage></ImageInstall>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <OOBE><HideEULAPage>true</HideEULAPage><ProtectYourPC>3</ProtectYourPC><NetworkLocation>Work</NetworkLocation></OOBE>
      <UserAccounts><AdministratorPassword><Value>P@ssw0rd#DC2026</Value><PlainText>true</PlainText></AdministratorPassword></UserAccounts>
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Order>1</Order><CommandLine>powershell -ExecutionPolicy Bypass -File C:\windows\Install-DC.ps1</CommandLine></SynchronousCommand>
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
XML
echo "  ✓ $WIN_DIR/autounattend.xml"

say "3. Install-DC.ps1 (promosikan jadi DC iamlab.test)"
cat > "$WIN_DIR/Install-DC.ps1" <<'PS1'
# Promosikan server ini menjadi Domain Controller hutan iamlab.test (Lab, data sintetis).
$ErrorActionPreference = "Stop"
# --- IP statis sesuai RENCANA JARINGAN KANONIK (Host-Only lab): DC = 10.10.10.10/24 ---
# Wajib: stack Docker menghubungi DC di 10.10.10.10 (LDAPS/Kerberos/DNS via extra_hosts).
# NIC lab = adapter Host-Only (tanpa gateway internet). DNS menunjuk ke diri sendiri.
$ifx = (Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Select-Object -First 1).ifIndex
if ($ifx) {
  Get-NetIPAddress -InterfaceIndex $ifx -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
  Remove-NetRoute -InterfaceIndex $ifx -DestinationPrefix '0.0.0.0/0' -Confirm:$false -ErrorAction SilentlyContinue
  New-NetIPAddress -InterfaceIndex $ifx -IPAddress 10.10.10.10 -PrefixLength 24 | Out-Null
  Set-DnsClientServerAddress -InterfaceIndex $ifx -ServerAddresses 127.0.0.1
}
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
$sm = ConvertTo-SecureString "P@ssw0rd#DSRM2026" -AsPlainText -Force
Install-ADDSForest -DomainName "iamlab.test" -DomainNetbiosName "IAMLAB" `
  -SafeModeAdministratorPassword $sm -InstallDns -Force
# Reboot otomatis → setelah naik, jalankan langkah Sesi 1 (OU/grup/import-ad.ps1).
PS1
echo "  ✓ $WIN_DIR/Install-DC.ps1"
echo
echo "Langkah kelas (host peserta: VirtualBox) — autounattend.xml memasang & mem-promote DC otomatis:"
echo "  1) Buat ISO kecil berisi autounattend.xml + Install-DC.ps1 (root media), mis. via oscdimg/PowerShell,"
echo "     atau pakai 'VBoxManage unattended install' (meng-inject jawaban + --post-install-command)."
echo "  2) Buat VM: NIC1 = Host-Only lab (10.10.10.0/24); boot dari ISO WS2025 + ISO autounattend."
echo "     Install-DC.ps1 menyetel IP statis 10.10.10.10 + DNS lalu Install-ADDSForest (reboot otomatis)."
echo "  3) Setelah DC naik: salin folder sesi-1 ke DC, jalankan OU/grup + import-ad.ps1 (Sesi 1 Bagian B)."
echo "  (Catatan: VMware juga didukung — lampirkan autounattend.xml via floppy/USB.)"
