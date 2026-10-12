# Lab 5 — Audit & Monitoring (70') · Indikator 4.1

**Tujuan:** jejak audit end-to-end + dashboard pemantauan sederhana.

## 1. Lengkapi pipeline Alloy
Edit `lab/monitoring/alloy/config.alloy` — tambah `stage.match` untuk sumber lain
(bagian **TODO PESERTA**). Prinsip label: **hanya low-cardinality** (`service`, `event`);
`user`/`ip` sebagai field (`| json` di LogQL), jangan dijadikan label.
```alloy
stage.match {
  selector = "{service=\"openbao\"}"
  stage.json { expressions = { path = "request.path", bao_user = "auth.display_name", ip = "request.remote_address" } }
  stage.labels { values = { event = "path" } }
  stage.structured_metadata { values = { user = "bao_user", ip = "ip" } }
}
```
Reload: `docker compose restart alloy`.

## 2. Windows Event dari DC
Pasang **Grafana Alloy** di VM DC → kirim log Security ke Loki lab:
```alloy
loki.source.windowsevent "sec" { eventlog_name = "Security" forward_to = [loki.write.lab.receiver] }
loki.write "lab" { endpoint { url = "http://<IP-host-docker>:3100/loki/api/v1/push" } }
```

## 3. Dashboard "Identity Audit" di Grafana (`https://grafana.iamlab.test`)
Buat ≥ 4 panel (datasource Loki sudah terprovision). Label `event` berisi tipe event
Keycloak (LOGIN, LOGIN_ERROR, dst.); `ipAddress` diekstrak saat query dengan `| regexp`:
- Login sukses vs gagal: `sum(count_over_time({service="keycloak", event="LOGIN"}[5m]))` vs `event="LOGIN_ERROR"`.
- Top IP gagal:
  ```logql
  topk(10, sum by (ipAddress) (
    count_over_time({service="keycloak", event="LOGIN_ERROR"}
      | regexp `ipAddress="?(?P<ipAddress>[0-9.]+)` [15m])))
  ```
- Aktivitas per client · Perubahan grup (dari Windows Event 4728/4732).

## 4. Alert rules + contact point Mailpit
- Rule brute force: LOGIN_ERROR per IP > 10 / 5m.
- Contact point: SMTP `mailpit:1025` → uji kirim.

## 5. Telusur satu login end-to-end
Login App-Komentar → lihat jejaknya di Keycloak (LOGIN) lalu LDAP bind di AD (Windows Event 4768/4769).

## Hasil yang diharapkan
- ≥ 5 sumber log tampil di Loki; dashboard menampilkan data; alert memicu email uji di Mailpit.
