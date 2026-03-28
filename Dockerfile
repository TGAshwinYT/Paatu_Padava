# Use a slimmed-down Python image
FROM python:3.11-slim

# Set the working directory
WORKDIR /code

# The Caching Magic
COPY ./backend/requirements.txt /code/requirements.txt
RUN pip install --no-cache-dir --upgrade -r /code/requirements.txt

# Copy the rest of your app code
COPY . .

# Explicitly expose the port Hugging Face requires
EXPOSE 7860

# --- THE FIX ---
# Step inside the backend folder before running the app
WORKDIR /code/backend

# Run the app locally as if we are already inside the folder
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "7860"]