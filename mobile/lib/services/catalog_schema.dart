import 'package:sqflite/sqflite.dart';

/// Database schema and table initializers for CatalogDatabase
class CatalogSchema {
  static Future<void> createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS movies (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        year INTEGER,
        composer TEXT,
        starring TEXT,
        director TEXT,
        language TEXT,
        cover_url TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS artists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        role TEXT,
        image_url TEXT,
        is_verified INTEGER DEFAULT 1
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS songs (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        movie_title TEXT,
        movie_id TEXT,
        composer TEXT,
        singers TEXT,
        starring TEXT,
        year INTEGER,
        duration INTEGER,
        cover_url TEXT,
        audio_url TEXT,
        source TEXT,
        language TEXT,
        is_dynamic INTEGER DEFAULT 0,
        created_at INTEGER
      );
    ''');

    try {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS songs_fts USING fts4(
          title, movie_title, composer, singers, starring, content="songs"
        );
      ''');

      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS songs_ai AFTER INSERT ON songs BEGIN
          INSERT INTO songs_fts(rowid, title, movie_title, composer, singers, starring)
          VALUES (new.rowid, new.title, new.movie_title, new.composer, new.singers, new.starring);
        END;
      ''');

      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS songs_ad AFTER DELETE ON songs BEGIN
          DELETE FROM songs_fts WHERE rowid = old.rowid;
        END;
      ''');
    } catch (_) {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_songs_title ON songs(title);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_songs_movie ON songs(movie_title);');
    }
  }
}
