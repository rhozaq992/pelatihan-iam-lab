"""App-Komentar — aplikasi demo RBAC untuk lab IAM.

Tujuan ajar (dipetakan ke skenario S1-S7 di dokumen Bab 10):
  - S1 beda role: Viewer/Editor/Admin dari klaim grup Keycloak
  - S2 Broken Access Control: otorisasi DITEGAKKAN DI SERVER (bukan sekadar
        menyembunyikan tombol) -> endpoint menolak role tak berhak walau dipanggil langsung
  - S3 IDOR / kepemilikan: Editor hanya boleh hapus/ubah komentar MILIKNYA;
        Admin boleh atas semua -> otorisasi per-objek
  - S4 manipulasi token: Authlib memvalidasi tanda tangan/iss/aud -> token palsu ditolak
  - S5 step-up: hapus massal (/comments/purge) meminta autentikasi ulang (max_age)
  - S6 single logout: /logout mengakhiri sesi lokal + redirect end-session Keycloak
  - S7 jejak audit: tiap aksi dicatat ke stdout (JSON) -> dipungut Alloy -> Loki/Grafana

Catatan: infrastruktur "berjalan tetapi belum dikonfigurasi". Tanpa OIDC_CLIENT_SECRET
valid, app tetap START dan menampilkan status belum terkonfigurasi (peserta mengisi
setelah membuat client di Keycloak). Penegakan role TETAP di sisi server.

ponytail: SQLite + satu berkas; cukup untuk lab, bukan produksi.
"""
import json
import os
import sqlite3
import sys
import time
from functools import wraps

from flask import (Flask, g, redirect, request, session, url_for,
                   render_template, abort, jsonify)
from authlib.integrations.flask_client import OAuth

APP_BASE_URL = os.environ.get("APP_BASE_URL", "http://localhost:5000")
ISSUER = os.environ.get("OIDC_ISSUER", "")
CLIENT_ID = os.environ.get("OIDC_CLIENT_ID", "app-komentar")
CLIENT_SECRET = os.environ.get("OIDC_CLIENT_SECRET", "")
REDIRECT_URI = os.environ.get("OIDC_REDIRECT_URI", APP_BASE_URL + "/callback")
VERIFY_TLS = os.environ.get("OIDC_VERIFY_TLS", "false").lower() == "true"
DB_PATH = os.environ.get("DB_PATH", "/data/komentar.db")

# Pemetaan grup AD/Keycloak -> role aplikasi. Peserta memastikan group mapper
# Keycloak mengirim nama grup ini di klaim 'groups'.
GROUP_ROLE = {
    "GG-App-Admin": "admin",
    "GG-App-Editor": "editor",
    "GG-App-Viewer": "viewer",
}
ROLE_RANK = {"viewer": 1, "editor": 2, "admin": 3}

app = Flask(__name__)
app.secret_key = os.environ.get("FLASK_SECRET", "dev-only-change-me")

# Lab: issuer memakai TLS dari CA internal Caddy. Jika OIDC_VERIFY_TLS=false,
# matikan verifikasi TLS untuk semua request HTTP app (hanya untuk lab terisolasi).
# Alternatif produksi: pasang CA lab dan set REQUESTS_CA_BUNDLE (jangan matikan verifikasi).
if not VERIFY_TLS:
    import functools
    import requests
    import urllib3
    urllib3.disable_warnings()
    requests.Session.request = functools.partialmethod(requests.Session.request, verify=False)

oauth = OAuth(app)
_oidc_ready = bool(ISSUER and CLIENT_SECRET and CLIENT_SECRET != "ISI_SETELAH_BUAT_CLIENT")
if _oidc_ready:
    oauth.register(
        name="keycloak",
        client_id=CLIENT_ID,
        client_secret=CLIENT_SECRET,
        server_metadata_url=ISSUER.rstrip("/") + "/.well-known/openid-configuration",
        client_kwargs={"scope": "openid profile email groups"},
    )


# ---------------- util ----------------
def audit(action, **fields):
    """S7: jejak audit JSON satu-baris ke stdout -> Alloy."""
    rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "app": "app-komentar",
           "action": action, "user": (session.get("user") or {}).get("username"),
           "role": current_role()}
    rec.update(fields)
    print(json.dumps(rec), flush=True)


def db():
    if "db" not in g:
        g.db = sqlite3.connect(DB_PATH)
        g.db.row_factory = sqlite3.Row
        g.db.execute(
            "CREATE TABLE IF NOT EXISTS comments ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT, author TEXT NOT NULL, "
            "body TEXT NOT NULL, created_at TEXT NOT NULL)")
    return g.db


@app.teardown_appcontext
def _close(_):
    d = g.pop("db", None)
    if d is not None:
        d.close()


