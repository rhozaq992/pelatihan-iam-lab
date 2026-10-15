#!/usr/bin/env bash
# =============================================================================
# import-ad.sh — bulk import pengguna dummy ke Samba AD (dc1). Dijalankan DI DALAM
# container samba-dc (Sesi 1):
#   docker compose cp ../Pelatihan_IAM/sesi-1-direktori-akses-cis samba-dc:/tmp/sesi1
#   docker compose exec samba-dc bash /tmp/sesi1/import-ad.sh --csv /tmp/sesi1/users_dummy.csv --send-email
#
# Per baris CSV: buat user (CN = username agar unik), sandi awal acak, wajib ganti saat
# login pertama, keanggotaan grup (harus sudah dibuat), status enabled. Opsi --send-email
# mengirim sandi awal ke Mailpit (SMTP mailpit:1025 di jaringan Docker). Data sintetis.
# =============================================================================
set -euo pipefail
CSV="users_dummy.csv"; USEROU="OU=Pengguna"; SEND=0; SMTP="mailpit"; PORT=1025
while [ $# -gt 0 ]; do case "$1" in
  --csv) CSV="$2"; shift 2;;
  --ou) USEROU="$2"; shift 2;;
  --send-email) SEND=1; shift;;
  --smtp) SMTP="$2"; shift 2;;
  -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  *) echo "opsi tak dikenal: $1"; exit 1;;
esac; done
[ -f "$CSV" ] || { echo "CSV tidak ditemukan: $CSV"; exit 1; }

exec python3 - "$CSV" "$USEROU" "$SEND" "$SMTP" "$PORT" <<'PY'
import csv, secrets, smtplib, string, subprocess, sys
from collections import defaultdict
from email.message import EmailMessage

path, userou, send, smtp_host, smtp_port = sys.argv[1], sys.argv[2], sys.argv[3] == "1", sys.argv[4], int(sys.argv[5])

def tool(*args, check=True):
    return subprocess.run(["samba-tool", *args], capture_output=True, text=True, check=check)

def new_password():
    sets = ["ABCDEFGHJKLMNPQRSTUVWXYZ", "abcdefghijkmnpqrstuvwxyz", "23456789", "!@#%^*-_"]
    pw = [secrets.choice(s) for s in sets] + [secrets.choice("".join(sets)) for _ in range(11)]
    secrets.SystemRandom().shuffle(pw)
    # huruf di depan: sandi berawalan '-' akan dibaca samba-tool sebagai opsi
    return secrets.choice(sets[0] + sets[1]) + "".join(pw)

existing = set(tool("user", "list").stdout.split())
groups = set(tool("group", "list").stdout.splitlines())
members = defaultdict(list)
rows = list(csv.DictReader(open(path, encoding="utf-8")))
print(f"Memproses {len(rows)} pengguna dari {path}")
made = skipped = failed = 0
mail = []
for r in rows:
    sam = r["username"]
    if sam in existing:
        skipped += 1
        continue
    pw = new_password()
    res = tool("user", "create", sam, pw, "--use-username-as-cn",
               f"--userou={userou}", f"--given-name={r['given_name']}", f"--surname={r['surname']}",
               f"--mail-address={r['email']}", f"--department={r['department']}",
               f"--job-title={r['title']}", f"--description=Karyawan {r['employee_id']} (data sintetis)",
               "--must-change-at-next-login", check=False)
    if res.returncode != 0:
        failed += 1
        msg = (res.stdout + res.stderr).strip().splitlines()
        print(f"  gagal {sam}: {msg[-1] if msg else 'exit ' + str(res.returncode)}")
        continue
    made += 1
    if r.get("enabled", "true").lower() != "true":
        tool("user", "disable", sam, check=False)
    for g in filter(None, r["groups"].split(";")):
        if g in groups:
            members[g].append(sam)
        else:
            print(f"  ! grup belum ada: {g} (buat dulu)")
    if send and r.get("enabled", "true").lower() == "true":
        mail.append((r, sam, pw))

for g, users in members.items():
    for i in range(0, len(users), 50):          # tambah anggota per batch
        tool("group", "addmembers", g, ",".join(users[i:i + 50]), check=False)

if mail:
    with smtplib.SMTP(smtp_host, smtp_port, timeout=10) as s:
        for r, sam, pw in mail:
            m = EmailMessage()
            m["From"], m["To"], m["Subject"] = "it@iamlab.test", r["email"], "Akun Lab IAM"
            m.set_content(f"Halo {r['given_name']},\n\nAkun lab Anda: {sam}\nSandi awal: {pw}\n"
                          "Ganti sandi saat login pertama.\n\n(Lab terisolasi - data sintetis.)")
            s.send_message(m)
print(f"Selesai: dibuat {made}, dilewati (sudah ada) {skipped}, gagal {failed}"
      + (f", email terkirim {len(mail)}" if mail else " (tanpa --send-email, sandi awal tidak dikirim)"))
PY
