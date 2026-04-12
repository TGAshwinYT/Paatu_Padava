# Use a slimmed-down Python image
FROM python:3.11-slim

# Set the working directory
WORKDIR /code

# Install system dependencies (Node.js for JS signature solving, FFmpeg for media)
RUN apt-get update && apt-get install -y \
    curl \
    ffmpeg \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# The Caching Magic
COPY ./backend/requirements.txt /code/requirements.txt
RUN pip install --no-cache-dir --upgrade -r /code/requirements.txt

# Copy the rest of your app code
COPY . .

# Explicitly expose the port Hugging Face requires
EXPOSE 7860

# --- THE FIX ---
# Step inside the backend folder and add it to PYTHONPATH
WORKDIR /code/backend
ENV PYTHONPATH=/code/backend

# Run the app
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "7860"]