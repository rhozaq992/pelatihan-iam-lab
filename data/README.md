# data/ — Data dummy & import

- `gen_dummy_users.py` — generator CSV sintetis (seed tetap, deterministik).
  - `python3 gen_dummy_users.py` → `users_dummy.csv` (200 user)
  - `python3 gen_dummy_users.py --count 20 --start 201 --out users_batch2.csv`
- `users_dummy.csv`, `users_batch2.csv` — contoh hasil (regenerable).
- `import-ad.ps1` — bulk import ke Active Directory (dijalankan di VM DC):
  membuat user + grup, sandi awal acak, flag ganti saat login, opsi kirim email ke Mailpit.

Semua data sintetis; tidak ada data pribadi nyata (UU PDP).
