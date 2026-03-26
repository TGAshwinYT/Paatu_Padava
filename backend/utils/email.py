import os
import requests

def send_password_reset_email(to_email: str, otp: str) -> bool:
    """
    Sends a password reset email via a Google Apps Script Webhook.
    Bypasses SMTP port blocking on Hugging Face using HTTP POST.
    """
    webhook_url = os.getenv("GOOGLE_SCRIPT_URL")

    if not webhook_url:
        print("Error: GOOGLE_SCRIPT_URL environment variable is not set.")
        return False

    try:
        # Step 2: Make the POST request to the webhook
        # The payload matches the Google Apps Script EXPECTATIONS (to, otp)
        response = requests.post(
            webhook_url, 
            json={"to": to_email, "otp": otp}, 
            timeout=10
        )
        
        # Step 3: Parse response and check for success
        if response.status_code == 200:
            result = response.json()
            if result.get("status") == "success":
                print(f"Success: Password reset email sent via Webhook to {to_email}")
                return True
            else:
                print(f"Webhook error: {result.get('message', 'Unknown error')}")
        else:
            print(f"Server error: Received status code {response.status_code}")
            
        return False
        
    except Exception as e:
        print(f"Exception while sending email via Webhook: {str(e)}")
        return False
