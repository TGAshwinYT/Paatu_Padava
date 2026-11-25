# Use a slimmed-down Python image
FROM python:3.13-slim

# Set the working directory
WORKDIR /code

# The Caching Magic
COPY ./backend-data-hf/requirements.txt /code/requirements.txt

# Install system dependencies required for curl-cffi and other builds
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    libcurl4-openssl-dev \
    libssl-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir --upgrade -r /code/requirements.txt

# Create non-root user for container execution
RUN useradd -m -u 1000 user

# Copy the rest of your app code and set ownership
COPY . .
RUN chown -R user:user /code

# Explicitly expose the port Hugging Face requires
EXPOSE 7860

# Step inside the backend-data-hf folder and add it to PYTHONPATH
WORKDIR /code/backend-data-hf
ENV PYTHONPATH=/code/backend-data-hf

USER user

# Run the app
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "7860"]
