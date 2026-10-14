"""Load generator lab IAM (Locust).

Profil dipilih via env LAB_PROFILE: normal | spray | fail-then-success | off-hours.
Catatan: HANYA membidik layanan lab (host diisi di compose). Laju dibatasi.

Tiap percobaan menjalankan alur login nyata: App-Komentar (/login) -> redirect ke form
login Keycloak -> POST username/sandi. Sandi salah menghasilkan event LOGIN_ERROR,
sandi benar menghasilkan LOGIN (keduanya dipanen Alloy -> Loki untuk Sesi 4).
Login sukses butuh akun uji dengan sandi permanen & tanpa OTP: LAB_TEST_USER/LAB_TEST_PASS.
'off-hours' = pola 'normal' yang dijalankan instruktur di luar jam kerja.
"""
import html
import os
import random
import re

from locust import HttpUser, task, between

PROFILE = os.environ.get("LAB_PROFILE", "normal")
TEST_USER = os.environ.get("LAB_TEST_USER", "")
TEST_PASS = os.environ.get("LAB_TEST_PASS", "")
# Akun nyata dari users_dummy.csv (Sesi 1) -> spray menyasar pengguna yang ada.
USERS = ["dewi.puspita001", "dian.hartono002", "tono.pratama003", "hadi.maulana004",
         "ani.hidayat005", "putri.permana006", "siti.permana007", "dian.halim008",
         "agus.ramadhan009", "yusuf.anggraini010", "agus.firmansyah011", "rizki.puspita012"]
FORM_ACTION = re.compile(r'<form[^>]+id="kc-form-login"[^>]+action="([^"]+)"', re.S)


class LabUser(HttpUser):
    wait_time = between(1, 3)

    def _try_login(self, username, password):
        """Satu percobaan login penuh. Mengembalikan True bila Keycloak menerima sandi."""
        self.client.cookies.clear()   # sesi baru tiap percobaan (seperti klien berbeda)
        r = self.client.get("/login", verify=False, name="1 buka form login")
        m = FORM_ACTION.search(r.text or "")
        if not m:
            # Realm/client belum dibuat (Sesi 2) atau app belum terkonfigurasi.
            return False
        with self.client.post(html.unescape(m.group(1)), verify=False, catch_response=True,
                              data={"username": username, "password": password,
                                    "credentialId": ""},
                              name=f"2 kirim kredensial [{PROFILE}]") as resp:
            ok = 'id="kc-form-login"' not in resp.text   # form muncul lagi = sandi ditolak
            resp.success()   # kegagalan login adalah skenario yang diharapkan, bukan error uji
        return ok

    @task
    def run_profile(self):
        if PROFILE == "spray":
            # satu sandi umum dicoba ke banyak akun
            self._try_login(random.choice(USERS), "Musim#Hujan2026")
        elif PROFILE == "fail-then-success":
            u = TEST_USER or USERS[0]
            for _ in range(5):
                self._try_login(u, "Wrong#Password")
            if TEST_USER and TEST_PASS:
                self._try_login(TEST_USER, TEST_PASS)
        else:  # normal / off-hours
            if TEST_USER and TEST_PASS:
                self._try_login(TEST_USER, TEST_PASS)
