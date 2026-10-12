# Sesi 0 — Pengantar: Topologi Sistem & Teori Dasar

Sesi pembuka. Tujuannya memberi **gambaran utuh** sistem IAM yang akan dibangun
dan **fondasi teori** yang dipakai berulang di sesi-sesi berikutnya. Detail teknis
dan praktik diperdalam per sesi (lihat `sesi-1` … `sesi-4`).

## a. Tujuan Sesi

Peserta memahami:
- Peta keseluruhan sistem (komponen, jaringan, aliran data) sebelum masuk ke praktik.
- Konsep dasar identitas: **IAAA** (Identifikasi, Autentikasi, Otorisasi, Audit).
- Perbedaan dan peran **AD/LDAP**, **SSO (SAML/OIDC)**, **MFA**, **PAM**, dan **audit/UBA**.
- Bagaimana tiap komponen saling terhubung dan dipetakan ke 4 sesi praktik.

## b. Output yang Diharapkan

- Peserta dapat menjelaskan alur "pengguna → aplikasi → IdP → direktori" dengan kata sendiri.
- Peserta mengenali di mana tiap komponen berada pada topologi dan apa fungsinya.
- Lingkungan lab siap (VM AD berjalan, stack layanan berjalan, nama domain teruji).

## c. Teori Dasar

### IAAA — empat pilar identitas
| Pilar | Makna | Analogi |
|------|-------|---------|
| **Identifikasi** | Mengaku sebagai siapa (username) | Menyebut nama di resepsionis |
| **Autentikasi** | Membuktikan klaim identitas (faktor) | Menunjukkan KTP/kartu akses |
| **Otorisasi** | Hak melakukan apa (peran/izin) | Kartu hanya membuka lantai tertentu |
| **Audit** | Mencatat siapa melakukan apa & kapan | Buku tamu + CCTV |

**Identitas terpusat** memindahkan keempatnya dari tiap aplikasi ke satu sumber
kebenaran (direktori) dan satu gerbang (IdP), sehingga kebijakan konsisten,
penonaktifan akun berlaku serentak, dan jejak audit terkumpul. _Analogi:_ dari
"tiap pintu punya daftar tamu sendiri" menjadi "satu lobi dengan satu petugas dan
satu buku tamu".

### Komponen & perannya
- **Active Directory (AD/LDAP)** — direktori + _control plane_ identitas: pengguna,
  grup, Kerberos, DNS, Group Policy. *(Sesi 1)*
- **Keycloak (Identity Provider)** — gerbang SSO yang memverifikasi identitas ke
  direktori dan menerbitkan token/assertion untuk aplikasi; menegakkan **MFA**. *(Sesi 2)*
- **MFA (Google Authenticator / TOTP)** — faktor kedua "sesuatu yang dimiliki"
  selain sandi "sesuatu yang diketahui". *(Sesi 2)*
- **PAM (OpenBao + Warpgate)** — brankas kredensial istimewa + jump server yang
  merekam sesi admin. *(Sesi 3)*
- **Audit & Monitoring (Alloy → Loki → Grafana)** — mengumpulkan log identitas dan
  menampilkan dashboard + alert; **UBA** mendeteksi perilaku tak lazim. *(Sesi 4)*

### Protokol federasi (ringkas — diperdalam di Sesi 2)
- **SAML 2.0** — autentikasi + atribut via XML Assertion bertanda tangan.
- **OAuth 2.0** — otorisasi akses sumber daya (bukan login).
- **OpenID Connect (OIDC)** — lapisan identitas di atas OAuth 2.0; token = ID Token (JWT).
  Alur aman yang dipakai lab: **Authorization Code + PKCE**.

_Analogi SSO:_ gelang masuk festival — diperiksa sekali di gerbang (IdP), lalu semua
panggung (aplikasi) menerimanya tanpa periksa ulang identitas.

## d. Struktur Sistem (Topologi)

Seluruh lab berjalan terisolasi di PC peserta (jaringan Host-Only, tanpa internet),
domain sintetis **`iamlab.test`**:

```
                         PC Peserta (host)
  ┌───────────────────────────────────────────────────────────────┐
  │  VM Windows Server 2025  (Tier 0 / control plane)              │
  │  dc1.iamlab.test — AD DS · DNS · Kerberos · GPO · SYSVOL       │   ← Sesi 1
  └───────────────┬───────────────────────────────────────────────┘
                  │ LDAPS 636 (federasi)        │ Kerberos / GPO
                  ▼                             ▼
  ┌───────────────────────────────────────────────────────────────┐
  │  Stack layanan (Docker)                                        │
  │                                                                │
  │   Caddy (reverse proxy + TLS CA internal)  :443                │
  │     ├─ Keycloak (IdP SAML/OIDC + MFA) ──── PostgreSQL          │   ← Sesi 2
  │     │     ├─ App-Komentar (RBAC: viewer/editor/admin)          │
  │     │     └─ App-SAML                                          │
  │     ├─ Warpgate (bastion + rekam sesi) ── srv-app01 / srv-db01 │   ← Sesi 3
  │     ├─ OpenBao (vault kredensial + SSH CA)                     │
  │     ├─ Mailpit (SMTP uji: reset & kirim sandi)                 │
  │     └─ Grafana ← Loki ← Alloy  (audit & dashboard)             │   ← Sesi 4
  │                                                                │
  │   Locust (load generator)   ·   attacker (simulasi, allowlist) │
  └───────────────────────────────────────────────────────────────┘
```

**Aliran data inti:** pengguna membuka aplikasi → diarahkan ke **Keycloak** →
Keycloak memverifikasi kredensial ke **AD** (LDAPS) dan meminta **MFA** bila perlu →
menerbitkan token → aplikasi memberi akses sesuai peran (klaim grup). Semua aktivitas
autentikasi/otorisasi mengalir sebagai log ke **Alloy → Loki → Grafana** untuk audit.

## Peta Sesi

| Sesi | Fokus | Indikator |
|------|-------|-----------|
| **1** | Pengamanan Direktori (AD/LDAP) & GPO; simulasi terkendali | 1.1, 1.2 |
| **2** | SSO & MFA (Keycloak) + App-Komentar (RBAC) | 2.1, 2.2 |
| **3** | Privileged Access Management (OpenBao + Warpgate) | 3.1, 3.2 |
| **4** | Audit & Monitoring (Alloy/Loki/Grafana) + capstone | 4.1, 4.2 |

> Lingkungan (VM AD + stack layanan) disiapkan terlebih dahulu; peserta fokus pada
> **konfigurasi keamanan** di tiap sesi, bukan instalasi dari nol.
