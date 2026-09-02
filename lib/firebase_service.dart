import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// Digital 24 Online Billing - Cloud Master Data service.
///
/// SQLite remains the working offline database. Firebase/Firestore is the
/// cloud master used for multi-device sync and reinstall recovery.
class FirebaseService {
  FirebaseService._() {
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (user == null) {
        _stopAutoSync();
      } else {
        _startAutoSync();
        Future<void>.delayed(const Duration(seconds: 3), () async {
          if (isSignedIn) {
            try {
              await syncNow();
            } catch (_) {}
          }
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
    // Firestore rules may not have been installed yet. Authentication itself
    // must still succeed; cloud setup can be retried later by syncNow().
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

  void _startAutoSync() {
    if (_autoSyncTimer != null) return;
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (!isSignedIn) return;
      try {
        await syncNow();
      } catch (_) {
        // Offline/unavailable cloud: keep local SQLite working and retry later.
      }
    });
  }

  void _stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  Future<void> sendPasswordResetEmail(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> _ensureBusinessDocument() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _businessRef.set({
      'uid': user.uid,
      'email': user.email ?? '',
      'company_name': 'Digital 24 Online Billing',
      'address':
          'Seroil Colony, 4 No. Road, Ghoramara, Chandrima Rajshahi-6100',
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> cloudAvailable() async {
    if (!isSignedIn) return false;
    try {
      await _businessRef.get(const GetOptions(source: Source.server));
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
      final hasLocal = await _hasLocalCustomerData();
      if (!hasLocal) {
        await syncNow();
      } else {
        await syncNow();
      }
    } catch (_) {
      // Offline login must never be blocked by cloud failure.
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
    if (!isSignedIn) throw StateError('Please sign in first.');
    await _ensureBusinessDocument();
    final db = await DatabaseHelper.instance.database;

    // Merge is intentionally done in both directions. Firestore reads use its
    // normal cache/server behavior, while writes are queued by Firestore when
    // the device is temporarily offline.
    await _mergeCustomers(db);
    await _mergePackages(db);
    await _mergeStaff(db);
    await _mergeBills(db);
    await _mergePayments(db);
    await _repairLocalRelations(db);
    await _recalculateAllCustomerTotals(db);
  }

  Future<bool> _hasLocalCustomerData() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM customers');
    return rows.isNotEmpty && _int(rows.first['total']) > 0;
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

    // Read again so newly uploaded local rows are included before restore.
    final merged = await _readCollection('customers');
    for (final row in merged) {
      final key = _string(row['user_id']).trim();
      if (key.isEmpty) continue;
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

  Future<void> _upsertCustomer(Database db, Map<String, dynamic> r) async {
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
      // package_id is device-local, so it is deliberately not restored.
      await db.insert('customers', values, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
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
    final byName = <String, Map<String, dynamic>>{
      for (final r in cloud) _string(r['name']).trim(): r,
    };
    for (final row in local) {
      final key = _string(row['name']).trim();
      if (key.isEmpty) continue;
      final remote = byName[key];
      if (remote == null || _localIsNewer(row, remote)) {
        await _setCloud('packages', _key(key), _packageToCloud(row));
      }
    }
    for (final row in await _readCollection('packages')) {
      final name = _string(row['name']).trim();
      if (name.isEmpty) continue;
      final found = await db.query('packages', where: 'name = ?', whereArgs: [name], limit: 1);
      final values = {
        'name': name,
        'speed': _string(row['speed']),
        'price': _double(row['price']),
        'active': _int(row['active'], fallback: 1),
        'created_at': _string(row['created_at']),
        'updated_at': _string(row['updated_at']),
      };
      if (found.isEmpty) {
        await db.insert('packages', values, conflictAlgorithm: ConflictAlgorithm.ignore);
      } else {
        await db.update('packages', values, where: 'id = ?', whereArgs: [found.first['id']]);
      }
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

  // ---------------------------------------------------------------------------
  // STAFF
  // ---------------------------------------------------------------------------

  Future<void> _mergeStaff(Database db) async {
  final local = await db.query('staff');
  final cloud = await _readCollection('staff');

  final byUid = <String, Map<String, dynamic>>{};
  final byName = <String, Map<String, dynamic>>{};

  for (final r in cloud) {
    final uid = _string(r['staff_uid']).trim();
    final name = _string(r['name']).trim();

    if (uid.isNotEmpty) {
      byUid[uid] = r;
    }

    if (name.isNotEmpty) {
      byName[name] = r;
    }
  }

  for (final row in local) {
    final uid = _string(row['staff_uid']).trim();
    final name = _string(row['name']).trim();

    if (uid.isEmpty || name.isEmpty) continue;

    final remote = byUid[uid] ?? byName[name];

    final documentId = remote == null
        ? uid
        : _string(remote['_doc_id']).trim().isNotEmpty
            ? _string(remote['_doc_id']).trim()
            : uid;

    if (remote == null || _localIsNewer(row, remote)) {
      await _setCloud(
        'staff',
        documentId,
        _staffToCloud(row),
      );
    } else if (_string(remote['staff_uid']).trim().isEmpty) {
      await _setCloud(
        'staff',
        documentId,
        _staffToCloud(row),
      );
    }
  }

  for (final row in await _readCollection('staff')) {
    final name = _string(row['name']).trim();

    if (name.isEmpty) continue;

    final uid = _string(row['staff_uid']).trim();

    final values = {
      'staff_uid': uid,
      'name': name,
      'mobile': _string(row['mobile']),
      'active': _int(row['active'], fallback: 1),
      'created_at': _string(row['created_at']),
      'updated_at': _string(row['updated_at']),
    };

    final found = uid.isNotEmpty
        ? await db.query(
            'staff',
            where: 'staff_uid = ?',
            whereArgs: [uid],
            limit: 1,
          )
        : await db.query(
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
    } else {
      await db.update(
        'staff',
        values,
        where: 'id = ?',
        whereArgs: [found.first['id']],
      );
    }
  }
}

Map<String, dynamic> _staffToCloud(
  Map<String, dynamic> r,
) => {
      'staff_uid': _string(r['staff_uid']),
      'name': _string(r['name']),
      'mobile': _string(r['mobile']),
      'active': _int(r['active'], fallback: 1),
      'created_at': _string(r['created_at']),
      'updated_at': _string(r['updated_at']),
      'id_local': _int(r['id']),
      'cloud_updated_at': FieldValue.serverTimestamp(),
    };

  // ---------------------------------------------------------------------------
  // BILLS
  // ---------------------------------------------------------------------------

  Future<void> _mergeBills(Database db) async {
    final local = await db.query('bills');
    final customers = await db.query('customers', columns: ['id', 'user_id']);
    final userById = <int, String>{
      for (final c in customers) _int(c['id']): _string(c['user_id']),
    };
    final cloud = await _readCollection('bills');

    for (final row in local) {
      final customerUserId = userById[_int(row['customer_id'])] ?? '';
      final month = _string(row['billing_month']);
      if (customerUserId.isEmpty || month.isEmpty) continue;
      final key = '${customerUserId}__$month';
      final remote = cloud.cast<Map<String, dynamic>?>().firstWhere(
        (r) => r != null &&
            _string(r['customer_user_id']) == customerUserId &&
            _string(r['billing_month']) == month,
        orElse: () => null,
      );
      if (remote == null || _localIsNewer(row, remote)) {
        await _setCloud('bills', _key(key), _billToCloud(row, customerUserId));
      }
    }

    for (final row in await _readCollection('bills')) {
      final userId = _string(row['customer_user_id']).trim();
      final month = _string(row['billing_month']).trim();
      final customerId = customers
          .where((c) => _string(c['user_id']) == userId)
          .map((c) => _int(c['id']))
          .cast<int?>()
          .firstWhere((v) => v != null, orElse: () => null);
      if (customerId == null || month.isEmpty) continue;
      final values = {
        'customer_id': customerId,
        'billing_month': month,
        'bill_date': _int(row['bill_date'], fallback: 7),
        'amount': _double(row['amount']),
        'created_at': _string(row['created_at']),
        'updated_at': _string(row['updated_at']),
      };
      final found = await db.query(
        'bills',
        where: 'customer_id = ? AND billing_month = ?',
        whereArgs: [customerId, month],
        limit: 1,
      );
      if (found.isEmpty) {
        await db.insert('bills', values, conflictAlgorithm: ConflictAlgorithm.ignore);
      } else {
        await db.update('bills', values, where: 'id = ?', whereArgs: [found.first['id']]);
      }
    }
  }

  Map<String, dynamic> _billToCloud(Map<String, dynamic> r, String customerUserId) => {
        'customer_user_id': customerUserId,
        'billing_month': _string(r['billing_month']),
        'bill_date': _int(r['bill_date'], fallback: 7),
        'amount': _double(r['amount']),
        'created_at': _string(r['created_at']),
        'updated_at': _string(r['updated_at']),
        'id_local': _int(r['id']),
        'cloud_updated_at': FieldValue.serverTimestamp(),
      };

  // ---------------------------------------------------------------------------
  // PAYMENTS
  // ---------------------------------------------------------------------------

  Future<void> _mergePayments(Database db) async {
    final local = await db.query('payments');
    final customers = await db.query('customers', columns: ['id', 'user_id']);
    final userById = <int, String>{
      for (final c in customers) _int(c['id']): _string(c['user_id']),
    };
    final cloud = await _readCollection('payments');
    final cloudByReceipt = <String, Map<String, dynamic>>{
      for (final r in cloud) _string(r['receipt_no']): r,
    };

    for (final row in local) {
      final receipt = _string(row['receipt_no']).trim();
      final customerUserId = userById[_int(row['customer_id'])] ?? '';
      if (receipt.isEmpty || customerUserId.isEmpty) continue;
      final remote = cloudByReceipt[receipt];
      if (remote == null || _localIsNewer(row, remote)) {
        await _setCloud('payments', _key(receipt), await _paymentToCloud(db, row, customerUserId));
      }
    }

    for (final row in await _readCollection('payments')) {
      final receipt = _string(row['receipt_no']).trim();
      final userId = _string(row['customer_user_id']).trim();
      if (receipt.isEmpty || userId.isEmpty) continue;
      final customer = customers.where((c) => _string(c['user_id']) == userId).toList();
      if (customer.isEmpty) continue;
      final customerId = _int(customer.first['id']);
      final billId = await _findOrCreateBillForPayment(db, customerId, row);
      final staffId = await _findStaffId(db, _string(row['staff_name']));
      final values = {
        'customer_id': customerId,
        'bill_id': billId,
        'user_id': userId,
        'amount': _double(row['amount']),
        'payment_date': _string(row['payment_date']),
        'receipt_no': receipt,
        'staff_id': staffId,
        'note': _string(row['note']),
        'created_at': _string(row['created_at']),
        'updated_at': _string(row['updated_at']),
      };
      final found = await db.query('payments', where: 'receipt_no = ?', whereArgs: [receipt], limit: 1);
      if (found.isEmpty) {
        await db.insert('payments', values, conflictAlgorithm: ConflictAlgorithm.ignore);
      } else if (_remoteIsNewer(found.first, row)) {
        await db.update(
          'payments',
          values,
          where: 'id = ?',
          whereArgs: [found.first['id']],
        );
      }
    }
  }

  Future<Map<String, dynamic>> _paymentToCloud(
    Database db,
    Map<String, dynamic> r,
    String customerUserId,
  ) async {
    String staffName = '';
    final staffId = r['staff_id'];
    if (staffId != null) {
      final staff = await db.query('staff', where: 'id = ?', whereArgs: [staffId], limit: 1);
      if (staff.isNotEmpty) staffName = _string(staff.first['name']);
    }
    String billingMonth = '';
    final billId = r['bill_id'];
    if (billId != null) {
      final bills = await db.query('bills', columns: ['billing_month'], where: 'id = ?', whereArgs: [billId], limit: 1);
      if (bills.isNotEmpty) billingMonth = _string(bills.first['billing_month']);
    }
    if (billingMonth.isEmpty) {
      final date = _string(r['payment_date']);
      if (date.length >= 7) billingMonth = date.substring(0, 7);
    }
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

  Future<int?> _findOrCreateBillForPayment(
    Database db,
    int customerId,
    Map<String, dynamic> payment,
  ) async {
    final month = _string(payment['billing_month']);
    if (month.isEmpty) return null;
    final existing = await db.query(
      'bills',
      where: 'customer_id = ? AND billing_month = ?',
      whereArgs: [customerId, month],
      limit: 1,
    );
    if (existing.isNotEmpty) return _int(existing.first['id']);
    final customer = await db.query('customers', where: 'id = ?', whereArgs: [customerId], limit: 1);
    if (customer.isEmpty) return null;
    return db.insert('bills', {
      'customer_id': customerId,
            'billing_month': month,
      'bill_date': _int(customer.first['bill_date'], fallback: 7),
      'amount': _double(customer.first['amount']),
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<int?> _findStaffId(Database db, String name) async {
    if (name.trim().isEmpty) return null;
    final rows = await db.query('staff', where: 'name = ?', whereArgs: [name.trim()], limit: 1);
    return rows.isEmpty ? null : _int(rows.first['id']);
  }

  // ---------------------------------------------------------------------------
  // RELATION REPAIR
  // ---------------------------------------------------------------------------

  Future<void> _repairLocalRelations(Database db) async {
    final customers = await db.query(
      'customers',
      columns: ['id', 'package_id', 'package_name'],
    );
    for (final row in customers) {
      final id = _int(row['id']);
      if (id <= 0) continue;
      final packageName = _string(row['package_name']).trim();
      if (packageName.isEmpty) continue;
      final package = await db.query(
        'packages',
        columns: ['id'],
        where: 'name = ?',
        whereArgs: [packageName],
        limit: 1,
      );
      if (package.isNotEmpty) {
        final packageId = _int(package.first['id']);
        if (_int(row['package_id']) != packageId) {
          await db.update(
            'customers',
            {'package_id': packageId},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    }
  }
  
  // ---------------------------------------------------------------------------
  // TOTALS / FIRESTORE HELPERS
  // ---------------------------------------------------------------------------

  Future<void> _recalculateAllCustomerTotals(Database db) async {
    final customers = await db.query('customers', columns: ['id', 'amount']);
    for (final c in customers) {
      final id = _int(c['id']);
      final bill = await db.rawQuery(
        'SELECT COALESCE(SUM(amount),0) AS total FROM bills WHERE customer_id = ?',
        [id],
      );
      final paid = await db.rawQuery(
        'SELECT COALESCE(SUM(amount),0) AS total FROM payments WHERE customer_id = ?',
        [id],
      );
      final totalBill = _double(bill.first['total'], fallback: _double(c['amount']));
      final totalPaid = _double(paid.first['total']);
      final due = totalBill - totalPaid;
      await db.update(
        'customers',
        {
          'total_amount': totalBill,
          'paid_amount': totalPaid,
          'due_amount': due > 0 ? due : 0,
          'payment_date': await _latestPaymentDate(db, id),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<String> _latestPaymentDate(Database db, int customerId) async {
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

  Future<List<Map<String, dynamic>>> _readCollection(String name) async {
    final snap = await _collection(name).get();
    return snap.docs.map((d) => {'_doc_id': d.id, ...d.data()}).toList();
  }
  
  Future<void> _setCloud(
    String collection,
    String documentId,
    Map<String, dynamic> data,
  ) async {
    await _collection(collection).doc(_key(documentId)).set(data, SetOptions(merge: true));
  }

  bool _remoteIsNewer(Map<String, dynamic> local, Map<String, dynamic> remote) {
    final localDate = _localTimestamp(local);
    final remoteDate = _remoteTimestamp(remote);
    return remoteDate.isAfter(localDate);
  }

  bool _localIsNewer(Map<String, dynamic> local, Map<String, dynamic> remote) {
    final localDate = _localTimestamp(local);
    final remoteDate = _remoteTimestamp(remote);
    return localDate.isAfter(remoteDate);
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
    return trimmed.replaceAll('/', '_').replaceAll('\\', '_').replaceAll('#', '_');
  }

  String _string(Object? value) {
    if (value == null) return '';
    if (value is Timestamp) return value.toDate().toIso8601String();
    return value.toString();
  }

  int _int(Object? value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    return int.tryParse(_string(value)) ?? fallback;
  }

  double _double(Object? value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(_string(value)) ?? fallback;
  }
}
