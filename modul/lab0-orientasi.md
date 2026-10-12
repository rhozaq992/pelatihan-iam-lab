# Lab 0 — Orientasi Lingkungan (20')

**Tujuan:** memastikan semua layanan siap dan waktu tersinkron (Kerberos sensitif skew).

## Disiapkan
- VM Windows Server 2025 (DC `iamlab.test`) sudah promote.
- Stack Docker (`lab/`) berjalan di Docker Desktop / VM Ubuntu.

## Langkah
1. **DC**: login, buka PowerShell:
   ```powershell
   Get-ADDomain | Select DNSRoot,NetBIOSName
   w32tm /query /status      # pastikan waktu sinkron
   ```
2. **Host Docker**:
   ```bash
   cd lab && cp .env.example .env     # set DC_IP bila berbeda
   docker compose up -d && docker compose ps
   ```
3. **Resolusi nama**: tambahkan ke `hosts` (host peserta) → IP host Docker:
   `kc. app. saml. grafana. bao. mail. pam.iamlab.test`
   (atau buat record A di DNS DC).
4. **Percaya CA lab**: ekspor root CA Caddy, impor ke *Trusted Root* browser:
   ```bash
   docker compose exec caddy cat /data/caddy/pki/authorities/local/root.crt
   ```
5. Buka `https://kc.iamlab.test` dan `https://app.iamlab.test` — harus tanpa peringatan.

## Hasil yang diharapkan
- `docker compose ps` semua `running`/`healthy`.
- Semua endpoint HTTPS terbuka tanpa error sertifikat.
- Selisih waktu DC ↔ host < 5 menit.
