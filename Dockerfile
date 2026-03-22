FROM python:3.9

# Set the working directory
WORKDIR /code

# Copy requirements and install
COPY ./backend/requirements.txt /code/requirements.txt
RUN pip install --no-cache-dir --upgrade -r /code/requirements.txt

# Copy the rest of your app code
COPY . .

# Command to run the app
# Use the full path since we are in /code and copied everything
CMD ["python", "backend/main.py"]
