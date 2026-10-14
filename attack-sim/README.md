# attack-sim/

Runner simulasi LAB-ONLY. Lihat `run.sh` dan `TARGETS.lab`.
Defensif: untuk menguji deteksi/mitigasi, bukan menyerang sistem lain.

Runner menolak berjalan bila internet terjangkau dari container. Di Docker Desktop pada PC
yang masih terhubung internet, container ikut online → putus koneksi internet PC (Wi-Fi/LAN)
selama simulasi; lab tetap jalan karena memakai jaringan Host-Only.
