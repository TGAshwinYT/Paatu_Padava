import uuid

def send_verification_email(email: str, token: str):
    """
    Mock function to simulate sending a verification email.
    In a real app, use fastapi-mail or a service like SendGrid/SES.
    """
    verification_link = f"http://localhost:8000/api/auth/verify/{token}"
    print(f"--- MOCK EMAIL SENT TO {email} ---")
    print(f"Click the link to verify your account: {verification_link}")
    print("-----------------------------------")
