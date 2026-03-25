import smtplib
import os
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

def send_password_reset_email(to_email: str, otp: str) -> bool:
    """
    Sends a password reset email with a 6-digit OTP using Gmail SMTP.
    """
    sender_email = os.getenv("EMAIL_SENDER")
    sender_password = os.getenv("EMAIL_PASSWORD")

    if not sender_email or not sender_password:
        print("Error: EMAIL_SENDER or EMAIL_PASSWORD environment variables not set.")
        return False
    
    # Cast to str to satisfy static analysis
    sender_email_str: str = str(sender_email)
    sender_password_str: str = str(sender_password)

    # Create the email content
    message = MIMEMultipart("alternative")
    message["Subject"] = "Password Reset OTP"
    message["From"] = sender_email_str
    message["To"] = to_email

    text = f"""
    Hi,

    A password reset was requested for your account. 
    Your 6-digit OTP code is: {otp}

    This code will expire in 15 minutes.

    If you did not request this, please ignore this email.
    """
    
    html = f"""
    <html>
      <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
        <div style="max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #ddd; border-radius: 10px;">
          <h2 style="color: #1DB954;">Password Reset Request</h2>
          <p>Hi,</p>
          <p>A password reset was requested for your account. Use the following 6-digit OTP code to proceed:</p>
          <div style="background-color: #f4f4f4; padding: 15px; text-align: center; font-size: 24px; font-weight: bold; letter-spacing: 5px; border-radius: 5px;">
            {otp}
          </div>
          <p>This code will expire in <strong>15 minutes</strong>.</p>
          <p>If you did not request this, please ignore this email.</p>
          <hr style="border: 0; border-top: 1px solid #eee; margin: 20px 0;">
          <p style="font-size: 12px; color: #888;">This is an automated message. Please do not reply.</p>
        </div>
      </body>
    </html>
    """

    part1 = MIMEText(text, "plain")
    part2 = MIMEText(html, "html")
    message.attach(part1)
    message.attach(part2)

    try:
        # Connect to Gmail SMTP server
        with smtplib.SMTP("smtp.gmail.com", 587) as server:
            server.starttls()  # Secure the connection
            server.login(sender_email_str, sender_password_str)
            server.sendmail(sender_email_str, to_email, message.as_string())
        return True
    except Exception as e:
        print(f"Failed to send email: {e}")
        return False
