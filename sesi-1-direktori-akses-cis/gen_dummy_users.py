#!/usr/bin/env python3
"""Generator data pengguna dummy untuk lab IAM (pustaka standar, seed tetap).

Membangkitkan CSV sintetis (tidak ada data pribadi nyata). Deterministik:
seed tetap -> hasil identik -> lab dapat direset.

Pakai:
  python3 gen_dummy_users.py                 # 200 user -> users_dummy.csv
  python3 gen_dummy_users.py --count 20 --start 201 --out users_batch2.csv

Kolom: username,given_name,surname,department,title,email,employee_id,groups,enabled
"""
import argparse
import csv
import random

DEPTS = ["Pimpinan", "Keuangan", "SDM", "TI", "Operasional", "Layanan", "Hukum"]
DEPT_GROUP = {d: f"GG-{d}" for d in DEPTS}
TITLES = ["Staf", "Analis", "Koordinator", "Kepala Seksi", "Pelaksana", "Penyelia"]
GIVEN = ["Budi", "Siti", "Agus", "Dewi", "Eko", "Rina", "Joko", "Ani", "Hadi", "Lia",
         "Rizki", "Putri", "Dian", "Fajar", "Maya", "Yusuf", "Nina", "Bayu", "Sari", "Tono"]
SUR = ["Santoso", "Wijaya", "Pratama", "Lestari", "Nugroho", "Hartono", "Saputra",
       "Anggraini", "Kurniawan", "Utami", "Permana", "Rahayu", "Hidayat", "Maulana",
       "Puspita", "Setiawan", "Wulandari", "Firmansyah", "Halim", "Ramadhan"]
# Sebagian user masuk grup aplikasi untuk demo RBAC App-Komentar.
APP_GROUPS = ["GG-App-Viewer", "GG-App-Editor", "GG-App-Admin"]


def gen(count, start, seed):
    rnd = random.Random(seed + start)
    rows = []
    for i in range(count):
        n = start + i
        g = rnd.choice(GIVEN)
        s = rnd.choice(SUR)
        dept = rnd.choice(DEPTS)
        uname = f"{g.lower()}.{s.lower()}{n:03d}"
        groups = [DEPT_GROUP[dept]]
        # ~30% dapat role aplikasi (mayoritas viewer)
        if rnd.random() < 0.30:
            groups.append(rnd.choices(APP_GROUPS, weights=[6, 3, 1])[0])
        enabled = "false" if rnd.random() < 0.05 else "true"   # ~5% nonaktif
        rows.append({
            "username": uname, "given_name": g, "surname": s,
            "department": dept, "title": rnd.choice(TITLES),
            "email": f"{uname}@iamlab.test", "employee_id": f"EMP{n:04d}",
            "groups": ";".join(groups), "enabled": enabled,
        })
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=200)
    ap.add_argument("--start", type=int, default=1)
    ap.add_argument("--seed", type=int, default=2026)
    ap.add_argument("--out", default="users_dummy.csv")
    a = ap.parse_args()
    rows = gen(a.count, a.start, a.seed)
    cols = ["username", "given_name", "surname", "department", "title",
            "email", "employee_id", "groups", "enabled"]
    with open(a.out, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
    print(f"tulis {len(rows)} user -> {a.out}")


if __name__ == "__main__":
    main()
