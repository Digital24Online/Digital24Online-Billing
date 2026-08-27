import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

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

    return openDatabase(
      path,
      version: 6,
      onConfigure: _onConfigure,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _createDB(Database db, int version) async {
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

    await _createIndexes(db);
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customers_user_id
      ON customers(user_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customers_bill_date
      ON customers(bill_date)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customers_active
      ON customers(active)
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
          created_at TEXT,
          FOREIGN KEY(customer_id)
            REFERENCES customers(id)
            ON DELETE CASCADE
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
          created_at TEXT,
          FOREIGN KEY(customer_id)
            REFERENCES customers(id)
            ON DELETE CASCADE
        )
      ''');
    }

    if (oldVersion < 6) {
      final columns = await db.rawQuery(
        'PRAGMA table_info(customers)',
      );

      final names = columns
          .map((e) => e['name'].toString())
          .toSet();

      if (!names.contains('active')) {
        await db.execute(
          'ALTER TABLE customers ADD COLUMN active INTEGER DEFAULT 1',
        );
      }

      await db.execute('''
        UPDATE customers
        SET active = 1
        WHERE active IS NULL
      ''');
    }

    await _createIndexes(db);
  }

  Future<int> addCustomer(
    Map<String, dynamic> customer,
  ) async {
    final db = await database;

    final data = Map<String, dynamic>.from(customer);

    data['created_at'] ??=
        DateTime.now().toIso8601String();

    data['active'] ??= 1;

    return db.insert('customers', data);
  }

  Future<List<Map<String, dynamic>>> getCustomers() async {
    final db = await database;

    return db.query(
      'customers',
      orderBy: 'id ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getCustomersByBillDate(
    int billDate,
  ) async {
    final db = await database;

    return db.query(
      'customers',
      where: 'bill_date = ?',
      whereArgs: [billDate],
      orderBy: 'id ASC',
    );
  }

  Future<List<Map<String, dynamic>>> searchCustomers(
    String keyword,
  ) async {
    final db = await database;

    final value = keyword.trim();

    if (value.isEmpty) {
      return getCustomers();
    }

    return db.query(
      'customers',
      where: '''
        user_id LIKE ?
        OR name LIKE ?
        OR mobile LIKE ?
        OR package_name LIKE ?
      ''',
      whereArgs: [
        '%$value%',
        '%$value%',
        '%$value%',
        '%$value%',
      ],
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

    return db.update(
      'customers',
      customer,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteCustomer(int id) async {
    final db = await database;

    return db.delete(
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

    return db.update(
      'customers',
      {
        'active': active ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> addPayment(
    Map<String, dynamic> payment,
  ) async {
    final db = await database;

    final data = Map<String, dynamic>.from(payment);

    data['created_at'] ??=
        DateTime.now().toIso8601String();

    return db.insert('payments', data);
  }

  Future<List<Map<String, dynamic>>> getPaymentHistory(
    int customerId,
  ) async {
    final db = await database;

    return db.query(
      'payments',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'id DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getPaymentsByDate(
    String date,
  ) async {
    final db = await database;

    return db.query(
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

  Future<int> addBill(
    Map<String, dynamic> bill,
  ) async {
    final db = await database;

    final data = Map<String, dynamic>.from(bill);

    data['created_at'] ??=
        DateTime.now().toIso8601String();

    return db.insert('bills', data);
  }

  Future<List<Map<String, dynamic>>> getCustomerBills(
    int customerId,
  ) async {
    final db = await database;

    return db.query(
      'bills',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'billing_month DESC',
    );
  }

  Future<String?> backupDatabase() async {
    final db = await database;

    final customers = await db.query('customers');
    final payments = await db.query('payments');
    final bills = await db.query('bills');

    final backupData = {
      'version': 6,
      'backup_date':
          DateTime.now().toIso8601String(),
      'customers': customers,
      'payments': payments,
      'bills': bills,
    };

    final jsonData = jsonEncode(backupData);

    return FilePicker.platform.saveFile(
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
      throw Exception('Backup ফাইল পড়া যাচ্ছে না');
    }

    final jsonData = utf8.decode(file.bytes!);
    final backupData = jsonDecode(jsonData);

    if (backupData is! Map ||
        backupData['customers'] is! List) {
      throw Exception('ভুল Backup ফাইল');
    }

    final db = await database;

    await db.transaction((txn) async {
      await txn.delete('payments');
      await txn.delete('bills');
      await txn.delete('customers');

      final customerIdMap = <int, int>{};

      final customers =
          (backupData['customers'] as List)
              .map(
                (item) =>
                    Map<String, dynamic>.from(item),
              )
              .toList();

      for (final customer in customers) {
        final oldId = customer['id'];

        customer.remove('id');

        final newId = await txn.insert(
          'customers',
          customer,
        );

        if (oldId is int) {
          customerIdMap[oldId] = newId;
        }
      }

      if (backupData['payments'] is List) {
        for (final item
            in backupData['payments'] as List) {
          final payment =
              Map<String, dynamic>.from(item);

          final oldCustomerId =
              payment['customer_id'];

          if (oldCustomerId is! int ||
              !customerIdMap.containsKey(
                oldCustomerId,
              )) {
            continue;
          }

          payment['customer_id'] =
              customerIdMap[oldCustomerId];

          payment.remove('id');

          await txn.insert(
            'payments',
            payment,
          );
        }
      }

      if (backupData['bills'] is List) {
        for (final item
            in backupData['bills'] as List) {
          final bill =
              Map<String, dynamic>.from(item);

          final oldCustomerId =
              bill['customer_id'];

          if (oldCustomerId is! int ||
              !customerIdMap.containsKey(
                oldCustomerId,
              )) {
            continue;
          }

          bill['customer_id'] =
              customerIdMap[oldCustomerId];

          bill.remove('id');

          await txn.insert(
            'bills',
            bill,
          );
        }
      }
    });
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
