# OpenBao — konfigurasi lab. Server START dalam keadaan UNINITIALIZED.
# Peserta menjalankan: bao operator init / unseal / enable audit / policy / auth ldap.
ui = false   # image OpenBao 2.1.0 tidak membundel aset UI → lab memakai CLI (konsisten dgn modul Sesi 3)

storage "file" {
  path = "/openbao/file"
}

# TLS diterminasi di Caddy (bao.iamlab.test). Di dalam jaringan lab listener plaintext.
# Di produksi: aktifkan TLS listener. (Catatan hardening: lihat Sesi 3.)
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}


api_addr = "http://openbao:8200"
