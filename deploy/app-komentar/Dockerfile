FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
RUN mkdir -p /data
ENV DB_PATH=/data/komentar.db
EXPOSE 5000
# Lab: server dev Flask (cukup). Produksi: gunakan gunicorn.
HEALTHCHECK --interval=15s --timeout=5s --retries=5 CMD python -c "import urllib.request;urllib.request.urlopen('http://localhost:5000/healthz')" || exit 1
CMD ["python", "app.py"]
