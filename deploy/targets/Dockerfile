# Target akses istimewa (SSH). Peserta memasang trust SSH CA OpenBao & matikan password auth.
FROM debian:12-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server sudo ca-certificates \
    && rm -rf /var/lib/apt/lists/* && mkdir -p /run/sshd \
    && useradd -m -s /bin/bash labadmin && echo 'labadmin:ChangeMe#2026' | chpasswd \
    && adduser labadmin sudo
# Default SENGAJA belum di-hardening (password auth masih aktif) agar peserta berlatih.
# Latihan peserta (Sesi 3 bagian B): TrustedUserCAKeys /etc/ssh/openbao_ca.pub; PasswordAuthentication no.
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
