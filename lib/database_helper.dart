import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();

  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDB('digital24online.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(
    Database db,
    int version,
  ) async {
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        serial_no INTEGER,
        user_id TEXT NOT NULL,
        name TEXT NOT NULL,
        mobile TEXT,
        package_name TEXT,
        bill_date TEXT,
        amount REAL DEFAULT 0,
        total_amount REAL DEFAULT 0,
        paid_amount REAL DEFAULT 0,
        payment_date TEXT,
        due_amount REAL DEFAULT 0,
        active INTEGER DEFAULT 1
      )
    ''');
  }

  Future<int> addCustomer(
    Map<String, dynamic> customer,
  ) async {
    final db = await database;

    return await db.insert(
      'customers',
      customer,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getCustomers() async {
    final db = await database;

    return await db.query(
      'customers',
      orderBy: 'serial_no ASC',
    );
  }

  Future<int> updateCustomer(
    int id,
    Map<String, dynamic> customer,
  ) async {
    final db = await database;

    return await db.update(
      'customers',
      customer,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteCustomer(int id) async {
    final db = await database;

    return await db.delete(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateCustomerStatus(
    int id,
    bool active,
  ) async {
    final db = await database;

    return await db.update(
      'customers',
      {
        'active': active ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, dynamic>?> getCustomerByUserId(
    String userId,
  ) async {
    final db = await database;

    final result = await db.query(
      'customers',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return result.first;
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
