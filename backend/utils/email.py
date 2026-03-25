import os
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

def send_password_reset_email(to_email: str, otp: str) -> bool:
    """
    Sends a password reset email with a 6-digit OTP using Gmail SMTP over SSL (Port 465).
    Bypasses port 587 blocking on many hosting providers.
    """
    sender_email = os.getenv("GMAIL_EMAIL")
    app_password = os.getenv("GMAIL_APP_PASSWORD")

    if not sender_email or not app_password:
        print("Error: GMAIL_EMAIL or GMAIL_APP_PASSWORD environment variables not set.")
        return False

    # Create the email message
    msg = MIMEMultipart("alternative")
    msg["Subject"] = "Reset your Paatu Padava Password"
    msg["From"] = f"Paatu Padava <{sender_email}>"
    msg["To"] = to_email

    # HTML Body
    html_content = f"""
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
    
    msg.attach(MIMEText(html_content, "html"))

    try:
        # Use SMTP_SSL for Port 465
        with smtplib.SMTP_SSL("smtp.gmail.com", 465) as server:
            server.login(sender_email, app_password)
            server.send_message(msg)
            print(f"Success: Password reset email sent to {to_email}")
            return True
    except Exception as e:
        print(f"Exception while sending Gmail SMTP email: {str(e)}")
        return False
