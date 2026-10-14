# Image simulasi LAB-ONLY: Impacket (open source) + bash untuk runner berpagar.
FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash iproute2 ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir "setuptools<81" impacket==0.12.0   # impacket butuh pkg_resources (setuptools)
COPY run.sh /usr/local/bin/run.sh
COPY TARGETS.lab /opt/TARGETS.lab
RUN chmod +x /usr/local/bin/run.sh
# Runner juga tersedia di /attack-sim via mount read-only dari compose (sumber yang sama).
CMD ["sleep", "infinity"]
