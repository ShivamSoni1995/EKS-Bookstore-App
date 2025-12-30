# -----------------------------
# Base Image (Slim & Stable)
# -----------------------------
FROM python:3.9-slim

# Prevent .pyc files & enable unbuffered logs
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Set working directory
WORKDIR /app

# Install minimal system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy dependencies first (better layer caching)
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create and use non-root user (security hardening)
RUN useradd -m appuser
USER appuser

# Expose API port
EXPOSE 5000

# Run with Gunicorn (production-safe)
CMD ["gunicorn", "-w", "2", "-b", "0.0.0.0:5000", "main:app"]
