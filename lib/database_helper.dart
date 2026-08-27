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
      version: 5,
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
        due_amount REAL DEFAULT 0,
        payment_date TEXT,
        active INTEGER DEFAULT 1,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        user_id TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_date TEXT NOT NULL,
        note TEXT,
        created_at TEXT,
        FOREIGN KEY(customer_id)
          REFERENCES customers(id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE bills (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        user_id TEXT NOT NULL,
        billing_month TEXT NOT NULL,
        bill_amount REAL NOT NULL,
        paid_amount REAL DEFAULT 0,
        due_amount REAL DEFAULT 0,
        status TEXT DEFAULT 'unpaid',
        created_at TEXT,
        FOREIGN KEY(customer_id)
          REFERENCES customers(id)
          ON DELETE CASCADE
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

    await db.execute('''
      CREATE INDEX idx_payments_customer_id
      ON payments(customer_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_payments_date
      ON payments(payment_date)
    ''');

    await db.execute('''
      CREATE INDEX idx_bills_customer_id
      ON bills(customer_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_bills_month
      ON bills(billing_month)
    ''');
  }

  Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 4) {
      final columns = await db.rawQuery(
        'PRAGMA table_info(customers)',
      );

      final names = columns
          .map((e) => e['name'].toString())
          .toSet();

      if (!names.contains('created_at')) {
        await db.execute(
          'ALTER TABLE customers ADD COLUMN created_at TEXT',
        );
      }
    }

    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_id INTEGER NOT NULL,
          user_id TEXT NOT NULL,
          amount REAL NOT NULL,
          payment_date TEXT NOT NULL,
          note TEXT,
          created_at TEXT
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS bills (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_id INTEGER NOT NULL,
          user_id TEXT NOT NULL,
          billing_month TEXT NOT NULL,
          bill_amount REAL NOT NULL,
          paid_amount REAL DEFAULT 0,
          due_amount REAL DEFAULT 0,
          status TEXT DEFAULT 'unpaid',
          created_at TEXT
        )
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_payments_customer_id
        ON payments(customer_id)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_payments_date
        ON payments(payment_date)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_bills_customer_id
        ON bills(customer_id)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_bills_month
        ON bills(billing_month)
      ''');
    }
  }

  Future<int> addCustomer(
    Map<String, dynamic> customer,
  ) async {
    final db = await database;

    final data = Map<String, dynamic>.from(customer);

    data['created_at'] ??=
        DateTime.now().toIso8601String();

    return await db.insert(
      'customers',
      data,
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

    return result.isEmpty ? null : result.first;
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

  
  Future<int> addBill(
    Map<String, dynamic> bill,
  ) async {
    final db = await database;

    return await db.insert(
      'bills',
      {
        ...bill,
        'created_at':
            DateTime.now().toIso8601String(),
      },
    );
  }

  Future<List<Map<String, dynamic>>> getCustomerBills(
    int customerId,
  ) async {
    final db = await database;

    return await db.query(
      'bills',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'billing_month DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getPaymentsByDate(
    String date,
  ) async {
    final db = await database;

    return await db.query(
      'payments',
      where: 'payment_date = ?',
      whereArgs: [date],
      orderBy: 'id DESC',
    );
  }

  Future<Map<String, double>> getPaymentSummary(
    String date,
  ) async {
    final db = await database;

    final result = await db.rawQuery('''
      SELECT
        COUNT(*) AS payment_count,
        COALESCE(SUM(amount), 0) AS total
      FROM payments
      WHERE payment_date = ?
    ''', [date]);

    final row = result.first;

    return {
      'payment_count':
          (row['payment_count'] as num?)?.toDouble() ?? 0,
      'total':
          (row['total'] as num?)?.toDouble() ?? 0,
    };
  }

  Future<String?> backupDatabase() async {
    final db = await database;

    final customers = await db.query('customers');
    final payments = await db.query('payments');
    final bills = await db.query('bills');

    final backupData = {
      'version': 5,
      'backup_date':
          DateTime.now().toIso8601String(),
      'customers': customers,
      'payments': payments,
      'bills': bills,
    };

    final jsonData = jsonEncode(backupData);

    return await FilePicker.platform.saveFile(
      dialogTitle: 'Database Backup সংরক্ষণ করুন',
      fileName: 'digital24_backup.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: utf8.encode(jsonData),
    );
  }

  Future<void> restoreDatabase() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Database Backup নির্বাচন করুন',
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );

    if (result == null) return;

    final file = result.files.single;

    if (file.bytes == null) {
      throw Exception(
        'Backup ফাইল পড়া যাচ্ছে না',
      );
    }

    final jsonData = utf8.decode(file.bytes!);
    final backupData = jsonDecode(jsonData);

    if (backupData is! Map ||
        backupData['customers'] is! List) {
      throw Exception(
        'ভুল Backup ফাইল',
      );
    }

    final db = await database;

    await db.transaction((txn) async {
      await txn.delete('payments');
      await txn.delete('bills');
      await txn.delete('customers');

      final customers =
          List<Map<String, dynamic>>.from(
        (backupData['customers'] as List).map(
          (item) =>
              Map<String, dynamic>.from(item),
        ),
      );

      for (final customer in customers) {
        final data =
            Map<String, dynamic>.from(customer);

        data.remove('id');

        await txn.insert(
          'customers',
          data,
        );
      }

      if (backupData['payments'] is List) {
        final payments =
            backupData['payments'] as List;

        for (final payment in payments) {
          final data =
              Map<String, dynamic>.from(
            payment,
          );

          data.remove('id');

          await txn.insert(
            'payments',
            data,
          );
        }
      }

      if (backupData['bills'] is List) {
        final bills =
            backupData['bills'] as List;

        for (final bill in bills) {
          final data =
              Map<String, dynamic>.from(
            bill,
          );

          data.remove('id');

          await txn.insert(
            'bills',
            data,
          );
        }
      }
    });
  }
  Future<int> addPayment(
    Map<String, dynamic> payment,
  ) async {
    final db = await database;

    return await db.insert(
      'payments',
      payment,
    );
  }

  Future<List<Map<String, dynamic>>> getPaymentHistory(
    int customerId,
  ) async {
    final db = await database;

    return await db.query(
      'payments',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'id DESC',
    );
  }
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
