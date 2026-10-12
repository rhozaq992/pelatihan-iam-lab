# Image simulasi LAB-ONLY: Impacket (open source) + bash untuk runner berpagar.
FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash iproute2 ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir impacket==0.12.0
COPY run.sh /usr/local/bin/run.sh
COPY TARGETS.lab /opt/TARGETS.lab
RUN chmod +x /usr/local/bin/run.sh
# Runner juga di-mount di /attack-sim (compose) agar instruktur dapat mengubahnya.
CMD ["sleep", "infinity"]
