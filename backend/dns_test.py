import socket
try:
    host = "aws-1-ap-south-1.pooler.supabase.com"
    print(f"Resolving {host}...")
    ip = socket.gethostbyname(host)
    print(f"Success! IP: {ip}")
except Exception as e:
    print(f"Error: {e}")