def roles_from_claims(userinfo):
    groups = userinfo.get("groups") or []
    # Keycloak kadang mengirim grup dengan awalan '/', mis. '/GG-App-Editor'
    norm = {gname.lstrip("/") for gname in groups}
    roles = {GROUP_ROLE[gname] for gname in norm if gname in GROUP_ROLE}
    return roles


def current_role():
    roles = set(session.get("roles") or [])
    if not roles:
        return None
    return max(roles, key=lambda r: ROLE_RANK.get(r, 0))


def require_role(minimum):
    """S2: penegakan OTORISASI DI SERVER untuk tiap endpoint sensitif."""
    def deco(fn):
        @wraps(fn)
        def wrap(*a, **kw):
            if "user" not in session:
                return redirect(url_for("login"))
            have = ROLE_RANK.get(current_role(), 0)
            if have < ROLE_RANK[minimum]:
                audit("DENY_" + fn.__name__.upper(), reason="role_insufficient",
                      required=minimum)
                abort(403)
            return fn(*a, **kw)
        return wrap
    return deco


# ---------------- auth ----------------
@app.route("/login")
def login():
    if not _oidc_ready:
        return render_template("notconfigured.html", issuer=ISSUER or "(belum diset)")
    return oauth.keycloak.authorize_redirect(REDIRECT_URI)


@app.route("/callback")
def callback():
    token = oauth.keycloak.authorize_access_token()
    userinfo = token.get("userinfo") or oauth.keycloak.userinfo(token=token)
    session["user"] = {"username": userinfo.get("preferred_username"),
                       "name": userinfo.get("name")}
    session["roles"] = sorted(roles_from_claims(userinfo))
    session["auth_time"] = int(userinfo.get("auth_time") or time.time())
    audit("LOGIN")
    return redirect(url_for("index"))


@app.route("/logout")
def logout():
    audit("LOGOUT")
    session.clear()
    # S6: akhiri juga sesi di Keycloak (single logout)
    if _oidc_ready:
        meta = oauth.keycloak.load_server_metadata()
        end = meta.get("end_session_endpoint")
        if end:
            return redirect(end + "?post_logout_redirect_uri=" + APP_BASE_URL +
                            "&client_id=" + CLIENT_ID)
    return redirect(url_for("index"))


# ---------------- komentar ----------------
@app.route("/")
def index():
    rows = db().execute("SELECT * FROM comments ORDER BY id DESC").fetchall()
    return render_template("index.html", comments=rows, user=session.get("user"),
                           role=current_role(), ready=_oidc_ready)


@app.route("/comments", methods=["POST"])
@require_role("editor")
def add_comment():
    body = (request.form.get("body") or "").strip()
    if not body:
        abort(400)
    db().execute("INSERT INTO comments(author, body, created_at) VALUES(?,?,?)",
                 (session["user"]["username"], body, time.strftime("%Y-%m-%d %H:%M")))
    db().commit()
    audit("COMMENT_ADD")
    return redirect(url_for("index"))


@app.route("/comments/<int:cid>/delete", methods=["POST"])
@require_role("editor")
def delete_comment(cid):
    row = db().execute("SELECT * FROM comments WHERE id=?", (cid,)).fetchone()
    if not row:
        abort(404)
    # S3: kepemilikan. Editor hanya miliknya; Admin boleh semua (cek per-objek di SERVER).
    me = session["user"]["username"]
    if current_role() != "admin" and row["author"] != me:
        audit("DENY_DELETE", target_id=cid, owner=row["author"], reason="not_owner")
        abort(403)
    db().execute("DELETE FROM comments WHERE id=?", (cid,))
    db().commit()
    audit("COMMENT_DELETE", target_id=cid, owner=row["author"])
    return redirect(url_for("index"))


@app.route("/comments/purge", methods=["POST"])
@require_role("admin")
def purge():
    # S5: step-up — aksi destruktif minta autentikasi "segar" (<5 menit).
    if int(time.time()) - int(session.get("auth_time", 0)) > 300:
        audit("STEPUP_REQUIRED", action="purge")
        if _oidc_ready:
            return oauth.keycloak.authorize_redirect(REDIRECT_URI, max_age=0)
        abort(401)
    db().execute("DELETE FROM comments")
    db().commit()
    audit("COMMENT_PURGE")
    return redirect(url_for("index"))


# API JSON (untuk menguji S2/S3 via curl langsung tanpa UI)
@app.route("/api/comments")
def api_comments():
    rows = db().execute("SELECT id, author, body, created_at FROM comments").fetchall()
    return jsonify([dict(r) for r in rows])


@app.route("/healthz")
def healthz():
    return "ok", 200


@app.errorhandler(403)
def forbidden(_):
    return render_template("denied.html", role=current_role()), 403


if __name__ == "__main__":
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    print(json.dumps({"app": "app-komentar", "oidc_ready": _oidc_ready,
                      "issuer": ISSUER}), file=sys.stderr, flush=True)
    app.run(host="0.0.0.0", port=5000)
