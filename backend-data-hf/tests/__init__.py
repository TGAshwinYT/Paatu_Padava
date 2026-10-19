import os

# Set testing environment variables for test runners and CI environments
if not os.environ.get("JWT_SECRET"):
    os.environ["JWT_SECRET"] = "test_jwt_secret_for_ci_and_local_testing_minimum_32_chars"
if not os.environ.get("SUPABASE_JWT_SECRET"):
    os.environ["SUPABASE_JWT_SECRET"] = "test_supabase_jwt_secret_for_ci_and_local_testing"
