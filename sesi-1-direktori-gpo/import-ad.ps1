<#
  import-ad.ps1 - bulk import pengguna dummy ke Active Directory (dijalankan di DC).
  Lab IAM. Membuat user dari CSV, menetapkan grup, sandi awal acak, flag ganti saat
  login pertama, dan (opsional) mengirim email sandi awal via SMTP (Mailpit).

  Jalankan di VM Windows Server 2025 (sebagai Domain Admin):
    .\import-ad.ps1 -Csv .\users_dummy.csv -SendEmail -SmtpServer 10.10.10.5 -SmtpPort 1025

  Catatan: Mailpit menerima SMTP di port 1025 (tanpa TLS; sudah dipublikasikan compose).
  Tanpa -SendEmail, sandi awal TIDAK dikirim. Semua data sintetis.
  Berkas ini sengaja ASCII murni: Windows PowerShell 5.1 membaca .ps1 tanpa BOM sebagai
  ANSI, sehingga karakter non-ASCII (mis. em-dash) dapat merusak parsing string.
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
    # -Name (CN) wajib unik per OU; nama lengkap bisa kembar -> pakai sAMAccountName.
    New-ADUser -Name $sam `
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
              "Ganti sandi saat login pertama.`n`n(Lab terisolasi - data sintetis.)"
      Send-MailMessage -To $r.email -From "it@iamlab.test" -Subject "Akun Lab IAM" `
        -Body $body -SmtpServer $SmtpServer -Port $SmtpPort -ErrorAction SilentlyContinue
    }
    Write-Host "  dibuat: $sam"
  } catch {
    Write-Warning "  gagal $sam : $($_.Exception.Message)"
  }
}
Write-Host "Selesai. (Tanpa -SendEmail, sandi awal tidak dikirim - lihat log untuk verifikasi.)"
