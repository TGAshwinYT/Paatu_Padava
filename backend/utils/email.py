import os
import requests

def send_password_reset_email(to_email: str, otp: str) -> bool:
    """
    Sends a password reset email with a 6-digit OTP using the Resend API.
    Uses HTTPS to bypass SMTP port blocking.
    """
    api_key = os.getenv("RESEND_API_KEY")
    if not api_key:
        print("Error: RESEND_API_KEY environment variable not set.")
        return False

    url = "https://api.resend.com/emails"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    
    payload = {
        "from": "onboarding@resend.dev",
        "to": [to_email],
        "subject": "Reset your Paatu Padava Password",
        "html": f"""
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
    }

    try:
        response = requests.post(url, headers=headers, json=payload)
        if response.status_code == 200:
            print(f"Success: Password reset email sent to {to_email}")
            return True
        else:
            print(f"Error: Failed to send email via Resend API. Status: {response.status_code}")
            print(f"Response: {response.text}")
            return False
    except Exception as e:
        print(f"Exception while sending email via Resend: {str(e)}")
        return False
