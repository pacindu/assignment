# syntax=docker/dockerfile:1
# -----------------------------------------------------------------------
# NTT GCC Sample API
# Target platform: linux/arm64 (AWS Fargate ARM64)
# Listens on port 80 via gunicorn
# -----------------------------------------------------------------------
FROM python:3.12-slim

# Metadata
LABEL maintainer="NTT" \
      project="GCC" \
      environment="Production"

WORKDIR /app

# Install dependencies first (layer-cached until requirements change)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source
COPY main.py .

EXPOSE 80

# gunicorn: 2 workers, log to stdout so CloudWatch picks them up
CMD ["gunicorn", \
     "--bind", "0.0.0.0:80", \
     "--workers", "2", \
     "--timeout", "30", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "main:app"]
