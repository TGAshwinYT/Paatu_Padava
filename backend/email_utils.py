import uuid
import smtplib
import os
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

def send_verification_email(email: str, token: str):
    """
    Mock function to simulate sending a verification email.
    In a real app, use fastapi-mail or a service like SendGrid/SES.
    """
    verification_link = f"http://localhost:8000/api/auth/verify/{token}"
    print(f"--- MOCK EMAIL SENT TO {email} ---")
    print(f"Click the link to verify your account: {verification_link}")
    print("-----------------------------------")

def send_password_reset_email(to_email: str, otp: str) -> bool:
    """
    Sends a real password reset OTP email using Gmail SMTP.
    Requires EMAIL_SENDER and EMAIL_PASSWORD (App Password) in .env.
    """
    sender_email = os.getenv("EMAIL_SENDER")
    sender_password = os.getenv("EMAIL_PASSWORD")
    
    if not sender_email or not sender_password:
        print("ERROR: Email credentials not found in .env. Falling back to terminal log.")
        print(f"--- OTP FOR {to_email}: {otp} ---")
        return False

    message = MIMEMultipart("alternative")
    message["Subject"] = "Password Reset OTP - Paatu Paaduva"
    message["From"] = sender_email
    message["To"] = to_email

    text = f"""
    Hello,

    You requested a password reset for your Paatu Paaduva account.
    Your 6-digit OTP is: {otp}

    This code will expire in 15 minutes.

    If you did not request this, please ignore this email.

    Regards,
    The Paatu Paaduva Team
    """
    
    html = f"""
    <html>
      <body style="font-family: sans-serif; background-color: #121212; color: #ffffff; padding: 20px;">
        <div style="max-width: 600px; margin: 0 auto; background-color: #181818; padding: 40px; border-radius: 12px; border: 1px solid #333;">
          <h2 style="color: #1DB954; text-align: center;">Paatu Paaduva</h2>
          <p>Hello,</p>
          <p>You requested a password reset for your account. Use the code below to proceed:</p>
          <div style="background-color: #282828; padding: 20px; border-radius: 8px; text-align: center; margin: 30px 0;">
            <span style="font-size: 32px; font-weight: bold; letter-spacing: 12px; color: #1DB954;">{otp}</span>
          </div>
          <p style="color: #b3b3b3; font-size: 14px;">This code will expire in <b>15 minutes</b>.</p>
          <hr style="border: 0; border-top: 1px solid #333; margin: 30px 0;">
          <p style="color: #b3b3b3; font-size: 12px; text-align: center;">
            If you did not request this reset, please ignore this email.
          </p>
        </div>
      </body>
    </html>
    """

    part1 = MIMEText(text, "plain")
    part2 = MIMEText(html, "html")
    message.attach(part1)
    message.attach(part2)

    try:
        with smtplib.SMTP("smtp.gmail.com", 587) as server:
            server.starttls()
            server.login(sender_email, sender_password)
            server.sendmail(sender_email, to_email, message.as_string())
        return True
    except Exception as e:
        print(f"SMTP ERROR: Failed to send email to {to_email}. Error: {str(e)}")
        return False
