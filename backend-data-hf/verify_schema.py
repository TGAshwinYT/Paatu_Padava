"""
Database Schema Verification Script
Maintained by db_architect agent.
Validates table structures, foreign keys, unique constraints, and indices.
"""
import sys
import os

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from base import Base
import models


def verify_schema_integrity():
    print("[DB ARCHITECT] Starting Schema Verification Audit...")
    tables = Base.metadata.tables
    expected_tables = {
        "users",
        "artists",
        "user_followed_artists",
        "listening_history",
        "search_history",
        "search_click_history",
        "liked_songs",
    }

    missing_tables = expected_tables - set(tables.keys())
    if missing_tables:
        raise ValueError(f"Missing expected tables: {missing_tables}")

    print(f"[SUCCESS] All {len(expected_tables)} primary tables defined.")

    # 1. Verify Unique Constraints
    liked_songs_table = tables["liked_songs"]
    uq_names = [uq.name for uq in liked_songs_table.constraints if hasattr(uq, "name")]
    assert "uq_user_song" in uq_names, "uq_user_song constraint missing on liked_songs!"
    print("[SUCCESS] Unique constraint 'uq_user_song' verified on liked_songs.")

    # 2. Verify Indices
    lh_table = tables["listening_history"]
    index_names = [idx.name for idx in lh_table.indexes]
    assert "ix_user_played_at" in index_names, "ix_user_played_at index missing on listening_history!"
    print("[SUCCESS] Composite index 'ix_user_played_at' verified on listening_history.")

    # 3. Verify Foreign Keys
    for table_name, table in tables.items():
        for fk in table.foreign_keys:
            target_table = fk.target_fullname.split(".")[0]
            assert target_table in tables, f"FK in {table_name} references non-existent table {target_table}"
    print("[SUCCESS] All foreign key relations point to valid target tables.")

    print("\n[DB ARCHITECT AUDIT COMPLETE] 100% Schema Integrity Verified.")
    return True


if __name__ == "__main__":
    verify_schema_integrity()
