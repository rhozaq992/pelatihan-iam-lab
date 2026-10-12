# Lab 2 — SSO, MFA & App-Komentar (85') · Indikator 2.1, 2.2

**Tujuan:** integrasi aplikasi ke IdP, beda hak akses (RBAC), dan MFA pada layanan kritikal.
Dikerjakan di **Keycloak admin** (`https://kc.iamlab.test`, realm master → buat realm `iamlab`).

## 1. Realm + federasi LDAP ke AD
1. **Create realm** → `iamlab`.
2. **User federation → Add LDAP**:
   - Vendor: *Active Directory*
   - Connection URL: `ldaps://dc1.iamlab.test:636` (impor CA lab ke truststore bila perlu)
   - Bind DN: `CN=svc-keycloak,OU=AkunLayanan,DC=iamlab,DC=test` · Bind cred: (sandi svc-keycloak)
   - Edit mode: **READ_ONLY**
   - **Users DN: `DC=iamlab,DC=test`** (root — mencakup Pengguna, Tier0, AkunLayanan; jika hanya OU=Pengguna, login admin akan gagal)
   - Username LDAP attr: `sAMAccountName` · UUID: `objectGUID`
   - **Save → Test connection & authentication → Synchronize all users**
3. **Mappers → Create → group-ldap-mapper**: LDAP Groups DN `OU=Grup,DC=iamlab,DC=test`, membership attr `member`, mode READ_ONLY → **Sync LDAP groups to Keycloak**.

## 2. Client OIDC untuk App-Komentar
1. **Clients → Create → OpenID Connect**, Client ID `app-komentar`.
2. Client authentication **On** (confidential); Standard flow **On**; **Direct access grants Off**.
3. Valid redirect URIs: `https://app.iamlab.test/callback` · Web origins: `https://app.iamlab.test`.
4. **Advanced → Proof Key for Code Exchange: S256**.
5. **Client scopes → app-komentar-dedicated → Add mapper → Group Membership**: token claim name `groups`, **Full group path = Off** (agar bernama `GG-App-...`). Pastikan scope `groups` masuk default.
6. **Credentials → copy Client secret** → isi `lab/.env` (`APP_OIDC_CLIENT_SECRET`) → `docker compose up -d app-komentar`.

Uji: buka `https://app.iamlab.test` → *masuk (SSO)* dengan user yang bergrup `GG-App-*`. Role tampil sesuai grup.

## 3. Client SAML untuk App-SAML
- **Clients → Create → SAML**, Client ID = entity id SP App-SAML. Unduh IdP metadata
  (`https://kc.iamlab.test/realms/iamlab/protocol/saml/descriptor`) untuk konfigurasi mellon
  (lihat `solutions/`). Assertion **signed**.

## 4. MFA bersyarat (Google Authenticator)
1. **Authentication → Required actions**: *Configure OTP* = On.
2. **Authentication → Flows → Browser → Duplicate** → tambahkan sub-flow **Conditional OTP**:
   - *Condition – User Role* / atau *Condition – user configured* → OTP Form **Required**.
   - Targetkan ke grup admin (mis. role dari `GG-Tier0-Admin`) & client kritikal.
3. **Bind** flow sebagai *Browser flow* untuk realm (atau override per-client untuk Grafana/Warpgate).
4. Uji: user biasa login App-Komentar tanpa OTP; **admin dipaksa scan QR Google Authenticator**.

> Catatan: realm Keycloak 26 memiliki aksi default **Verify Profile**. User dari
> federasi AD sudah lengkap (email/nama). Jika Anda membuat user lokal manual untuk
> uji, isi email + firstName + lastName + set sandi permanen, atau login akan ditolak
> "Account is not fully set up".

## 5. Pertahanan brute force & SMTP
- **Realm settings → Security defenses → Brute force detection: On**.
- **Realm settings → Email**: Host `mailpit`, Port `1025`, From `no-reply@iamlab.test` (untuk reset & verifikasi).
- **Realm settings → Sessions/Tokens**: perpendek masa hidup sesi & akses token.
- **Realm settings → Events**: aktifkan *Save events* (user + admin) + listener `jboss-logging`.

## Hasil yang diharapkan
- App-Komentar: Viewer tak punya tombol hapus; Editor hapus miliknya; Admin hapus semua.
- Admin realm/Grafana dipaksa OTP; brute force aktif; events tercatat.
EOF
echo "lab2 ok"