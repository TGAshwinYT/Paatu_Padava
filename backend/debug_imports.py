try:
    print("Testing imports...")
    import database
    print("Database imported.")
    import base
    print("Base imported.")
    import models
    print("Models imported.")
    import routers.music
    print("Music router imported.")
    import routers.auth
    print("Auth router imported.")
    import main
    print("Main imported.")
except ImportError as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()
