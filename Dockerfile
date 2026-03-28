# Use a slimmed-down Python image for much faster build times
FROM python:3.11-slim

# Set the working directory
WORKDIR /code

# The Caching Magic (You already had this right!)
COPY ./backend/requirements.txt /code/requirements.txt
RUN pip install --no-cache-dir --upgrade -r /code/requirements.txt

# Copy the rest of your app code
COPY . .

# Explicitly expose the port Hugging Face requires
EXPOSE 7860

# Force FastAPI (uvicorn) to broadcast on 0.0.0.0 and port 7860
CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "7860"]