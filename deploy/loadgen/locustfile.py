"""Load generator lab IAM (Locust).

Profil dipilih via env LAB_PROFILE: normal | spray | fail-then-success | off-hours.
Catatan: HANYA membidik layanan lab (host diisi di compose). Laju dibatasi.
Login OIDC penuh (termasuk OTP) disederhanakan — lihat catatan di dokumen Bab 13.
ponytail: satu berkas, memukul endpoint HTTP lab; bukan klien OIDC lengkap.
"""
import os
import random
from locust import HttpUser, task, between

PROFILE = os.environ.get("LAB_PROFILE", "normal")
USERS = [f"user{n:03d}" for n in range(1, 201)]


class LabUser(HttpUser):
    wait_time = between(1, 3)

    def _try_login(self, username, password):
        # Memukul halaman login App-Komentar (yang redirect ke Keycloak).
        # Di lab nyata, alur kode OIDC dijalankan; di sini cukup menimbulkan
        # trafik autentikasi untuk menghasilkan event login sukses/gagal.
        with self.client.get("/login", allow_redirects=True, catch_response=True,
                             verify=False, name=f"login[{PROFILE}]") as r:
            r.success()

    @task
    def run_profile(self):
        if PROFILE == "spray":
            # satu pola: banyak user, sandi salah
            self._try_login(random.choice(USERS), "Wrong#Password")
        elif PROFILE == "fail-then-success":
            u = USERS[0]
            for _ in range(5):
                self._try_login(u, "Wrong#Password")
            self._try_login(u, "Correct#Password")
        else:  # normal / off-hours
            self._try_login(random.choice(USERS), "Correct#Password")
