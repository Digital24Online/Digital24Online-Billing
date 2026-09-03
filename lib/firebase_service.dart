import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// Digital 24 Online Billing - Firebase/Firestore sync service.
///
/// SQLite remains the offline working database.
/// Firestore is the cloud master for multi-device sync and recovery.
///
/// Important:
/// - Every local entity keeps its own updated_at.
/// - Customer totals are recalculated from bills/payments after sync.
/// - Recalculated customer totals are then pushed back to Firestore.
/// - Payment documents use receipt_no as their stable identity.
/// - Online payment upload uses a Firestore transaction against the bill
///   document, so concurrent online uploads cannot silently exceed the bill.
/// - Offline devices can still create conflicting payments while disconnected;
///   no client-only solution can make two disconnected devices globally
///   atomic. Such conflicts must be resolved when they reconnect.
class FirebaseService {
  FirebaseService._() {
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (user == null) {
        _stopAutoSync();
      } else {
        _startAutoSync();
        Future<void>.delayed(const Duration(seconds: 3), () async {
          if (!isSignedIn) return;
          try {
            await syncNow();
          } catch (_) {}
        });
      }
    });
  }

  static final FirebaseService instance = FirebaseService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void>? _syncInProgress;
  Timer? _autoSyncTimer;
  StreamSubscription<User?>? _authSubscription;

  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentUser != null;
  String? get uid => _auth.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> get _businessRef {
    final id = _auth.currentUser?.uid;
    if (id == null || id.isEmpty) {
      throw StateError('User is not signed in.');
    }
    return _firestore.collection('businesses').doc(id);
  }

  CollectionReference<Map<String, dynamic>> _collection(String name) =>
      _businessRef.collection(name);

  // ---------------------------------------------------------------------------
  // AUTH
  // ---------------------------------------------------------------------------

  Future<UserCredential> createAccount({
    required String email,
    required String password,
  }) async {
    final result = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    try {
      await _ensureBusinessDocument();
    } catch (_) {}
    return result;
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    final result = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    try {
      await _ensureBusinessDocument();
    } catch (_) {}
    return result;
  }

  Future<void> signOut() async {
    _stopAutoSync();
    await _auth.signOut();
  }

  Future<void> sendPasswordResetEmail(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  // ---------------------------------------------------------------------------
  // AUTO SYNC / CLOUD
  // ---------------------------------------------------------------------------

  void _startAutoSync() {
    if (_autoSyncTimer != null) return;

    _autoSyncTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (!isSignedIn) return;
      try {
        await syncNow();
      } catch (_) {}
    });
  }

  void _stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  Future<void> _ensureBusinessDocument() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _businessRef.set(
      {
        'uid': user.uid,
        'email': user.email ?? '',
        'company_name': 'Digital 24 Online Billing',
        'address':
            'Seroil Colony, 4 No. Road, Ghoramara, Chandrima Rajshahi-6100',
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<bool> cloudAvailable() async {
    if (!isSignedIn) return false;
    try {
      await _businessRef.get(
        const GetOptions(source: Source.server),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // PUBLIC SYNC API
  // ---------------------------------------------------------------------------

  Future<void> restoreAfterLogin() async {
    if (!isSignedIn) return;

    try {
      await _ensureBusinessDocument();

      final db = await DatabaseHelper.instance.database;
      final freshInstall = await _isFreshInstall(db);

      // Never let the six locally seeded packages overwrite a real cloud
      // package configuration on a fresh installation.
      if (freshInstall && await _hasOnlyDefaultPackages(db)) {
        await db.delete('packages');
      }

      if (freshInstall) {
        // On a genuinely empty installation, restore cloud master data first.
        await _pullCloudToLocal(db);

        // If the cloud account is empty, create the standard packages locally
        // and then publish them.
        if (await _count(db, 'packages') == 0) {
          await _seedDefaultPackages(db);
          await _mergePackages(db);
        }

        await _repairLocalRelations(db);
        await _recalculateAllCustomerTotals(db);
        await _pushRecalculatedCustomers(db);
        return;
      }

      await syncNow();
    } catch (_) {
      // Offline use must continue even when cloud recovery is unavailable.
    }
  }

  Future<void> syncNow() async {
    final running = _syncInProgress;
    if (running != null) return running;

    final future = _syncNowInternal();
    _syncInProgress = future;

    try {
      await future;
    } finally {
      if (identical(_syncInProgress, future)) {
        _syncInProgress = null;
      }
    }
  }

  Future<void> _syncNowInternal() async {
    if (!isSignedIn) {
      throw StateError('Please sign in first.');
    }

    await _ensureBusinessDocument();
    final db = await DatabaseHelper.instance.database;

    await _mergeCustomers(db);
    await _mergePackages(db);
    await _mergeStaff(db);
    await _mergeBills(db);
    await _mergePayments(db);

    await _repairLocalRelations(db);
    await _recalculateAllCustomerTotals(db);

    // The recalculation changes customer totals locally. Push those values
    // after the recalculation so Firestore does not keep stale totals.
    await _pushRecalculatedCustomers(db);
  }

  Future<bool> _isFreshInstall(Database db) async {
    final customers = await _count(db, 'customers');
    final bills = await _count(db, 'bills');
    final payments = await _count(db, 'payments');
    final staff = await _count(db, 'staff');

    return customers == 0 &&
        bills == 0 &&
        payments == 0 &&
        staff == 0;
  }

  Future<bool> _businessDataIsEmpty(Database db) async {
    return await _count(db, 'customers') == 0 &&
        await _count(db, 'bills') == 0 &&
        await _count(db, 'payments') == 0 &&
        await _count(db, 'staff') == 0;
  }

  Future<int> _count(Database db, String table) async {
    final result = await db.rawQuery('SELECT COUNT(*) AS total FROM $table');
    return _int(result.isEmpty ? 0 : result.first['total']);
  }

  Future<bool> _hasOnlyDefaultPackages(Database db) async {
    final rows = await db.query(
      'packages',
      columns: ['name', 'speed', 'price'],
      orderBy: 'name ASC',
    );

    final expected = <String, double>{
      '35 Mbps': 500,
      '45 Mbps': 600,
      '60 Mbps': 800,
      '75 Mbps': 1000,
      '85 Mbps': 1200,
      '100 Mbps': 1500,
    };

    if (rows.length != expected.length) return false;

    for (final row in rows) {
      final name = _string(row['name']).trim();
      final speed = _string(row['speed']).trim();
      final price = _double(row['price']);

      if (!expected.containsKey(name)) return false;
      if (speed != name) return false;
      if (price != expected[name]) return false;
    }

    return true;
  }

  Future<void> _seedDefaultPackages(Database db) async {
    final now = DateTime.now().toIso8601String();
    final defaults = <Map<String, dynamic>>[
      {'name': '35 Mbps', 'speed': '35 Mbps', 'price': 500.0},
      {'name': '45 Mbps', 'speed': '45 Mbps', 'price': 600.0},
      {'name': '60 Mbps', 'speed': '60 Mbps', 'price': 800.0},
      {'name': '75 Mbps', 'speed': '75 Mbps', 'price': 1000.0},
      {'name': '85 Mbps', 'speed': '85 Mbps', 'price': 1200.0},
      {'name': '100 Mbps', 'speed': '100 Mbps', 'price': 1500.0},
    ];

    for (final p in defaults) {
      await db.insert(
        'packages',
        {
          ...p,
          'active': 1,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // FRESH INSTALL: CLOUD -> LOCAL
  // ---------------------------------------------------------------------------

  Future<void> _pullCloudToLocal(Database db) async {
    final customers = await _readCollection('customers');
    final packages = await _readCollection('packages');
    final staff = await _readCollection('staff');
    final bills = await _readCollection('bills');
    final payments = await _readCollection('payments');

    for (final row in packages) {
      await _upsertPackage(db, row);
    }

    for (final row in staff) {
      await _upsertStaff(db, row);
    }

    for (final row in customers) {
      await _upsertCustomer(db, row);
    }

    for (final row in bills) {
      await _upsertBill(db, row);
    }

    for (final row in payments) {
      await _upsertPayment(db, row);
    }
  }

  // ---------------------------------------------------------------------------
  // CUSTOMERS
  // ---------------------------------------------------------------------------

  Future<void> _mergeCustomers(Database db) async {
    final local = await db.query('customers');
    final cloud = await _readCollection('customers');

    final cloudByKey = <String, Map<String, dynamic>>{};
    for (final row in cloud) {
      final key = _string(row['user_id']).trim();
      if (key.isNotEmpty) cloudByKey[key] = row;
    }

    for (final row in local) {
      final key = _string(row['user_id']).trim();
      if (key.isEmpty) continue;

      final remote = cloudByKey[key];
      if (remote == null || _localIsNewer(row, remote)) {
        await _setCloud('customers', key, _customerToCloud(row));
      }
    }

    final merged = await _readCollection('customers');
    for (final row in merged) {
      await _upsertCustomer(db, row);
    }
  }

  Map<String, dynamic> _customerToCloud(Map<String, dynamic> r) => {
        'user_id': _string(r['user_id']),
        'name': _string(r['name']),
        'mobile': _string(r['mobile']),
        'address': _string(r['address']),
        'package_name': _string(r['package_name']),
        'bill_date': _int(r['bill_date'], fallback: 7),
        'amount': _double(r['amount']),
        'total_amount': _double(r['total_amount']),
        'paid_amount': _double(r['paid_amount']),
        'due_amount': _double(r['due_amount']),
        'payment_date': _string(r['payment_date']),
        'status': _int(r['status'], fallback: 1),
        'active': _int(r['active'], fallback: 1),
        'created_at': _string(r['created_at']),
        'updated_at': _string(r['updated_at']),
        'id_local': _int(r['id']),
        'cloud_updated_at': FieldValue.serverTimestamp(),
      };

  Future<void> _upsertCustomer(
    Database db,
    Map<String, dynamic> r,
  ) async {
    final userId = _string(r['user_id']).trim();
    if (userId.isEmpty) return;

    final values = {
      'user_id': userId,
      'name': _string(r['name']),
      'mobile': _string(r['mobile']),
      'address': _string(r['address']),
      'package_name': _string(r['package_name']),
      'bill_date': _int(r['bill_date'], fallback: 7),
      'amount': _double(r['amount']),
      'total_amount': _double(r['total_amount']),
      'paid_amount': _double(r['paid_amount']),
      'due_amount': _double(r['due_amount']),
      'payment_date': _string(r['payment_date']),
      'status': _int(r['status'], fallback: 1),
      'active': _int(r['active'], fallback: 1),
      'created_at': _string(r['created_at']),
      'updated_at': _string(r['updated_at']),
    };

    final found = await db.query(
      'customers',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (found.isEmpty) {
      await db.insert(
        'customers',
        values,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } else if (_remoteIsNewer(found.first, r)) {
      await db.update(
        'customers',
        values,
        where: 'id = ?',
        whereArgs: [found.first['id']],
      );
    }
  }

  // ---------------------------------------------------------------------------
  // PACKAGES
  // ---------------------------------------------------------------------------

  Future<void> _mergePackages(Database db) async {
    final local = await db.query('packages');
    final cloud = await _readCollection('packages');

    final byName = <String, Map<String, dynamic>>{};
    for (final row in cloud) {
      final name = _string(row['name']).trim();
      if (name.isNotEmpty) byName[name] = row;
    }

    for (final row in local) {
      final name = _string(row['name']).trim();
      if (name.isEmpty) continue;

      final remote = byName[name];
      if (remote == null || _localIsNewer(row, remote)) {
        await _setCloud('packages', _key(name), _packageToCloud(row));
      }
    }

    final merged = await _readCollection('packages');
    for (final row in merged) {
      await _upsertPackage(db, row);
    }
  }

  Map<String, dynamic> _packageToCloud(Map<String, dynamic> r) => {
        'name': _string(r['name']),
        'speed': _string(r['speed']),
        'price': _double(r['price']),
        'active': _int(r['active'], fallback: 1),
        'created_at': _string(r['created_at']),
        'updated_at': _string(r['updated_at']),
        'id_local': _int(r['id']),
        'cloud_updated_at': FieldValue.serverTimestamp(),
      };

  Future<void> _upsertPackage(
    Database db,
    Map<String, dynamic> r,
  ) async {
    final name = _string(r['name']).trim();
    if (name.isEmpty) return;

    final values = {
      'name': name,
      'speed': _string(r['speed']),
      'price': _double(r['price']),
      'active': _int(r['active'], fallback: 1),
      'created_at': _string(r['created_at']),
      'updated_at': _string(r['updated_at']),
    };

    final found = await db.query(
      'packages',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );

    if (found.isEmpty) {
      await db.insert(
        'packages',
        values,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } else if (_remoteIsNewer(found.first, r)) {
      await db.update(
        'packages',
        values,
        where: 'id = ?',
        whereArgs: [found.first['id']],
      );
    }
  }

  // ---------------------------------------------------------------------------
  // STAFF
  // ---------------------------------------------------------------------------

  Future<void> _mergeStaff(Database db) async {
    final local = await db.query('staff');
    final cloud = await _readCollection('staff');

    final byName = <String, Map<String, dynamic>>{};
    for (final row in cloud) {
      final name = _string(row['name']).trim();
      if (name.isNotEmpty) byName[name] = row;
    }

    for (final row in local) {
      final name = _string(row['name']).trim();
      if (name.isEmpty) continue;

      final remote = byName[name];
      final documentId = remote == null
          ? _key(name)
          : _string(remote['_doc_id']).trim().isNotEmpty
              ? _string(remote['_doc_id']).trim()
              : _key(name);

      if (remote == null || _localIsNewer(row, remote)) {
        await _setCloud(
          'staff',
          documentId,
          _staffToCloud(row),
        );
      }
    }

    final merged = await _readCollection('staff');
    for (final row in merged) {
      await _upsertStaff(db, row);
    }
  }

  Map<String, dynamic> _staffToCloud(Map<String, dynamic> r) => {
        'name': _string(r['name']),
        'mobile': _string(r['mobile']),
        'active': _int(r['active'], fallback: 1),
        'created_at': _string(r['created_at']),
        'updated_at': _string(r['updated_at']),
        'id_local': _int(r['id']),
        'cloud_updated_at': FieldValue.serverTimestamp(),
      };

  Future<void> _upsertStaff(
    Database db,
    Map<String, dynamic> r,
  ) async {
    final name = _string(r['name']).trim();
    if (name.isEmpty) return;

    final values = {
      'name': name,
      'mobile': _string(r['mobile']),
      'active': _int(r['active'], fallback: 1),
      'created_at': _string(r['created_at']),
      'updated_at': _string(r['updated_at']),
    };

    final found = await db.query(
      'staff',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );

    if (found.isEmpty) {
      await db.insert(
        'staff',
        values,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } else if (_remoteIsNewer(found.first, r)) {
      await db.update(
        'staff',
        values,
        where: 'id = ?',
        whereArgs: [found.first['id']],
      );
    }
  }

  // ---------------------------------------------------------------------------
  // BILLS
  // ---------------------------------------------------------------------------

  Future<void> _mergeBills(Database db) async {
    final local = await db.query('bills');
    final customers = await db.query(
      'customers',
      columns: ['id', 'user_id'],
    );
    final cloud = await _readCollection('bills');

    final userById = <int, String>{
      for (final c in customers) _int(c['id']): _string(c['user_id'])
    };

    for (final row in local) {
      final customerUserId = userById[_int(row['customer_id'])] ?? '';
      final month = _string(row['billing_month']).trim();

      if (customerUserId.isEmpty || month.isEmpty) continue;

      final key = '${customerUserId}__$month';
      Map<String, dynamic>? remote;

      for (final item in cloud) {
        if (_string(item['customer_user_id']).trim() == customerUserId &&
            _string(item['billing_month']).trim() == month) {
          remote = item;
          break;
        }
      }

      if (remote == null || _localIsNewer(row, remote)) {
        await _setCloud(
          'bills',
          _key(key),
          _billToCloud(row, customerUserId),
        );
      }
    }

    final merged = await _readCollection('bills');
    for (final row in merged) {
      await _upsertBill(db, row);
    }

    // Initialize the server-side balance guard for each bill. This is done
    // before payment uploads so online concurrent payments can be checked
    // atomically against one shared paid_total value.
    await _initializeBillBalances(merged);
  }

  Future<void> _initializeBillBalances(
    List<Map<String, dynamic>> bills,
  ) async {
    final payments = await _readCollection('payments');

    for (final bill in bills) {
      final customerUserId = _string(bill['customer_user_id']).trim();
      final month = _string(bill['billing_month']).trim();

      if (customerUserId.isEmpty || month.isEmpty) continue;

      final billKey = _key('${customerUserId}__$month');
            final balanceRef = _collection('bill_balances').doc(billKey);
      final existing = await balanceRef.get();

      if (existing.exists) continue;

      double paidTotal = 0;
      for (final payment in payments) {
        if (_string(payment['customer_user_id']).trim() ==
                customerUserId &&
            _string(payment['billing_month']).trim() == month) {
          paidTotal += _double(payment['amount']);
        }
      }

      await balanceRef.set(
        {
          'customer_user_id': customerUserId,
          'billing_month': month,
          'bill_amount': _double(bill['amount']),
          'paid_total': paidTotal,
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await _collection('bills').doc(billKey).set(
        {
          'paid_total': paidTotal,
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
  }

  Map<String, dynamic> _billToCloud(
    Map<String, dynamic> r,
    String customerUserId,
  ) =>
      {
        'customer_user_id': customerUserId,
        'billing_month': _string(r['billing_month']),
        'bill_date': _int(r['bill_date'], fallback: 7),
        'amount': _double(r['amount']),
        'created_at': _string(r['created_at']),
        'updated_at': _string(r['updated_at']),
        'id_local': _int(r['id']),
        'cloud_updated_at': FieldValue.serverTimestamp(),
      };

  Future<void> _upsertBill(
    Database db,
    Map<String, dynamic> r,
  ) async {
    final userId = _string(r['customer_user_id']).trim();
    final month = _string(r['billing_month']).trim();

    if (userId.isEmpty || month.isEmpty) return;

    final customers = await db.query(
      'customers',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (customers.isEmpty) return;

    final customerId = _int(customers.first['id']);

    final values = {
      'customer_id': customerId,
      'billing_month': month,
      'bill_date': _int(r['bill_date'], fallback: 7),
      'amount': _double(r['amount']),
      'created_at': _string(r['created_at']),
      'updated_at': _string(r['updated_at']),
    };
    
    final found = await db.query(
      'bills',
      where: 'customer_id = ? AND billing_month = ?',
      whereArgs: [customerId, month],
      limit: 1,
    );

    if (found.isEmpty) {
      await db.insert(
        'bills',
        values,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } else if (_remoteIsNewer(found.first, r)) {
      await db.update(
        'bills',
        values,
        where: 'id = ?',
        whereArgs: [found.first['id']],
      );
    }
  }

  // ---------------------------------------------------------------------------
  // PAYMENTS
  // ---------------------------------------------------------------------------

  Future<void> _mergePayments(Database db) async {
    final local = await db.query('payments');
    final cloud = await _readCollection('payments');

    final customers = await db.query(
      'customers',
      columns: ['id', 'user_id'],
    );

    final userById = <int, String>{
      for (final c in customers) _int(c['id']): _string(c['user_id'])
    };

    final cloudByReceipt = <String, Map<String, dynamic>>{};
    for (final row in cloud) {
      final receipt = _string(row['receipt_no']).trim();
      if (receipt.isNotEmpty) cloudByReceipt[receipt] = row;
    }

    for (final row in local) {
      final receipt = _string(row['receipt_no']).trim();
      final customerUserId = userById[_int(row['customer_id'])] ?? '';

      if (receipt.isEmpty || customerUserId.isEmpty) continue;

      final remote = cloudByReceipt[receipt];

      if (remote == null) {
        final uploaded = await _tryUploadPaymentAtomically(
          db,
          row,
          customerUserId,
        );

        // If the cloud bill rejects an overpayment, retain the local record
        // instead of silently deleting money data. It will be visible locally
        // until an operator resolves the conflict.
        if (!uploaded) continue;
      } else if (_localIsNewer(row, remote)) {
        await _setCloud(
          'payments',
          _key(receipt),
          await _paymentToCloud(db, row, customerUserId),
        );
      }
    }

    final merged = await _readCollection('payments');
    for (final row in merged) {
      await _upsertPayment(db, row);
    }
  }
  
  Future<bool> _tryUploadPaymentAtomically(
    Database db,
    Map<String, dynamic> row,
    String customerUserId,
  ) async {
    final receipt = _string(row['receipt_no']).trim();
    if (receipt.isEmpty) return false;

    final month = await _paymentBillingMonth(db, row);
    if (month.isEmpty) return false;

    final billKey = _key('${customerUserId}__$month');
    final billRef = _collection('bills').doc(billKey);
    final balanceRef = _collection('bill_balances').doc(billKey);
    final paymentRef = _collection('payments').doc(_key(receipt));
    final amount = _double(row['amount']);

    if (amount <= 0) return false;

    try {
      await _firestore.runTransaction<void>((transaction) async {
        final billSnapshot = await transaction.get(billRef);
        final balanceSnapshot = await transaction.get(balanceRef);
        final paymentSnapshot = await transaction.get(paymentRef);

        if (paymentSnapshot.exists) return;

        if (!billSnapshot.exists) {
          throw StateError('Cloud bill not found for payment $receipt.');
        }

        // The balance document is created during bill synchronization.
        // Refuse an uninitialized balance instead of guessing the paid total.
        if (!balanceSnapshot.exists) {
          throw StateError(
            'Cloud bill balance is not initialized for $billKey.',
          );
        }

        final billData = billSnapshot.data() ?? <String, dynamic>{};
        final balanceData = balanceSnapshot.data() ?? <String, dynamic>{};

        final billAmount = _double(billData['amount']);
        final cloudPaid = _double(balanceData['paid_total']);

        if (cloudPaid + amount > billAmount + 0.000001) {
          throw StateError(
            'Payment conflict: bill already has enough payment.',
          );
        }

        transaction.set(
          paymentRef,
          await _paymentToCloud(db, row, customerUserId),
          SetOptions(merge: true),
        );

        transaction.set(
          balanceRef,
          {
            'customer_user_id': customerUserId,
            'billing_month': month,
            'bill_amount': billAmount,
            'paid_total': cloudPaid + amount,
            'updated_at': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        transaction.set(
          billRef,
          {
            'paid_total': cloudPaid + amount,
            'updated_at': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });

      return true;
    } catch (_) {
      return false;
    }
  }
  
  Future<String> _paymentBillingMonth(
    Database db,
    Map<String, dynamic> payment,
  ) async {
    final billId = payment['bill_id'];

    if (billId != null) {
      final bills = await db.query(
        'bills',
        columns: ['billing_month'],
        where: 'id = ?',
        whereArgs: [billId],
        limit: 1,
      );

      if (bills.isNotEmpty) {
        final month = _string(bills.first['billing_month']).trim();
        if (month.isNotEmpty) return month;
      }
    }

    final month = _string(payment['billing_month']).trim();
    if (month.isNotEmpty) return month;

    final date = _string(payment['payment_date']);
    if (date.length >= 7) return date.substring(0, 7);

    return '';
  }

  Future<Map<String, dynamic>> _paymentToCloud(
    Database db,
    Map<String, dynamic> r,
    String customerUserId,
  ) async {
    String staffName = '';
    final staffId = r['staff_id'];

    if (staffId != null) {
      final staff = await db.query(
        'staff',
        where: 'id = ?',
        whereArgs: [staffId],
        limit: 1,
      );
      if (staff.isNotEmpty) {
        staffName = _string(staff.first['name']);
      }
    }

    final billingMonth = await _paymentBillingMonth(db, r);

    return {
      'receipt_no': _string(r['receipt_no']),
      'customer_user_id': customerUserId,
      'billing_month': billingMonth,
      'amount': _double(r['amount']),
      'payment_date': _string(r['payment_date']),
      'staff_name': staffName,
      'note': _string(r['note']),
      'created_at': _string(r['created_at']),
      'updated_at': _string(r['updated_at']),
      'id_local': _int(r['id']),
      'cloud_updated_at': FieldValue.serverTimestamp(),
    };
  }

  Future<void> _upsertPayment(
    Database db,
    Map<String, dynamic> r,
  ) async {
    final receipt = _string(r['receipt_no']).trim();
    final userId = _string(r['customer_user_id']).trim();

    if (receipt.isEmpty || userId.isEmpty) return;

    final customers = await db.query(
      'customers',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (customers.isEmpty) return;

    final customerId = _int(customers.first['id']);
    final billId = await _findOrCreateBillForPayment(
      db,
      customerId,
      r,
    );
    if (billId == null) return;

    final staffId = await _findStaffId(
      db,
      _string(r['staff_name']),
    );
    
    final values = {
      'customer_id': customerId,
      'bill_id': billId,
      'user_id': userId,
      'amount': _double(r['amount']),
      'payment_date': _string(r['payment_date']),
      'receipt_no': receipt,
      'staff_id': staffId,
      'note': _string(r['note']),
      'created_at': _string(r['created_at']),
      'updated_at': _string(r['updated_at']),
    };

    final found = await db.query(
      'payments',
      where: 'receipt_no = ?',
      whereArgs: [receipt],
      limit: 1,
    );

    if (found.isEmpty) {
      await db.insert(
        'payments',
        values,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } else if (_remoteIsNewer(found.first, r)) {
      await db.update(
        'payments',
        values,
        where: 'id = ?',
        whereArgs: [found.first['id']],
      );
    }
  }

  Future<int?> _findOrCreateBillForPayment(
    Database db,
    int customerId,
    Map<String, dynamic> payment,
  ) async {
    final month = await _paymentBillingMonth(db, payment);
    if (month.isEmpty) return null;

    final existing = await db.query(
      'bills',
      where: 'customer_id = ? AND billing_month = ?',
      whereArgs: [customerId, month],
      limit: 1,
    );

    if (existing.isNotEmpty) return _int(existing.first['id']);

    final customer = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (customer.isEmpty) return null;

    final now = DateTime.now().toIso8601String();

    return db.insert(
      'bills',
      {
        'customer_id': customerId,
        'billing_month': month,
        'bill_date': _int(customer.first['bill_date'], fallback: 7),
        'amount': _double(customer.first['amount']),
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int?> _findStaffId(Database db, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return null;

    final rows = await db.query(
      'staff',
      where: 'name = ?',
      whereArgs: [clean],
      limit: 1,
    );

    return rows.isEmpty ? null : _int(rows.first['id']);
  }

  // ---------------------------------------------------------------------------
  // RELATIONS / TOTALS
  // ---------------------------------------------------------------------------

  Future<void> _repairLocalRelations(Database db) async {
    final customers = await db.query(
      'customers',
      columns: ['id', 'package_id', 'package_name'],
    );
    
    for (final row in customers) {
      final id = _int(row['id']);
      final packageName = _string(row['package_name']).trim();

      if (id <= 0 || packageName.isEmpty) continue;

      final package = await db.query(
        'packages',
        columns: ['id'],
        where: 'name = ?',
        whereArgs: [packageName],
        limit: 1,
      );

      if (package.isEmpty) continue;

      final packageId = _int(package.first['id']);

      if (_int(row['package_id']) != packageId) {
        final now = DateTime.now().toIso8601String();

        await db.update(
          'customers',
          {
            'package_id': packageId,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
  }

  Future<void> _recalculateAllCustomerTotals(Database db) async {
    final customers = await db.query(
      'customers',
      columns: ['id', 'amount'],
    );

    for (final customer in customers) {
      final id = _int(customer['id']);
      
      final bill = await db.rawQuery(
        'SELECT COALESCE(SUM(amount),0) AS total '
        'FROM bills WHERE customer_id = ?',
        [id],
      );

      final paid = await db.rawQuery(
        'SELECT COALESCE(SUM(amount),0) AS total '
        'FROM payments WHERE customer_id = ?',
        [id],
      );

      final totalBill = _double(
        bill.isEmpty ? 0 : bill.first['total'],
        fallback: _double(customer['amount']),
      );
      final totalPaid = _double(
        paid.isEmpty ? 0 : paid.first['total'],
      );

      final due = totalBill - totalPaid;
      final latestPaymentDate = await _latestPaymentDate(db, id);
      final now = DateTime.now().toIso8601String();

      await db.update(
        'customers',
        {
          'total_amount': totalBill,
          'paid_amount': totalPaid,
          'due_amount': due > 0 ? due : 0,
          'payment_date': latestPaymentDate,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> _pushRecalculatedCustomers(Database db) async {
    final rows = await db.query('customers');

    for (final row in rows) {
      final userId = _string(row['user_id']).trim();
      if (userId.isEmpty) continue;

      await _setCloud(
        'customers',
        userId,
        _customerToCloud(row),
      );
    }
  }

  Future<String> _latestPaymentDate(
    Database db,
    int customerId,
  ) async {
    final rows = await db.query(
      'payments',
      columns: ['payment_date'],
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'payment_date DESC, id DESC',
      limit: 1,
    );

    return rows.isEmpty ? '' : _string(rows.first['payment_date']);
  }

  // ---------------------------------------------------------------------------
  // FIRESTORE HELPERS
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _readCollection(
    String name,
  ) async {
    final snap = await _collection(name).get();

    return snap.docs
        .map(
          (doc) => <String, dynamic>{
            '_doc_id': doc.id,
            ...doc.data(),
          },
        )
        .toList();
  }
  
  Future<void> _setCloud(
    String collection,
    String documentId,
    Map<String, dynamic> data,
  ) async {
    await _collection(collection)
        .doc(_key(documentId))
        .set(data, SetOptions(merge: true));
  }

  bool _remoteIsNewer(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    return _remoteTimestamp(remote).isAfter(_localTimestamp(local));
  }

  bool _localIsNewer(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    return _localTimestamp(local).isAfter(_remoteTimestamp(remote));
  }

  DateTime _localTimestamp(Map<String, dynamic> row) {
    return DateTime.tryParse(_string(row['updated_at'])) ??
        DateTime.tryParse(_string(row['created_at'])) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime _remoteTimestamp(Map<String, dynamic> row) {
    final serverValue = row['cloud_updated_at'];
    final serverDate = serverValue is Timestamp
        ? serverValue.toDate()
        : DateTime.tryParse(_string(serverValue));

    return serverDate ??
        DateTime.tryParse(_string(row['updated_at'])) ??
        DateTime.tryParse(_string(row['created_at'])) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _key(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'empty';

    return trimmed
        .replaceAll('/', '_')
        .replaceAll('\\', '_')
        .replaceAll('#', '_');
  }

  String _string(Object? value) {
    if (value == null) return '';
    if (value is Timestamp) return value.toDate().toIso8601String();
    return value.toString();
  }

  int _int(
    Object? value, {
    int fallback = 0,
  }) {
    if (value is num) return value.toInt();
    return int.tryParse(_string(value)) ?? fallback;
  }

  double _double(
    Object? value, {
    double fallback = 0,
  }) {
    if (value is num) return value.toDouble();
    return double.tryParse(_string(value)) ?? fallback;
  }

  void dispose() {
    _stopAutoSync();
    _authSubscription?.cancel();
    _authSubscription = null;
  }
}
