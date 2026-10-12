import os
import smtplib
import logging
from email.message import EmailMessage

logger = logging.getLogger(__name__)


def send_verification_email(email: str, token: str):
    """
    Sends a verification email via standard SMTP (e.g. Brevo free tier or standard SMTP).
    Falls back to a secure log notice if SMTP credentials are not configured.
    """
    app_url = os.getenv("APP_URL", "http://localhost:8000").rstrip("/")
    verification_link = f"{app_url}/api/auth/verify/{token}"

    smtp_host = os.getenv("SMTP_HOST")
    smtp_port = int(os.getenv("SMTP_PORT", "587"))
    smtp_user = os.getenv("SMTP_USER")
    smtp_password = os.getenv("SMTP_PASSWORD")
    smtp_from = os.getenv("SMTP_FROM_EMAIL", smtp_user or "noreply@paatupadava.com")

    if smtp_host and smtp_user and smtp_password:
        try:
            msg = EmailMessage()
            msg["Subject"] = "Verify Your Paatu Padava Account"
            msg["From"] = smtp_from
            msg["To"] = email
            msg.set_content(
                f"Welcome to Paatu Padava!\n\n"
                f"Please verify your email address by opening the following link:\n"
                f"{verification_link}\n\n"
                f"If you did not create this account, please disregard this email."
            )

            with smtplib.SMTP(smtp_host, smtp_port, timeout=10.0) as server:
                server.starttls()
                server.login(smtp_user, smtp_password)
                server.send_message(msg)
            logger.info("Verification email successfully dispatched to %s", email)
            return
        except Exception as e:
            logger.error("Failed to send verification email to %s via SMTP: %s", email, e)

    # In local development or if SMTP is not configured:
    logger.info("[AUTH] Verification token generated for %s (link: %s)", email, verification_link)

