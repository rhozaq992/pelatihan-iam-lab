<#
  import-ad.ps1 — bulk import pengguna dummy ke Active Directory (dijalankan di DC).
  Lab IAM. Membuat user dari CSV, menetapkan grup, sandi awal acak, flag ganti saat
  login pertama, dan mengirim email sandi awal via SMTP (Mailpit)

  Jalankan di VM Windows Server 2025 (sebagai Domain Admin):
    .\import-ad.ps1 -Csv .\users_dummy.csv -SmtpServer <IP-docker-host> -SmtpPort 1025

  Catatan: Mailpit menerima SMTP di port 1025 (tanpa TLS) — publikasikan port itu
  bila ingin skrip DC mengirim ke Mailpit (tambahkan "1025:1025" pada service mailpit),
  atau gunakan server SMTP uji lain. Semua data sintetis.
#>
param(
  [string]$Csv = ".\users_dummy.csv",
  [string]$BaseDN = "DC=iamlab,DC=test",
  [string]$UserOU = "OU=Pengguna,DC=iamlab,DC=test",
  [string]$SmtpServer = "",
  [int]$SmtpPort = 1025,
  [switch]$SendEmail
)

Import-Module ActiveDirectory

function New-RandomPassword {
  # 16 karakter acak memenuhi kompleksitas.
  $sets = @('ABCDEFGHJKLMNPQRSTUVWXYZ','abcdefghijkmnpqrstuvwxyz','23456789','!@#$%^&*-_')
  $pw = ($sets | ForEach-Object { $_[(Get-Random -Max $_.Length)] }) -join ''
  $all = ($sets -join '')
  1..12 | ForEach-Object { $pw += $all[(Get-Random -Max $all.Length)] }
  return $pw
}

if (-not (Test-Path $Csv)) { throw "CSV tidak ditemukan: $Csv" }
$rows = Import-Csv $Csv
Write-Host "Memproses $($rows.Count) pengguna dari $Csv"

foreach ($r in $rows) {
  $sam = $r.username
  if (Get-ADUser -Filter "sAMAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
    Write-Host "  lewati (sudah ada): $sam"; continue
  }
  $pw = New-RandomPassword
  $sec = ConvertTo-SecureString $pw -AsPlainText -Force
  try {
    New-ADUser -Name "$($r.given_name) $($r.surname)" `
      -GivenName $r.given_name -Surname $r.surname `
      -SamAccountName $sam -UserPrincipalName "$sam@iamlab.test" `
      -DisplayName "$($r.given_name) $($r.surname)" `
      -EmailAddress $r.email -Department $r.department -Title $r.title `
      -EmployeeID $r.employee_id -Path $UserOU `
      -AccountPassword $sec -Enabled ([bool]::Parse($r.enabled)) `
      -ChangePasswordAtLogon $true -ErrorAction Stop

    foreach ($g in ($r.groups -split ';' | Where-Object { $_ })) {
      if (Get-ADGroup -Filter "Name -eq '$g'" -ErrorAction SilentlyContinue) {
        Add-ADGroupMember -Identity $g -Members $sam -ErrorAction SilentlyContinue
      } else {
        Write-Warning "  grup belum ada: $g (buat dulu grup/OU)"
      }
    }

    if ($SendEmail -and $SmtpServer -and [bool]::Parse($r.enabled)) {
      $body = "Halo $($r.given_name),`n`nAkun lab Anda: $sam`nSandi awal: $pw`n" +
              "Ganti sandi saat login pertama.`n`n(Lab terisolasi — data sintetis.)"
      Send-MailMessage -To $r.email -From "it@iamlab.test" -Subject "Akun Lab IAM" `
        -Body $body -SmtpServer $SmtpServer -Port $SmtpPort -ErrorAction SilentlyContinue
    }
    Write-Host "  dibuat: $sam"
  } catch {
    Write-Warning "  gagal $sam : $($_.Exception.Message)"
  }
}
Write-Host "Selesai. (Tanpa -SendEmail, sandi awal tidak dikirim — lihat log untuk verifikasi.)"
