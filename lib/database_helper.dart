import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
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
      version: 3,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
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
        bill_date INTEGER NOT NULL DEFAULT 7,
        amount REAL DEFAULT 0,
        total_amount REAL DEFAULT 0,
        paid_amount REAL DEFAULT 0,
        payment_date TEXT,
        due_amount REAL DEFAULT 0,
        active INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_customers_user_id
      ON customers(user_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_customers_bill_date
      ON customers(bill_date)
    ''');
  }

  Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // Version 2 থেকে 3-এ যাওয়ার সময়
    // পুরোনো ডেটা নষ্ট না করে প্রয়োজনীয় পরিবর্তন করা হবে।

    if (oldVersion < 3) {
      // bill_date কলাম না থাকলে তৈরি করা হবে।
      final columns = await db.rawQuery(
        'PRAGMA table_info(customers)',
      );

      final hasBillDate = columns.any(
        (column) => column['name'] == 'bill_date',
      );

      if (!hasBillDate) {
        await db.execute(
          'ALTER TABLE customers ADD COLUMN bill_date INTEGER DEFAULT 7',
        );
      }

      // পুরোনো bill_date_new থাকলে সেটার তথ্য
      // আসল bill_date-এ নেওয়া হবে।
      final hasBillDateNew = columns.any(
        (column) => column['name'] == 'bill_date_new',
      );

      if (hasBillDateNew) {
        await db.execute('''
          UPDATE customers
          SET bill_date =
            CASE
              WHEN bill_date_new = 14 THEN 14
              WHEN bill_date_new = 21 THEN 21
              ELSE 7
            END
        ''');
      }

      // যেসব ইউজারের due_amount ঠিকভাবে নেই,
      // তাদের bill - paid অনুযায়ী হিসাব করা হবে।
      await db.execute('''
        UPDATE customers
        SET due_amount =
          COALESCE(amount, 0) - COALESCE(paid_amount, 0)
      ''');

      // দ্রুত খোঁজার জন্য index
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_customers_user_id
        ON customers(user_id)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_customers_bill_date
        ON customers(bill_date)
      ''');
    }
  }

  Future<int> addCustomer(
    Map<String, dynamic> customer,
  ) async {
    final db = await database;

    return await db.insert(
      'customers',
      customer,
    );
  }

  Future<List<Map<String, dynamic>>> getCustomers() async {
    final db = await database;

    return await db.query(
      'customers',
      orderBy: 'id ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getCustomersByBillDate(
    int billDate,
  ) async {
    final db = await database;

    return await db.query(
      'customers',
      where: 'bill_date = ?',
      whereArgs: [billDate],
      orderBy: 'id ASC',
    );
  }

  Future<Map<String, double>> getBillDateSummary(
    int billDate,
  ) async {
    final db = await database;

    final result = await db.rawQuery('''
      SELECT
        COUNT(*) AS user_count,
        COALESCE(SUM(amount), 0) AS total_bill,
        COALESCE(SUM(paid_amount), 0) AS total_paid,
        COALESCE(SUM(due_amount), 0) AS total_due
      FROM customers
      WHERE bill_date = ?
    ''', [billDate]);

    final row = result.first;

    return {
      'user_count':
          (row['user_count'] as num?)?.toDouble() ?? 0,
      'total_bill':
          (row['total_bill'] as num?)?.toDouble() ?? 0,
      'total_paid':
          (row['total_paid'] as num?)?.toDouble() ?? 0,
      'total_due':
          (row['total_due'] as num?)?.toDouble() ?? 0,
    };
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
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
