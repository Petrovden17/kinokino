import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
class LocalDatabase {
  static Database? _db;
  static Future<Database> get database async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'kinokino.db');
    _db = await openDatabase(path, version: 3,
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE media (
          id INTEGER PRIMARY KEY, title TEXT NOT NULL, poster_path TEXT,
          is_favorite INTEGER NOT NULL DEFAULT 0, last_opened TEXT,
          user_rating REAL, media_type TEXT NOT NULL DEFAULT 'movie'
        )''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await db.execute('ALTER TABLE media ADD COLUMN user_rating REAL');
        if (oldVersion < 3) await db.execute("ALTER TABLE media ADD COLUMN media_type TEXT NOT NULL DEFAULT 'movie'");
      });
    return _db!;
  }
  static Future<void> setFavorite(int id, String title, String? poster, bool value, {String mediaType='movie'}) async {
    final db=await database;
    await db.rawInsert('''INSERT INTO media(id,title,poster_path,is_favorite,media_type) VALUES(?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET title=excluded.title,poster_path=excluded.poster_path,is_favorite=excluded.is_favorite,media_type=excluded.media_type''',
      [id,title,poster,value?1:0,mediaType]);
  }
  static Future<void> recordOpen(int id,String title,String? poster,{String mediaType='movie'}) async {
    final db=await database;
    await db.rawInsert('''INSERT INTO media(id,title,poster_path,last_opened,media_type) VALUES(?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET title=excluded.title,poster_path=excluded.poster_path,last_opened=excluded.last_opened,media_type=excluded.media_type''',
      [id,title,poster,DateTime.now().toIso8601String(),mediaType]);
  }
  static Future<void> setRating(int id,String title,String? poster,double rating,{String mediaType='movie'}) async {
    final db=await database;
    await db.rawInsert('''INSERT INTO media(id,title,poster_path,user_rating,media_type) VALUES(?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET title=excluded.title,poster_path=excluded.poster_path,user_rating=excluded.user_rating,media_type=excluded.media_type''',
      [id,title,poster,rating,mediaType]);
  }
  static Future<List<Map<String,Object?>>> favorites() async => (await database).query('media',where:'is_favorite=1',orderBy:'title COLLATE NOCASE');
  static Future<List<Map<String,Object?>>> history() async => (await database).query('media',where:'last_opened IS NOT NULL',orderBy:'last_opened DESC');
  static Future<List<Map<String,Object?>>> ratings() async => (await database).query('media',where:'user_rating IS NOT NULL',orderBy:'user_rating DESC');
}
