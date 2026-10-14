# attack-sim/

Runner simulasi LAB-ONLY. Lihat `run.sh` dan `TARGETS.lab`.
Defensif: untuk menguji deteksi/mitigasi, bukan menyerang sistem lain.

Runner menolak berjalan bila internet terjangkau dari container. Service `attacker` memakai
jaringan `attacknet` (`internal: true`) yang hanya menjangkau `dc1` tanpa rute ke internet,
sehingga pengaman ini lolos otomatis — TIDAK perlu memutus Wi-Fi/LAN PC.
