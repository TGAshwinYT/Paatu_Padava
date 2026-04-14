# Use a lightweight Python base image (Sync with HF)
FROM python:3.11-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PORT=8001

# Install system dependencies (ffmpeg is useful for yt-dlp)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose the port
EXPOSE 8001

# Start the application using uvicorn
# We use 0.0.0.0 to allow external connections (from Render)
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001"]
