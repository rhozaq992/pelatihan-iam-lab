# SP SAML contoh: Apache httpd + mod_auth_mellon.
# Infra berjalan; konfigurasi SP (metadata IdP, proteksi lokasi) = tugas peserta Sesi 2.
FROM debian:12-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      apache2 libapache2-mod-auth-mellon ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && a2enmod auth_mellon
COPY index.html /var/www/html/index.html
COPY protected.html /var/www/html/protected/index.html
# TODO PESERTA: taruh config mellon di /etc/apache2/conf-enabled/mellon.conf
#   (MellonSPMetadataFile, MellonIdPMetadataFile dari Keycloak, <Location /protected>)
EXPOSE 80
CMD ["apache2ctl", "-D", "FOREGROUND"]
