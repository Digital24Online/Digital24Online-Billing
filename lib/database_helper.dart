import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  static Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = join(
      await getDatabasesPath(),
      'digital24_billing.db',
    );

    return openDatabase(
      dbPath,
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _create,
      onUpgrade: _upgrade,
    );
  }

  // ============================================================
  // DATABASE CREATE
  // ============================================================

  Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        mobile TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '',
        package_id INTEGER,
        package_name TEXT NOT NULL DEFAULT '',
        bill_date INTEGER NOT NULL DEFAULT 7,

        amount REAL NOT NULL DEFAULT 0,
        total_amount REAL NOT NULL DEFAULT 0,
        paid_amount REAL NOT NULL DEFAULT 0,
        due_amount REAL NOT NULL DEFAULT 0,
        payment_date TEXT NOT NULL DEFAULT '',

        status INTEGER NOT NULL DEFAULT 1,
        active INTEGER NOT NULL DEFAULT 1,

        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE packages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        speed TEXT NOT NULL DEFAULT '',
        price REAL NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE bills (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        billing_month TEXT NOT NULL,
        bill_date INTEGER NOT NULL DEFAULT 7,
        amount REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,

        UNIQUE(customer_id, billing_month),

        FOREIGN KEY(customer_id)
          REFERENCES customers(id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE staff (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        mobile TEXT NOT NULL DEFAULT '',
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        bill_id INTEGER,
        user_id TEXT NOT NULL DEFAULT '',
        amount REAL NOT NULL DEFAULT 0,
        payment_date TEXT NOT NULL,
        receipt_no TEXT NOT NULL UNIQUE,
        staff_id INTEGER,
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,

        FOREIGN KEY(customer_id)
          REFERENCES customers(id)
          ON DELETE CASCADE,

        FOREIGN KEY(bill_id)
          REFERENCES bills(id)
          ON DELETE SET NULL,

        FOREIGN KEY(staff_id)
          REFERENCES staff(id)
          ON DELETE SET NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_customers_bill_date '
      'ON customers(bill_date)',
    );

    await db.execute(
      'CREATE INDEX idx_payments_date '
      'ON payments(payment_date)',
    );

    await db.execute(
      'CREATE INDEX idx_payments_customer '
      'ON payments(customer_id)',
    );

    await db.execute(
      'CREATE INDEX idx_bills_month '
      'ON bills(billing_month)',
    );

    await db.execute(
      'CREATE INDEX idx_bills_customer '
      'ON bills(customer_id)',
    );
  }

  // ============================================================
  // DATABASE UPGRADE / MIGRATION
  // ============================================================

  Future<void> _upgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _migrateCustomers(db);
      await _createNewTablesIfMissing(db);
      await _createIndexes(db);
    }
  }

  Future<bool> _tableExists(
    Database db,
    String table,
  ) async {
    final result = await db.rawQuery(
      '''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
      AND name = ?
      LIMIT 1
      ''',
      [table],
    );

    return result.isNotEmpty;
  }

  Future<bool> _columnExists(
    Database db,
    String table,
    String column,
  ) async {
    final result = await db.rawQuery(
      'PRAGMA table_info($table)',
    );

    return result.any(
      (row) => row['name']?.toString() == column,
    );
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String columnDefinition,
  ) async {
    final columnName =
        columnDefinition.trim().split(' ').first;

    if (!await _columnExists(
      db,
      table,
      columnName,
    )) {
      await db.execute(
        'ALTER TABLE $table ADD COLUMN $columnDefinition',
      );
    }
  }

  Future<void> _migrateCustomers(Database db) async {
    if (!await _tableExists(db, 'customers')) {
      await db.execute('''
        CREATE TABLE customers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL UNIQUE,
          name TEXT NOT NULL,
          mobile TEXT NOT NULL DEFAULT '',
          address TEXT NOT NULL DEFAULT '',
          package_id INTEGER,
          package_name TEXT NOT NULL DEFAULT '',
          bill_date INTEGER NOT NULL DEFAULT 7,
          amount REAL NOT NULL DEFAULT 0,
          total_amount REAL NOT NULL DEFAULT 0,
          paid_amount REAL NOT NULL DEFAULT 0,
          due_amount REAL NOT NULL DEFAULT 0,
          payment_date TEXT NOT NULL DEFAULT '',
          status INTEGER NOT NULL DEFAULT 1,
          active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      return;
    }

    await _addColumnIfMissing(
      db,
      'customers',
      'address TEXT NOT NULL DEFAULT ""',
    );

    await _addColumnIfMissing(
      db,
      'customers',
      'package_id INTEGER',
    );

    await _addColumnIfMissing(
      db,
      'customers',
      'package_name TEXT NOT NULL DEFAULT ""',
    );

    await _addColumnIfMissing(
      db,
      'customers',
      'bill_date INTEGER NOT NULL DEFAULT 7',
    );

    await _addColumnIfMissing(
      db,
      'customers',
      'amount REAL NOT NULL DEFAULT 0',
    );

    await _addColumnIfMissing(
      db,
      'customers',
      'total_amount REAL NOT NULL DEFAULT 0',
    );

    await _addColumnIfMissing(
      db,
      'customers',
      'paid_amount REAL NOT NULL DEFAULT 0',
    );

    await _addColumnIfMissing(
      db,
      'customers',
      'due_amount REAL NOT NULL DEFAULT 0',
    );

    await _addColumnIfMissing(
      db,
      'customers',
      'payment_date TEXT NOT NULL DEFAULT ""',
    );

    await _addColumnIfMissing(
      db,
      'customers',
      'status INTEGER NOT NULL DEFAULT 1',
    );

    await _addColumnIfMissing(
      db,
      'customers',
      'active INTEGER NOT NULL DEFAULT 1',
    );

    await _addColumnIfMissing(
      db,
      'customers',
      'created_at TEXT NOT NULL DEFAULT ""',
    );

    await _addColumnIfMissing(
      db,
      'customers',
      'updated_at TEXT NOT NULL DEFAULT ""',
    );

    // পুরোনো active থাকলে status-এর সঙ্গে সামঞ্জস্য রাখা।
    await db.rawUpdate('''
      UPDATE customers
      SET status = COALESCE(active, 1)
      WHERE status IS NULL
    ''');

    await db.rawUpdate('''
      UPDATE customers
      SET active = COALESCE(status, 1)
      WHERE active IS NULL
    ''');

    await db.rawUpdate('''
      UPDATE customers
      SET total_amount = COALESCE(amount, 0)
      WHERE total_amount = 0
      AND amount IS NOT NULL
    ''');

    await db.rawUpdate('''
      UPDATE customers
      SET due_amount =
        MAX(
          COALESCE(amount, 0) -
          COALESCE(paid_amount, 0),
          0
        )
    ''');
  }

  Future<void> _createNewTablesIfMissing(
    Database db,
  ) async {
    if (!await _tableExists(db, 'packages')) {
      await db.execute('''
        CREATE TABLE packages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          speed TEXT NOT NULL DEFAULT '',
          price REAL NOT NULL DEFAULT 0,
          active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL
        )
      ''');
    }

    if (!await _tableExists(db, 'bills')) {
      await db.execute('''
        CREATE TABLE bills (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_id INTEGER NOT NULL,
          billing_month TEXT NOT NULL,
          bill_date INTEGER NOT NULL DEFAULT 7,
          amount REAL NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          UNIQUE(customer_id, billing_month),
          FOREIGN KEY(customer_id)
            REFERENCES customers(id)
            ON DELETE CASCADE
        )
      ''');
    }

    if (!await _tableExists(db, 'staff')) {
      await db.execute('''
        CREATE TABLE staff (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          mobile TEXT NOT NULL DEFAULT '',
          active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL
        )
      ''');
    }

    if (!await _tableExists(db, 'payments')) {
      await db.execute('''
        CREATE TABLE payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_id INTEGER NOT NULL,
          bill_id INTEGER,
          user_id TEXT NOT NULL DEFAULT '',
          amount REAL NOT NULL DEFAULT 0,
          payment_date TEXT NOT NULL,
          receipt_no TEXT NOT NULL UNIQUE,
          staff_id INTEGER,
          note TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,

          FOREIGN KEY(customer_id)
            REFERENCES customers(id)
            ON DELETE CASCADE,

          FOREIGN KEY(bill_id)
            REFERENCES bills(id)
            ON DELETE SET NULL,

          FOREIGN KEY(staff_id)
            REFERENCES staff(id)
            ON DELETE SET NULL
        )
      ''');
    }
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_bill_date '
      'ON customers(bill_date)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_payments_date '
      'ON payments(payment_date)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_payments_customer '
      'ON payments(customer_id)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_bills_month '
      'ON bills(billing_month)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_bills_customer '
      'ON bills(customer_id)',
    );
  }

  // ============================================================
  // CUSTOMERS
  // ============================================================

  Future<List<Map<String, dynamic>>> getCustomers({
    int? billDate,
    String search = '',
  }) async {
    final db = await database;

    final where = <String>[];
    final args = <dynamic>[];

    if (billDate != null) {
      where.add('c.bill_date = ?');
      args.add(billDate);
    }

    if (search.trim().isNotEmpty) {
      final q =
          '%${search.trim().toLowerCase()}%';

      where.add('''
        (
          LOWER(c.user_id) LIKE ?
          OR LOWER(c.name) LIKE ?
          OR c.mobile LIKE ?
          OR LOWER(c.package_name) LIKE ?
        )
      ''');

      args.addAll([q, q, q, q]);
    }

    final whereSql = where.isEmpty
        ? ''
        : 'WHERE ${where.join(' AND ')}';

    return db.rawQuery(
      '''
      SELECT
        c.*,

        COALESCE(
          (
            SELECT SUM(b.amount)
            FROM bills b
            WHERE b.customer_id = c.id
          ),
          c.amount,
          0
        ) AS total_bill,

        COALESCE(
          (
            SELECT SUM(p.amount)
            FROM payments p
            WHERE p.customer_id = c.id
          ),
          c.paid_amount,
          0
        ) AS total_paid,

        COALESCE(
          (
            SELECT MAX(p.payment_date)
            FROM payments p
            WHERE p.customer_id = c.id
          ),
          c.payment_date,
          ''
        ) AS latest_payment_date

      FROM customers c

      $whereSql

      ORDER BY c.user_id COLLATE NOCASE
      ''',
      args,
    );
  }

  Future<List<Map<String, dynamic>>>
      getCustomersByBillDate(
    int billDate,
  ) async {
    return getCustomers(
      billDate: billDate,
    );
  }

  Future<Map<String, dynamic>?> getCustomerByUserId(
    String userId,
  ) async {
    final db = await database;

    final result = await db.query(
      'customers',
      where: 'user_id = ?',
      whereArgs: [userId.trim()],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return result.first;
  }

  Future<int> addCustomer(
    Map<String, dynamic> data,
  ) async {
    final db = await database;

    final now =
        DateTime.now().toIso8601String();

    final values =
        Map<String, dynamic>.from(data);

    final bill =
        (values['amount'] as num?)
                ?.toDouble() ??
            0;

    final paid =
        (values['paid_amount'] as num?)
                ?.toDouble() ??
            0;

    values['amount'] = bill;
    values['total_amount'] =
        (values['total_amount'] as num?)
                ?.toDouble() ??
            bill;

    values['paid_amount'] = paid;

    values['due_amount'] =
        (values['due_amount'] as num?)
                ?.toDouble() ??
            (bill - paid < 0
                ? 0
                : bill - paid);

    values['payment_date'] =
        values['payment_date']?.toString() ?? '';

    values['status'] =
        values['status'] ?? 1;

    values['active'] =
        values['active'] ?? 1;

    values['address'] =
        values['address']?.toString() ?? '';

    values['package_id'] =
        values['package_id'];

    values['package_name'] =
        values['package_name']
                ?.toString() ??
            '';

    values['bill_date'] =
        values['bill_date'] ?? 7;

    values['created_at'] =
        values['created_at'] ?? now;

    values['updated_at'] =
        values['updated_at'] ?? now;

    final id = await db.insert(
      'customers',
      values,
      conflictAlgorithm:
          ConflictAlgorithm.abort,
    );

    // নতুন monthly billing structure-এ
    // বর্তমান মাসের bill তৈরি।
    await ensureBill(
      id,
      _currentMonth(),
      values['bill_date'] as int? ?? 7,
      bill,
    );

    return id;
  }

  Future<int> updateCustomer(
    int id,
    Map<String, dynamic> data,
  ) async {
    final db = await database;

    final values =
        Map<String, dynamic>.from(data);

    values['updated_at'] =
        DateTime.now().toIso8601String();

    final result = await db.update(
      'customers',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );

    // Customer-এর bill amount পরিবর্তন হলে
    // current month's bill-ও update করা হবে।
    if (values.containsKey('amount')) {
      final amount =
          (values['amount'] as num?)
                  ?.toDouble() ??
              0;

      await db.update(
        'bills',
        {'amount': amount},
        where:
            'customer_id = ? AND billing_month = ?',
        whereArgs: [
          id,
          _currentMonth(),
        ],
      );
    }

    return result;
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
        'status': active ? 1 : 0,
        'updated_at':
            DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> setCustomerStatus(
    int id,
    bool active,
  ) {
    return updateCustomerStatus(
      id,
      active,
    );
  }

  Future<int> deleteCustomer(
    int id,
  ) async {
    final db = await database;

    return db.delete(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ============================================================
  // PACKAGES
  // ============================================================

  Future<List<Map<String, dynamic>>>
      getPackages({
    bool activeOnly = false,
  }) async {
    final db = await database;

    return db.query(
      'packages',
      where: activeOnly
          ? 'active = 1'
          : null,
      orderBy:
          'name COLLATE NOCASE',
    );
  }

  Future<int> addPackage(
    String name,
    String speed,
    double price,
  ) async {
    final db = await database;

    return db.insert(
      'packages',
      {
        'name': name.trim(),
        'speed': speed.trim(),
        'price': price,
        'active': 1,
        'created_at':
            DateTime.now().toIso8601String(),
      },
      conflictAlgorithm:
          ConflictAlgorithm.abort,
    );
  }

  Future<int> updatePackage(
    int id,
    String name,
    String speed,
    double price,
  ) async {
    final db = await database;

    return db.update(
      'packages',
      {
        'name': name.trim(),
        'speed': speed.trim(),
        'price': price,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> setPackageActive(
    int id,
    bool active,
  ) async {
    final db = await database;

    return db.update(
      'packages',
      {'active': active ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ============================================================
  // STAFF
  // ============================================================

  Future<List<Map<String, dynamic>>>
      getStaff() async {
    final db = await database;

    return db.query(
      'staff',
      where: 'active = 1',
      orderBy:
          'name COLLATE NOCASE',
    );
  }

  Future<int> addStaff(
    String name,
    String mobile,
  ) async {
    final db = await database;

    return db.insert(
      'staff',
      {
        'name': name.trim(),
        'mobile': mobile.trim(),
        'active': 1,
        'created_at':
            DateTime.now().toIso8601String(),
      },
      conflictAlgorithm:
          ConflictAlgorithm.abort,
    );
  }

  Future<int> setStaffActive(
    int id,
    bool active,
  ) async {
    final db = await database;

    return db.update(
      'staff',
      {'active': active ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ============================================================
  // MONTHLY BILLING
  // ============================================================

  String _currentMonth() {
    final now = DateTime.now();

    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}';
  }

  Future<int> ensureBill(
    int customerId,
    String month,
    int billDate,
    double amount,
  ) async {
    final db = await database;

    final existing = await db.query(
      'bills',
      where:
          'customer_id = ? AND billing_month = ?',
      whereArgs: [
        customerId,
        month,
      ],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      return (existing.first['id'] as num)
          .toInt();
    }

    return db.insert(
      'bills',
      {
        'customer_id': customerId,
        'billing_month': month,
        'bill_date': billDate,
        'amount': amount,
        'created_at':
            DateTime.now().toIso8601String(),
      },
    );
  }
  
    Future<List<Map<String, dynamic>>> getBills(
    String month,
  ) async {
    final db = await database;

    return db.rawQuery(
      '''
      SELECT
        b.*,
        c.user_id,
        c.name,
        c.mobile,
        c.package_name,

        COALESCE(
          (
            SELECT SUM(p.amount)
            FROM payments p
            WHERE p.bill_id = b.id
          ),
          0
        ) AS paid

      FROM bills b

      JOIN customers c
        ON c.id = b.customer_id

      WHERE b.billing_month = ?

      ORDER BY c.user_id COLLATE NOCASE
      ''',
      [month],
    );
  }

  Future<List<Map<String, dynamic>>>
      getDueReport(
    String month,
  ) async {
    final db = await database;

    return db.rawQuery(
      '''
      SELECT
        b.*,
        c.user_id,
        c.name,
        c.mobile,
        c.package_name,

        COALESCE(
          (
            SELECT SUM(p.amount)
            FROM payments p
            WHERE p.bill_id = b.id
          ),
          0
        ) AS paid

      FROM bills b

      JOIN customers c
        ON c.id = b.customer_id

      WHERE b.billing_month = ?

      AND b.amount >
        COALESCE(
          (
            SELECT SUM(p.amount)
            FROM payments p
            WHERE p.bill_id = b.id
          ),
          0
        )

      ORDER BY c.user_id COLLATE NOCASE
      ''',
      [month],
    );
  }

  Future<Map<String, dynamic>> summary(
    String month,
  ) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT
        COALESCE(
          SUM(amount),
          0
        ) AS bill,

        (
          SELECT COALESCE(
            SUM(p.amount),
            0
          )
          FROM payments p

          JOIN bills b
            ON b.id = p.bill_id

          WHERE b.billing_month = ?
        ) AS paid,

        COUNT(*) AS bills

      FROM bills

      WHERE billing_month = ?
      ''',
      [
        month,
        month,
      ],
    );

    final row = result.first;

    final bill =
        (row['bill'] as num?)
                ?.toDouble() ??
            0;

    final paid =
        (row['paid'] as num?)
                ?.toDouble() ??
            0;

    return {
      ...row,
      'due': (bill - paid)
          .clamp(0, double.infinity),
    };
  }

  // ============================================================
  // PAYMENTS
  // ============================================================

  String _receiptNumber() {
    final now = DateTime.now();

    return 'D24-${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.millisecondsSinceEpoch}';
  }

  String _receipt() {
    return _receiptNumber();
  }

  // পুরোনো main.dart-এর জন্য compatibility method।
  Future<int> addPayment(
    Map<String, dynamic> data,
  ) async {
    final db = await database;

    final customerId =
        (data['customer_id'] as num?)
                ?.toInt();

    if (customerId == null) {
      throw Exception(
        'Customer ID পাওয়া যায়নি',
      );
    }

    final amount =
        (data['amount'] as num?)
                ?.toDouble() ??
            0;

    if (amount <= 0) {
      throw Exception(
        'Payment amount সঠিক নয়',
      );
    }

    final paymentDate =
        data['payment_date']
                ?.toString() ??
            _today();

    final billId =
        (data['bill_id'] as num?)
            ?.toInt();

    final staffId =
        (data['staff_id'] as num?)
            ?.toInt();

    final userId =
        data['user_id']
                ?.toString() ??
            '';

    final note =
        data['note']
                ?.toString() ??
            '';

    return db.transaction(
      (txn) async {
        int? actualBillId = billId;

        if (actualBillId == null) {
          final customer =
              await txn.query(
            'customers',
            where: 'id = ?',
            whereArgs: [customerId],
            limit: 1,
          );

          if (customer.isEmpty) {
            throw Exception(
              'Customer পাওয়া যায়নি',
            );
          }

          final customerRow =
              customer.first;

          final billDate =
              (customerRow['bill_date']
                          as num?)
                      ?.toInt() ??
                  7;

          final billAmount =
              (customerRow['amount']
                          as num?)
                      ?.toDouble() ??
                  0;

          final month =
              _monthFromDate(
            paymentDate,
          );

          final existing =
              await txn.query(
            'bills',
            where:
                'customer_id = ? AND billing_month = ?',
            whereArgs: [
              customerId,
              month,
            ],
            limit: 1,
          );

          if (existing.isNotEmpty) {
            actualBillId =
                (existing.first['id'] as num)
                    .toInt();
          } else {
            actualBillId =
                await txn.insert(
              'bills',
              {
                'customer_id':
                    customerId,
                'billing_month':
                    month,
                'bill_date':
                    billDate,
                'amount':
                    billAmount,
                'created_at':
                    DateTime.now()
                        .toIso8601String(),
              },
            );
          }
        }

        if (actualBillId != null) {
          final bill =
              await txn.query(
            'bills',
            where: 'id = ?',
            whereArgs: [
              actualBillId,
            ],
            limit: 1,
          );

          if (bill.isNotEmpty) {
            final paidResult =
                await txn.rawQuery(
              '''
              SELECT COALESCE(
                SUM(amount),
                0
              ) AS total
              FROM payments
              WHERE bill_id = ?
              ''',
              [actualBillId],
            );

            final alreadyPaid =
                (paidResult.first['total']
                            as num?)
                        ?.toDouble() ??
                    0;

            final billAmount =
                (bill.first['amount']
                            as num?)
                        ?.toDouble() ??
                    0;

            if (amount >
                billAmount -
                    alreadyPaid +
                    0.0001) {
              throw Exception(
                'Payment bill-এর বকেয়ার চেয়ে বেশি',
              );
            }
          }
        }

        final receiptNo =
            _receiptNumber();

        final paymentId =
            await txn.insert(
          'payments',
          {
            'customer_id':
                customerId,
            'bill_id':
                actualBillId,
            'user_id':
                userId,
            'amount':
                amount,
            'payment_date':
                paymentDate,
            'receipt_no':
                receiptNo,
            'staff_id':
                staffId,
            'note':
                note,
            'created_at':
                DateTime.now()
                    .toIso8601String(),
          },
        );

        // Legacy customer fields update।
        final paidResult =
            await txn.rawQuery(
          '''
          SELECT COALESCE(
            SUM(amount),
            0
          ) AS total
          FROM payments
          WHERE customer_id = ?
          ''',
          [customerId],
        );

        final totalPaid =
            (paidResult.first['total']
                        as num?)
                    ?.toDouble() ??
                0;

        final customerRows =
            await txn.query(
          'customers',
          where: 'id = ?',
          whereArgs: [customerId],
          limit: 1,
        );

        if (customerRows.isNotEmpty) {
          final customer =
              customerRows.first;

          final totalAmount =
              (customer['amount']
                          as num?)
                      ?.toDouble() ??
                  0;

          final due =
              totalAmount -
                  totalPaid;

          await txn.update(
            'customers',
            {
              'paid_amount':
                  totalPaid,
              'due_amount':
                  due < 0
                      ? 0
                      : due,
              'payment_date':
                  paymentDate,
              'updated_at':
                  DateTime.now()
                      .toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [customerId],
          );
        }

        return paymentId;
      },
    );
  }

  // নতুন named-parameter API।
  Future<int> addPaymentNew({
    required int customerId,
    int? billId,
    required double amount,
    required String date,
    int? staffId,
    String note = '',
  }) async {
    return addPayment({
      'customer_id':
          customerId,
      'bill_id':
          billId,
      'amount':
          amount,
      'payment_date':
          date,
      'staff_id':
          staffId,
      'note':
          note,
    });
  }

  Future<List<Map<String, dynamic>>>
      getPaymentHistory(
    int customerId, {
    int? billId,
  }) async {
    final db = await database;

    final args = <dynamic>[
      customerId,
    ];

    var billCondition = '';

    if (billId != null) {
      billCondition =
          'AND p.bill_id = ?';
      args.add(billId);
    }

    return db.rawQuery(
      '''
      SELECT
        p.*,
        s.name AS staff_name,
        b.billing_month,
        b.amount AS bill_amount

      FROM payments p

      LEFT JOIN staff s
        ON s.id = p.staff_id

      LEFT JOIN bills b
        ON b.id = p.bill_id

      WHERE p.customer_id = ?

      $billCondition

      ORDER BY
        p.payment_date DESC,
        p.id DESC
      ''',
      args,
    );
  }

  Future<List<Map<String, dynamic>>>
      getPaymentsByDate(
    String date,
  ) async {
    final db = await database;

    return db.rawQuery(
      '''
      SELECT
        p.*,
        c.user_id,
        c.name,
        c.mobile,
        s.name AS staff_name

      FROM payments p

      JOIN customers c
        ON c.id = p.customer_id

      LEFT JOIN staff s
        ON s.id = p.staff_id

      WHERE date(p.payment_date)
        = date(?)

      ORDER BY
        p.payment_date DESC,
        p.id DESC
      ''',
      [date],
    );
  }

  Future<Map<String, dynamic>>
      getPaymentSummary(
    String date,
  ) async {
    final db = await database;

    final result =
        await db.rawQuery(
      '''
      SELECT
        COALESCE(
          SUM(amount),
          0
        ) AS total,

        COUNT(*) AS payment_count

      FROM payments

      WHERE date(payment_date)
        = date(?)
      ''',
      [date],
    );

    return result.first;
  }

  Future<List<Map<String, dynamic>>>
      getPaymentsReport(
    String from,
    String to, {
    int? staffId,
  }) async {
    final db = await database;

    final args = <dynamic>[
      from,
      to,
    ];

    var staffCondition = '';

    if (staffId != null) {
      staffCondition =
          'AND p.staff_id = ?';
      args.add(staffId);
    }

    return db.rawQuery(
      '''
      SELECT
        p.*,
        c.user_id,
        c.name,
        c.mobile,
        s.name AS staff_name,
        b.billing_month

      FROM payments p

      JOIN customers c
        ON c.id = p.customer_id

      LEFT JOIN staff s
        ON s.id = p.staff_id

      LEFT JOIN bills b
        ON b.id = p.bill_id

      WHERE date(p.payment_date)
        BETWEEN date(?) AND date(?)

      $staffCondition

      ORDER BY
        p.payment_date DESC,
        p.id DESC
      ''',
      args,
    );
  }

  // ============================================================
  // RECEIPT LOOKUP
  // ============================================================

  Future<Map<String, dynamic>?>
      getPaymentByReceipt(
    String receiptNo,
  ) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT
        p.*,
        c.user_id,
        c.name,
        c.mobile,
        c.package_name,
        s.name AS staff_name,
        b.billing_month,
        b.amount AS bill_amount

      FROM payments p

      JOIN customers c
        ON c.id = p.customer_id

      LEFT JOIN staff s
        ON s.id = p.staff_id

      LEFT JOIN bills b
        ON b.id = p.bill_id

      WHERE p.receipt_no = ?

      LIMIT 1
      ''',
      [receiptNo],
    );

    if (result.isEmpty) {
      return null;
    }

    return result.first;
  }

  // ============================================================
  // BACKUP
  // ============================================================

  Future<String?> backupDatabase() async {
    final dbPath = join(
      await getDatabasesPath(),
      'digital24_billing.db',
    );

    final source =
        File(dbPath);

    if (!await source.exists()) {
      return null;
    }

    final backupPath = join(
      await getDatabasesPath(),
      'digital24_backup_'
          '${DateTime.now().millisecondsSinceEpoch}'
          '.db',
    );

    await source.copy(
      backupPath,
    );

    return backupPath;
  }

  // ============================================================
  // RESTORE
  // ============================================================

  Future<void> restoreDatabase() async {
    throw UnsupportedError(
      'Restore করার জন্য Backup file নির্বাচন করার '
      'UI এখনো main.dart-এ যুক্ত করা হয়নি।',
    );
  }

  // ============================================================
  // UTILITIES
  // ============================================================

  String _today() {
    final now =
        DateTime.now();

    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  String _monthFromDate(
    String date,
  ) {
    if (date.length >= 7) {
      return date.substring(0, 7);
    }

    return _currentMonth();
  }

  Future<void> closeDatabase() async {
    final db = _db;

    if (db != null) {
      await db.close();
      _db = null;
    }
  }
  }
