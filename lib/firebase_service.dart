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

      // On a genuinely fresh installation, remove only the local
      // default master data before restoring the Cloud master.
      if (freshInstall && await _hasOnlyDefaultPackages(db)) {
        await db.delete('packages');
      }

      if (freshInstall && await _hasOnlyDefaultBillings(db)) {
        await db.delete('billings');
      }

      if (freshInstall) {
        // Restore existing Cloud master data first.
        await _pullCloudToLocal(db);

        // If Cloud has no packages, create the standard packages locally
        // and publish them to Cloud.
        if (await _count(db, 'packages') == 0) {
          await _seedDefaultPackages(db);
          await _mergePackages(db);
        }

        // If Cloud has no Billing workspace, recreate only the two
        // standard local Billing rows and publish them to Cloud.
        //
        // Do NOT call DatabaseHelper._seedDefaultBillings() here.
        // That method is private to DatabaseHelper.
        if (await _count(db, 'billings') == 0) {
          final now = DateTime.now().toIso8601String();

          await db.insert(
            'billings',
            {
              'name': 'Billing 1',
              'active': 1,
              'created_at': now,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );

          await db.insert(
            'billings',
            {
              'name': 'Billing 2',
              'active': 1,
              'created_at': now,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );

          await _mergeBillings(db);
        }

        await _repairLocalRelations(db);
        await _recalculateAllCustomerTotals(db);
        await _pushRecalculatedCustomers(db);
        return;
      }

      // Existing installation: perform normal two-way sync.
      await syncNow();
    } catch (_) {
      // Offline use must continue even when Cloud recovery is unavailable.
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

        await _mergeBillings(db);
    await _processCustomerDeletionTombstones(db);
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
      columns: ['name', 'active'],
      orderBy: 'id ASC',
    );

    final expected = <String>{
      '35 Mbps',
      '45 Mbps',
      '60 Mbps',
      '75 Mbps',
      '85 Mbps',
      '100 Mbps',
    };

    if (rows.length != expected.length) {
      return false;
    }

    for (final row in rows) {
      final name = _string(row['name']).trim();
      final active = _int(row['active'], fallback: 1);

      if (!expected.contains(name) || active != 1) {
        return false;
      }
    }

    return true;
  }

  Future<bool> _hasOnlyDefaultBillings(Database db) async {
    final rows = await db.query(
      'billings',
      columns: ['name', 'active'],
      orderBy: 'id ASC',
    );

    final expected = <String>{
      'Billing 1',
      'Billing 2',
    };

    if (rows.length != expected.length) {
      return false;
    }

    for (final row in rows) {
      final name = _string(row['name']).trim();
      final active = _int(row['active'], fallback: 1);

      if (!expected.contains(name) || active != 1) {
        return false;
      }
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
    final billings = await _readCollection('billings');
    final customers = await _readCollection('customers');
    final packages = await _readCollection('packages');
    final staff = await _readCollection('staff');
    final bills = await _readCollection('bills');
    final payments = await _readCollection('payments');

    for (final row in billings) {
      await _upsertBilling(db, row);
    }

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
  // BILLING WORKSPACES
  // ---------------------------------------------------------------------------
  Future<void> _mergeBillings(Database db) async {
    final local = await db.query('billings');
    final cloud = await _readCollection('billings');

    final cloudById = <String, Map<String, dynamic>>{};
    final cloudByBillingId = <int, Map<String, dynamic>>{};
    final cloudByName = <String, Map<String, dynamic>>{};

    for (final row in cloud) {
      final docId = _string(row['_doc_id']).trim();
      final cloudId = _string(row['cloud_id']).trim();
      final billingId = _int(row['billing_id']);
      final name = _string(row['name']).trim();

      final stableId =
          cloudId.isNotEmpty ? cloudId : docId;

      if (stableId.isNotEmpty) {
        cloudById[stableId] = row;
      }

      if (billingId > 0) {
        cloudByBillingId[billingId] = row;
      }

      if (name.isNotEmpty) {
        cloudByName[name] = row;
      }
    }

    // ------------------------------------------------------------
    // LOCAL -> CLOUD
    // ------------------------------------------------------------
    for (final row in local) {
      final localId = _int(row['id']);
      final name = _string(row['name']).trim();

      if (localId <= 0 || name.isEmpty) {
        continue;
      }

      String cloudId =
          _string(row['cloud_id']).trim();

      Map<String, dynamic>? remote;

      // 1. Local stable Cloud ID থাকলে
      //    সেটিই প্রথম priority।
      if (cloudId.isNotEmpty) {
        remote = cloudById[cloudId];
      }

      // 2. পুরোনো Billing হলে প্রথমে local ID দিয়ে
      //    পুরোনো Cloud record খোঁজা হবে।
      if (cloudId.isEmpty) {
        remote = cloudByBillingId[localId];

        if (remote != null) {
          cloudId = _string(
            remote['_doc_id'],
          ).trim();

          if (cloudId.isEmpty) {
            cloudId = _string(
              remote['cloud_id'],
            ).trim();
          }
        }
      }

      // 3. ID দিয়ে না পাওয়া গেলে নাম দিয়ে পুরোনো
      //    Cloud Billing খোঁজা হবে।
      if (cloudId.isEmpty) {
        remote = cloudByName[name];

        if (remote != null) {
          cloudId = _string(
            remote['_doc_id'],
          ).trim();

          if (cloudId.isEmpty) {
            cloudId = _string(
              remote['cloud_id'],
            ).trim();
          }
        }
      }

      // 4. একেবারে নতুন Billing হলে নতুন stable
      //    Firestore document ID তৈরি হবে।
      if (cloudId.isEmpty) {
        cloudId = _collection('billings')
            .doc()
            .id;
      }

      // 5. Local SQLite-এ stable Cloud ID সংরক্ষণ।
      if (_string(row['cloud_id']).trim() !=
          cloudId) {
        await db.update(
          'billings',
          {
            'cloud_id': cloudId,
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
      }

      // 6. Stable Cloud document-এ Local data পাঠানো।
      if (remote == null ||
          _localIsNewer(row, remote)) {
        await _setCloud(
          'billings',
          cloudId,
          _billingToCloud(
            row,
            cloudId,
          ),
        );
      }
    }

    // ------------------------------------------------------------
    // CLOUD -> LOCAL
    // ------------------------------------------------------------
    final merged =
        await _readCollection('billings');

    for (final row in merged) {
      await _upsertBilling(
        db,
        row,
      );
    }
  }

  Map<String, dynamic> _billingToCloud(
    Map<String, dynamic> r,
    String cloudId,
  ) =>
      {
        'cloud_id': cloudId,
        'billing_id': _int(
          r['id'],
        ),
        'name': _string(
          r['name'],
        ),
        'active': _int(
          r['active'],
          fallback: 1,
        ),
        'created_at': _string(
          r['created_at'],
        ),
        'updated_at': _string(
          r['updated_at'],
        ),
        'cloud_updated_at':
            FieldValue.serverTimestamp(),
      };

  Future<void> _upsertBilling(
    Database db,
    Map<String, dynamic> r,
  ) async {
    final billingId =
        _int(r['billing_id']);

    final name =
        _string(r['name']).trim();

    if (billingId <= 0 ||
        name.isEmpty) {
      return;
    }

    String cloudId =
        _string(r['cloud_id']).trim();

    if (cloudId.isEmpty) {
      cloudId =
          _string(r['_doc_id']).trim();
    }

    if (cloudId.isEmpty) {
      return;
    }

    final values = {
      'name': name,
      'active': _int(
        r['active'],
        fallback: 1,
      ),
      'cloud_id': cloudId,
      'created_at': _string(
        r['created_at'],
      ),
      'updated_at': _string(
        r['updated_at'],
      ),
    };

    // প্রথমে Local Billing ID দিয়ে খোঁজা।
    // এতে Customer/Bill/Payment-এর existing
    // local relationship অক্ষত থাকে।
    final foundById =
        await db.query(
      'billings',
      where: 'id = ?',
      whereArgs: [billingId],
      limit: 1,
    );

    if (foundById.isNotEmpty) {
      final existing =
          foundById.first;

      if (_remoteIsNewer(
        existing,
        r,
      )) {
        await db.update(
          'billings',
          values,
          where: 'id = ?',
          whereArgs: [billingId],
        );
      } else if (_string(
            existing['cloud_id'],
          ).trim().isEmpty) {
        await db.update(
          'billings',
          {
            'cloud_id': cloudId,
          },
          where: 'id = ?',
          whereArgs: [billingId],
        );
      }

      return;
    }

    // Local ID না থাকলে একই Cloud ID দিয়ে খোঁজা।
    final foundByCloudId =
        await db.query(
      'billings',
      where: 'cloud_id = ?',
      whereArgs: [cloudId],
      limit: 1,
    );

    if (foundByCloudId.isNotEmpty) {
      final existing =
          foundByCloudId.first;

      if (_remoteIsNewer(
        existing,
        r,
      )) {
        await db.update(
          'billings',
          values,
          where: 'id = ?',
          whereArgs: [
            existing['id'],
          ],
        );
      }

      return;
    }

    // নতুন Cloud Billing local database-এ যোগ।
    await db.insert(
      'billings',
      {
        'id': billingId,
        ...values,
      },
      conflictAlgorithm:
          ConflictAlgorithm.ignore,
    );
  }

  // ---------------------------------------------------------------------------
  // CUSTOMERS
  // ---------------------------------------------------------------------------

        Future<void> _processCustomerDeletionTombstones(
    Database db,
  ) async {
    final deleted = await db.query(
      'deleted_customers',
      orderBy: 'id ASC',
    );

    for (final row in deleted) {
      final billingId = _int(
        row['billing_id'],
        fallback: 1,
      );

      final userId = _string(
        row['user_id'],
      ).trim();

      final deletedAt = DateTime.tryParse(
        _string(row['deleted_at']),
      );

      if (billingId <= 0 ||
          userId.isEmpty ||
          deletedAt == null) {
        continue;
      }

      final key =
          '${billingId}__$userId';

      final customerRef = _collection(
        'customers',
      ).doc(_key(key));

      final snapshot = await customerRef.get();

      // Cloud-এ Customer আর নেই।
      // Tombstone অবশ্যই রেখে দিতে হবে, যাতে কোনো
      // পুরোনো Offline device আবার Customer-টি
      // Cloud-এ resurrect করতে না পারে।
      if (!snapshot.exists) {
        continue;
      }

      final remote =
          snapshot.data() ??
          <String, dynamic>{};

      final remoteUpdatedAt =
          _remoteTimestamp(remote);

      // Cloud record যদি deletion-এর সময়ের
      // সমান বা পুরোনো হয়, তাহলে এটি সেই পুরোনো
      // Customer record।
      //
      // এটিকে আবার delete করব এবং tombstone রাখব।
      if (!remoteUpdatedAt.isAfter(deletedAt)) {
        await customerRef.delete();
        continue;
      }

      // Cloud-এ deletion-এর পরে সত্যিকারের নতুন
      // Customer record তৈরি/পরিবর্তন হয়েছে।
      //
      // এটিকে legitimate newer record হিসেবে গ্রহণ
      // করে পুরোনো tombstone সরিয়ে দেওয়া হবে।
      await db.delete(
        'deleted_customers',
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
        }
    Future<void> _mergeCustomers(Database db) async {
    final local = await db.query('customers');
    final cloud = await _readCollection('customers');

    final deletedRows = await db.query(
      'deleted_customers',
      columns: ['billing_id', 'user_id'],
    );

    final deletedKeys = <String>{
      for (final row in deletedRows)
        '${_int(row['billing_id'], fallback: 1)}__'
            '${_string(row['user_id']).trim()}',
    };

    final cloudByKey = <String, Map<String, dynamic>>{};

    for (final row in cloud) {
      final key =
          '${_int(row['billing_id'], fallback: 1)}__'
          '${_string(row['user_id']).trim()}';

      if (key != '1__' &&
          key != '0__' &&
          !key.endsWith('__') &&
          !deletedKeys.contains(key)) {
        cloudByKey[key] = row;
      }
    }

    // Local -> Cloud
    //
    // Customer master information is synchronized using the customer's
    // own updated_at. Calculated totals are NOT used to make an old
    // device look newer.
    for (final row in local) {
      final userId = _string(row['user_id']).trim();

      if (userId.isEmpty) continue;

      final billingId = _int(
        row['billing_id'],
        fallback: 1,
      );

      final key = '${billingId}__$userId';

      if (deletedKeys.contains(key)) {
        continue;
      }

      final remote = cloudByKey[key];

      if (remote == null) {
        await _setCloud(
          'customers',
          _key(key),
          _customerToCloud(row),
        );
        continue;
      }

      // Only a genuine newer Customer master record may replace
      // the Cloud master record.
      if (_localIsNewer(row, remote)) {
        await _setCloud(
          'customers',
          _key(key),
          _customerToCloud(row),
        );
      }
    }

    // Cloud -> Local
    //
    // Pull the final Cloud state back so all authorized devices
    // converge to the same Customer master data.
    final merged = await _readCollection('customers');

    for (final row in merged) {
      final billingId = _int(
        row['billing_id'],
        fallback: 1,
      );

      final userId = _string(row['user_id']).trim();

      if (userId.isEmpty) continue;

      final key = '${billingId}__$userId';

      if (deletedKeys.contains(key)) {
        continue;
      }

      await _upsertCustomer(db, row);
    }
    }

  Map<String, dynamic> _customerToCloud(
    Map<String, dynamic> r,
  ) =>
      {
        'billing_id': _int(
          r['billing_id'],
          fallback: 1,
        ),
        'cust_id': _string(r['cust_id']),
        'user_id': _string(r['user_id']),
        'name': _string(r['name']),
        'mobile': _string(r['mobile']),
        'address': _string(r['address']),
        'package_name': _string(r['package_name']),
        'bill_date': _int(
          r['bill_date'],
          fallback: 7,
        ),
        'amount': _double(r['amount']),
        'total_amount': _double(
          r['total_amount'],
        ),
        'paid_amount': _double(
          r['paid_amount'],
        ),
        'due_amount': _double(
          r['due_amount'],
        ),
        'payment_date': _string(
          r['payment_date'],
        ),
        'staff_id': _int(r['staff_id']),
        'status': _int(
          r['status'],
          fallback: 1,
        ),
        'active': _int(
          r['active'],
          fallback: 1,
        ),
        'created_at': _string(
          r['created_at'],
        ),
        'updated_at': _string(
          r['updated_at'],
        ),
        'id_local': _int(r['id']),
        'cloud_updated_at':
            FieldValue.serverTimestamp(),
      };

  Future<void> _upsertCustomer(
    Database db,
    Map<String, dynamic> r,
  ) async {
    final userId =
        _string(r['user_id']).trim();

    if (userId.isEmpty) return;

    final values = {
      'billing_id': _int(
        r['billing_id'],
        fallback: 1,
      ),
      'cust_id': _string(r['cust_id']),
      'user_id': userId,
      'name': _string(r['name']),
      'mobile': _string(r['mobile']),
      'address': _string(r['address']),
      'package_name': _string(
        r['package_name'],
      ),
      'bill_date': _int(
        r['bill_date'],
        fallback: 7,
      ),
      'amount': _double(r['amount']),
      'total_amount': _double(
        r['total_amount'],
      ),
      'paid_amount': _double(
        r['paid_amount'],
      ),
      'due_amount': _double(
        r['due_amount'],
      ),
      'payment_date': _string(
        r['payment_date'],
      ),
      'staff_id': _int(r['staff_id']),
      'status': _int(
        r['status'],
        fallback: 1,
      ),
      'active': _int(
        r['active'],
        fallback: 1,
      ),
      'created_at': _string(
        r['created_at'],
      ),
      'updated_at': _string(
        r['updated_at'],
      ),
    };

    final found = await db.query(
      'customers',
      where:
          'billing_id = ? AND user_id = ?',
      whereArgs: [
        _int(
          r['billing_id'],
          fallback: 1,
        ),
        userId,
      ],
      limit: 1,
    );

    if (found.isEmpty) {
      await db.insert(
        'customers',
        values,
        conflictAlgorithm:
            ConflictAlgorithm.ignore,
      );
    } else if (_remoteIsNewer(
      found.first,
      r,
    )) {
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

  final cloudById = <String, Map<String, dynamic>>{};
  final cloudByName = <String, Map<String, dynamic>>{};

  for (final row in cloud) {
    final docId = _string(row['_doc_id']).trim();
    final cloudId = _string(row['cloud_id']).trim();
    final name = _string(row['name']).trim();

    final stableId =
        cloudId.isNotEmpty ? cloudId : docId;

    if (stableId.isNotEmpty) {
      cloudById[stableId] = row;
    }

    if (name.isNotEmpty) {
      cloudByName[name] = row;
    }
  }

  // ------------------------------------------------------------
  // LOCAL -> CLOUD
  // ------------------------------------------------------------
  for (final row in local) {
    final name = _string(row['name']).trim();

    if (name.isEmpty) continue;

    String cloudId =
        _string(row['cloud_id']).trim();

    Map<String, dynamic>? remote;

    // 1. Local-এ stable cloud_id থাকলে
    //    সেটিই সর্বোচ্চ priority।
    if (cloudId.isNotEmpty) {
      remote = cloudById[cloudId];
    }

    // 2. পুরোনো Package হলে name দিয়ে
    //    পুরোনো Cloud record খুঁজে তার document ID গ্রহণ।
    if (cloudId.isEmpty) {
      remote = cloudByName[name];

      if (remote != null) {
        cloudId = _string(
          remote['_doc_id'],
        ).trim();

        if (cloudId.isEmpty) {
          cloudId = _string(
            remote['cloud_id'],
          ).trim();
        }
      }
    }

    // 3. কোনো পুরোনো Cloud record না থাকলে
    //    নতুন stable Firestore document ID তৈরি।
    if (cloudId.isEmpty) {
      cloudId = _collection('packages')
          .doc()
          .id;
    }

    // 4. Local SQLite-এ stable cloud_id সংরক্ষণ।
    if (_string(row['cloud_id']).trim() !=
        cloudId) {
      await db.update(
        'packages',
        {
          'cloud_id': cloudId,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }

    // 5. Stable Cloud ID ব্যবহার করে
    //    Local Package Cloud-এ পাঠানো।
    if (remote == null ||
        _localIsNewer(row, remote)) {
      await _setCloud(
        'packages',
        cloudId,
        _packageToCloud(
          row,
          cloudId,
        ),
      );
    }
  }

  // ------------------------------------------------------------
  // CLOUD -> LOCAL
  // ------------------------------------------------------------
  final merged =
      await _readCollection('packages');

  for (final row in merged) {
    await _upsertPackage(
      db,
      row,
    );
  }
}

Map<String, dynamic> _packageToCloud(
  Map<String, dynamic> r,
  String cloudId,
) =>
    {
      'cloud_id': cloudId,
      'name': _string(r['name']),
      'speed': _string(r['speed']),
      'price': _double(r['price']),
      'active': _int(
        r['active'],
        fallback: 1,
      ),
      'created_at': _string(
        r['created_at'],
      ),
      'updated_at': _string(
        r['updated_at'],
      ),
      'id_local': _int(r['id']),
      'cloud_updated_at':
          FieldValue.serverTimestamp(),
    };

Future<void> _upsertPackage(
  Database db,
  Map<String, dynamic> r,
) async {
  final name =
      _string(r['name']).trim();

  if (name.isEmpty) return;

  String cloudId =
      _string(r['cloud_id']).trim();

  if (cloudId.isEmpty) {
    cloudId =
        _string(r['_doc_id']).trim();
  }

  if (cloudId.isEmpty) return;

  final values = {
    'name': name,
    'speed': _string(r['speed']),
    'price': _double(r['price']),
    'active': _int(
      r['active'],
      fallback: 1,
    ),
    'cloud_id': cloudId,
    'created_at': _string(
      r['created_at'],
    ),
    'updated_at': _string(
      r['updated_at'],
    ),
  };

  // প্রথমে stable cloud_id দিয়ে খোঁজা হবে।
  final foundByCloudId =
      await db.query(
    'packages',
    where: 'cloud_id = ?',
    whereArgs: [cloudId],
    limit: 1,
  );

  if (foundByCloudId.isNotEmpty) {
    final existing =
        foundByCloudId.first;

    if (_remoteIsNewer(
      existing,
      r,
    )) {
      await db.update(
        'packages',
        values,
        where: 'id = ?',
        whereArgs: [
          existing['id'],
        ],
      );
    }

    return;
  }

  // পুরোনো Local Package হলে name দিয়ে
  // matching করে stable cloud_id বসানো হবে।
  final foundByName =
      await db.query(
    'packages',
    where: 'name = ?',
    whereArgs: [name],
    limit: 1,
  );

  if (foundByName.isNotEmpty) {
    final existing =
        foundByName.first;

    final currentCloudId =
        _string(
      existing['cloud_id'],
    ).trim();

    final shouldUpdate =
        currentCloudId.isEmpty ||
        _remoteIsNewer(
          existing,
          r,
        );

    if (shouldUpdate) {
      await db.update(
        'packages',
        values,
        where: 'id = ?',
        whereArgs: [
          existing['id'],
        ],
      );
    }

    return;
  }

  // Cloud থেকে সম্পূর্ণ নতুন Package।
  await db.insert(
    'packages',
    values,
    conflictAlgorithm:
        ConflictAlgorithm.ignore,
  );
}

  // ---------------------------------------------------------------------------
// STAFF
// ---------------------------------------------------------------------------

Future<void> _mergeStaff(Database db) async {
  final local = await db.query('staff');
  final cloud = await _readCollection('staff');

  final cloudById = <String, Map<String, dynamic>>{};
  final cloudByName = <String, Map<String, dynamic>>{};

  for (final row in cloud) {
    final docId = _string(row['_doc_id']).trim();
    final name = _string(row['name']).trim();

    if (docId.isNotEmpty) {
      cloudById[docId] = row;
    }

    if (name.isNotEmpty) {
      cloudByName[name] = row;
    }
  }

  // ------------------------------------------------------------
  // LOCAL -> CLOUD
  // ------------------------------------------------------------
  for (final row in local) {
    final name = _string(row['name']).trim();

    if (name.isEmpty) continue;

    String cloudId = _string(row['cloud_id']).trim();
    Map<String, dynamic>? remote;

    // 1. Stable cloud_id থাকলে সেটিই সর্বোচ্চ priority।
    if (cloudId.isNotEmpty) {
      remote = cloudById[cloudId];
    }

    // 2. পুরোনো Staff হলে cloud_id এখনো না-ও থাকতে পারে।
    //    পুরোনো name-based Cloud record খুঁজে সেটির document ID গ্রহণ।
    if (cloudId.isEmpty) {
      remote = cloudByName[name];

      if (remote != null) {
        cloudId = _string(remote['_doc_id']).trim();
      }
    }

    // 3. কোনো পুরোনো Cloud record না থাকলে নতুন stable
    //    Firestore document ID তৈরি।
    if (cloudId.isEmpty) {
      cloudId = _collection('staff').doc().id;
    }

    // Local database-এ stable cloud_id সংরক্ষণ।
    if (_string(row['cloud_id']).trim() != cloudId) {
      await db.update(
        'staff',
        {
          'cloud_id': cloudId,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }

    // Stable Cloud ID-তে local Staff পাঠানো হবে।
    if (remote == null || _localIsNewer(row, remote)) {
      await _setCloud(
        'staff',
        cloudId,
        _staffToCloud(
          row,
          cloudId,
        ),
      );
    }
  }

  // ------------------------------------------------------------
  // CLOUD -> LOCAL
  // ------------------------------------------------------------
  final merged = await _readCollection('staff');

  for (final row in merged) {
    await _upsertStaff(
      db,
      row,
    );
  }
}

Map<String, dynamic> _staffToCloud(
  Map<String, dynamic> r,
  String cloudId,
) =>
    {
      'cloud_id': cloudId,
      'name': _string(r['name']),
      'mobile': _string(r['mobile']),
      'active': _int(
        r['active'],
        fallback: 1,
      ),
      'created_at': _string(r['created_at']),
      'updated_at': _string(r['updated_at']),
      'cloud_updated_at': FieldValue.serverTimestamp(),
    };

Future<void> _upsertStaff(
  Database db,
  Map<String, dynamic> r,
) async {
  final name = _string(r['name']).trim();

  if (name.isEmpty) return;

  final remoteCloudId = _string(
    r['cloud_id'],
  ).trim();

  final documentId = _string(
    r['_doc_id'],
  ).trim();

  final cloudId = remoteCloudId.isNotEmpty
      ? remoteCloudId
      : documentId;

  if (cloudId.isEmpty) return;

  final values = {
    'name': name,
    'mobile': _string(r['mobile']),
    'active': _int(
      r['active'],
      fallback: 1,
    ),
    'cloud_id': cloudId,
    'created_at': _string(r['created_at']),
    'updated_at': _string(r['updated_at']),
  };

  // প্রথমে Stable Cloud ID দিয়ে Staff খোঁজা।
  final byCloudId = await db.query(
    'staff',
    where: 'cloud_id = ?',
    whereArgs: [cloudId],
    limit: 1,
  );

  if (byCloudId.isNotEmpty) {
    final local = byCloudId.first;

    if (_remoteIsNewer(local, r)) {
      await db.update(
        'staff',
        values,
        where: 'id = ?',
        whereArgs: [local['id']],
      );
    }

    return;
  }

  // পুরোনো local Staff-এর cloud_id খালি থাকলে
  // name দিয়ে matching করে existing local Staff-কে
  // একই Stable Cloud ID দেওয়া হবে।
  final byName = await db.query(
    'staff',
    where: 'name = ?',
    whereArgs: [name],
    limit: 1,
  );

  if (byName.isNotEmpty) {
    final local = byName.first;

    await db.update(
      'staff',
      values,
      where: 'id = ?',
      whereArgs: [local['id']],
    );

    return;
  }

  // একেবারে নতুন Cloud Staff হলে নতুন local Staff তৈরি।
  await db.insert(
    'staff',
    values,
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );
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

      final billingId = _int(row['billing_id'], fallback: 1);
      final key = '${billingId}__${customerUserId}__$month';
      Map<String, dynamic>? remote;

      for (final item in cloud) {
        if (_int(item['billing_id'], fallback: 1) == billingId &&
            _string(item['customer_user_id']).trim() == customerUserId &&
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

      final billKey = _key('${_int(bill['billing_id'], fallback: 1)}__${customerUserId}__$month');
      final balanceRef = _collection('bill_balances').doc(billKey);
      final existing = await balanceRef.get();
      
      if (existing.exists) continue;

      double paidTotal = 0;
      for (final payment in payments) {
        if (_int(payment['billing_id'], fallback: 1) == _int(bill['billing_id'], fallback: 1) &&
            _string(payment['customer_user_id']).trim() == customerUserId &&
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
        'billing_id': _int(r['billing_id'], fallback: 1),
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
    final billingId = _int(
      r['billing_id'],
      fallback: 1,
    );

    final userId = _string(
      r['customer_user_id'],
    ).trim();

    final month = _string(
      r['billing_month'],
    ).trim();

    if (billingId <= 0 ||
        userId.isEmpty ||
        month.isEmpty) {
      return;
    }

    // ------------------------------------------------------------
    // Customer যাচাই
    // ------------------------------------------------------------
    final customers = await db.query(
      'customers',
      columns: ['id', 'billing_id'],
      where: 'billing_id = ? AND user_id = ?',
      whereArgs: [
        billingId,
        userId,
      ],
      limit: 1,
    );

    if (customers.isEmpty) {
      return;
    }

    final customerId = _int(
      customers.first['id'],
    );

    if (customerId <= 0) {
      return;
    }

    // ------------------------------------------------------------
    // Bill-এর Local data
    // ------------------------------------------------------------
    final values = {
      'billing_id': billingId,
      'customer_id': customerId,
      'billing_month': month,
      'bill_date': _int(
        r['bill_date'],
        fallback: 7,
      ),
      'amount': _double(
        r['amount'],
      ),
      'created_at': _string(
        r['created_at'],
      ),
      'updated_at': _string(
        r['updated_at'],
      ),
    };

    // ------------------------------------------------------------
    // বর্তমান Database schema অনুযায়ী:
    // UNIQUE(customer_id, billing_month)
    //
    // তাই Existing Bill Customer + Month দিয়ে খোঁজা হবে।
    // ------------------------------------------------------------
    final found = await db.query(
      'bills',
      columns: [
        'id',
        'billing_id',
        'customer_id',
        'billing_month',
      ],
      where:
          'customer_id = ? AND billing_month = ?',
      whereArgs: [
        customerId,
        month,
      ],
      limit: 1,
    );

    if (found.isNotEmpty) {
      final existingBillingId = _int(
        found.first['billing_id'],
        fallback: 1,
      );

      // অন্য Billing-এর Bill কখনো overwrite করা যাবে না।
      if (existingBillingId != billingId) {
        return;
      }

      if (_remoteIsNewer(
        found.first,
        r,
      )) {
        await db.update(
          'bills',
          values,
          where: 'id = ?',
          whereArgs: [
            found.first['id'],
          ],
        );
      }

      return;
    }

    // ------------------------------------------------------------
    // নতুন Bill তৈরি
    // ------------------------------------------------------------
    final billId = await db.insert(
      'bills',
      values,
      conflictAlgorithm:
          ConflictAlgorithm.ignore,
    );

    // ------------------------------------------------------------
    // Concurrent operation-এর কারণে Bill আগে তৈরি হলে
    // আবার খুঁজে নেওয়া হবে।
    // ------------------------------------------------------------
    if (billId <= 0) {
      final retry = await db.query(
        'bills',
        columns: [
          'id',
          'billing_id',
          'customer_id',
          'billing_month',
        ],
        where:
            'customer_id = ? AND billing_month = ?',
        whereArgs: [
          customerId,
          month,
        ],
        limit: 1,
      );

      if (retry.isEmpty) {
        return;
      }

      final retryBillingId = _int(
        retry.first['billing_id'],
        fallback: 1,
      );

      if (retryBillingId != billingId) {
        return;
      }
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

      if (receipt.isNotEmpty) {
        cloudByReceipt[receipt] = row;
      }
    }

    for (final row in local) {
      final receipt = _string(row['receipt_no']).trim();
      final customerUserId =
          userById[_int(row['customer_id'])] ?? '';

      if (receipt.isEmpty || customerUserId.isEmpty) {
        continue;
      }

      final remote = cloudByReceipt[receipt];

      // A receipt number is the permanent identity of a payment.
      // If this receipt already exists in Cloud, never overwrite it
      // from another device. This prevents Payment History and the
      // server-side bill balance from becoming inconsistent.
      if (remote != null) {
        continue;
      }

      final uploaded = await _tryUploadPaymentAtomically(
        db,
        row,
        customerUserId,
      );

      // If the Cloud bill rejects the payment because of a conflict
      // or overpayment, keep the local payment record intact.
      // It must not be silently deleted.
      if (!uploaded) {
        continue;
      }
    }

    // Cloud remains the source of truth for payment records.
    // Pull all Cloud payments back into this device so every
    // authorized phone eventually has the same payment history.
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

    final billKey = _key('${_int(row['billing_id'], fallback: 1)}__${customerUserId}__$month');
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
      'billing_id': _int(r['billing_id'], fallback: 1),
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
    final billingId = _int(r['billing_id'], fallback: 1);
    final userId = _string(r['customer_user_id']).trim();

    if (receipt.isEmpty || userId.isEmpty) return;

    final customers = await db.query(
      'customers',
      where: 'billing_id = ? AND user_id = ?',
      whereArgs: [billingId, userId],
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
      'billing_id': billingId,
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
  final month = await _paymentBillingMonth(
    db,
    payment,
  );

  if (month.isEmpty) {
    return null;
  }

  final paymentBillingId = _int(
    payment['billing_id'],
    fallback: 1,
  );

  if (paymentBillingId <= 0) {
    return null;
  }

  // ------------------------------------------------------------
  // Customer যাচাই
  // ------------------------------------------------------------
  final customer = await db.query(
    'customers',
    columns: [
      'billing_id',
      'bill_date',
      'amount',
    ],
    where: 'id = ?',
    whereArgs: [customerId],
    limit: 1,
  );

  if (customer.isEmpty) {
    return null;
  }

  final customerBillingId = _int(
    customer.first['billing_id'],
    fallback: 1,
  );

  // Payment এবং Customer একই Billing-এর
  // হতে হবে।
  if (customerBillingId != paymentBillingId) {
    return null;
  }

  // ------------------------------------------------------------
  // Existing Bill
  //
  // Database-এর বর্তমান schema অনুযায়ী:
  // UNIQUE(customer_id, billing_month)
  // তাই Billing ID দিয়ে নয়,
  // Customer + Month দিয়ে Bill খোঁজা হবে।
  // ------------------------------------------------------------
  final existing = await db.query(
    'bills',
    columns: [
      'id',
      'billing_id',
      'customer_id',
      'billing_month',
    ],
    where:
        'customer_id = ? AND billing_month = ?',
    whereArgs: [
      customerId,
      month,
    ],
    limit: 1,
  );

  if (existing.isNotEmpty) {
    final existingBillingId = _int(
      existing.first['billing_id'],
      fallback: 1,
    );

    // Existing Bill অন্য Billing-এর হলে
    // সেটি এই Payment-এর জন্য ব্যবহার করা যাবে না।
    if (existingBillingId != customerBillingId) {
      return null;
    }

    return _int(
      existing.first['id'],
    );
  }

  // ------------------------------------------------------------
  // নতুন Bill তৈরি
  // ------------------------------------------------------------
  final now = DateTime.now().toIso8601String();

  final billId = await db.insert(
    'bills',
    {
      'billing_id': customerBillingId,
      'customer_id': customerId,
      'billing_month': month,
      'bill_date': _int(
        customer.first['bill_date'],
        fallback: 7,
      ),
      'amount': _double(
        customer.first['amount'],
      ),
      'created_at': now,
      'updated_at': now,
    },
    conflictAlgorithm:
        ConflictAlgorithm.ignore,
  );

  if (billId <= 0) {
    // Concurrent operation-এর কারণে Bill ইতিমধ্যে
    // তৈরি হয়ে গেলে আবার খুঁজে নেওয়া হবে।
    final retry = await db.query(
      'bills',
      columns: [
        'id',
        'billing_id',
        'customer_id',
        'billing_month',
      ],
      where:
          'customer_id = ? AND billing_month = ?',
      whereArgs: [
        customerId,
        month,
      ],
      limit: 1,
    );

    if (retry.isEmpty) {
      return null;
    }

    final retryBillingId = _int(
      retry.first['billing_id'],
      fallback: 1,
    );

    if (retryBillingId != customerBillingId) {
      return null;
    }

    return _int(
      retry.first['id'],
    );
  }

  return billId;
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
  // ------------------------------------------------------------
  // 1. CUSTOMER -> PACKAGE
  // ------------------------------------------------------------
  final customers = await db.query(
    'customers',
    columns: [
      'id',
      'billing_id',
      'package_id',
      'package_name',
    ],
  );

  for (final row in customers) {
    final customerId = _int(row['id']);
    final packageName = _string(
      row['package_name'],
    ).trim();

    if (customerId <= 0 || packageName.isEmpty) {
      continue;
    }

    final package = await db.query(
      'packages',
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [packageName],
      limit: 1,
    );

    if (package.isEmpty) {
      continue;
    }

    final packageId = _int(
      package.first['id'],
    );

    if (_int(row['package_id']) != packageId) {
      await db.update(
        'customers',
        {
          'package_id': packageId,
        },
        where: 'id = ?',
        whereArgs: [customerId],
      );
    }
  }

  // ------------------------------------------------------------
  // 2. BILL -> CUSTOMER/BILLING
  // ------------------------------------------------------------
  final bills = await db.query(
    'bills',
    columns: [
      'id',
      'billing_id',
      'customer_id',
    ],
  );

  for (final bill in bills) {
    final billId = _int(bill['id']);
    final customerId = _int(
      bill['customer_id'],
    );

    if (billId <= 0 || customerId <= 0) {
      continue;
    }

    final customer = await db.query(
      'customers',
      columns: ['billing_id'],
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );

    if (customer.isEmpty) {
      continue;
    }

    final customerBillingId = _int(
      customer.first['billing_id'],
      fallback: 1,
    );

    if (customerBillingId <= 0) {
      continue;
    }

    if (_int(bill['billing_id']) !=
        customerBillingId) {
      await db.update(
        'bills',
        {
          'billing_id': customerBillingId,
        },
        where: 'id = ?',
        whereArgs: [billId],
      );
    }
  }

  // ------------------------------------------------------------
  // 3. PAYMENT -> CUSTOMER/BILL/BILLING
  // ------------------------------------------------------------
  final payments = await db.query(
    'payments',
    columns: [
      'id',
      'billing_id',
      'customer_id',
      'bill_id',
    ],
  );

  for (final payment in payments) {
    final paymentId = _int(
      payment['id'],
    );
    final customerId = _int(
      payment['customer_id'],
    );
    final billId = _int(
      payment['bill_id'],
    );

    if (paymentId <= 0 ||
        customerId <= 0) {
      continue;
    }

    final customer = await db.query(
      'customers',
      columns: ['billing_id'],
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );

    if (customer.isEmpty) {
      continue;
    }

    final customerBillingId = _int(
      customer.first['billing_id'],
      fallback: 1,
    );

    if (customerBillingId <= 0) {
      continue;
    }

    final values = <String, dynamic>{};

    // Payment-এর Billing ID Customer-এর
    // Billing ID-এর সাথে মিলিয়ে নেওয়া।
    if (_int(payment['billing_id']) !=
        customerBillingId) {
      values['billing_id'] = customerBillingId;
    }

    // Payment-এর Bill ID সত্যিই একই Customer-এর
    // Bill-এর দিকে নির্দেশ করছে কি না যাচাই।
    if (billId > 0) {
      final bill = await db.query(
        'bills',
        columns: [
          'id',
          'customer_id',
          'billing_id',
        ],
        where: 'id = ?',
        whereArgs: [billId],
        limit: 1,
      );

      if (bill.isEmpty ||
          _int(bill.first['customer_id']) !=
              customerId ||
          _int(bill.first['billing_id']) !=
              customerBillingId) {
        values['bill_id'] = 0;
      }
    }

    if (values.isNotEmpty) {
      await db.update(
        'payments',
        values,
        where: 'id = ?',
        whereArgs: [paymentId],
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

      // Recalculated totals are derived values.
      // Do NOT change customers.updated_at here.
      // Otherwise a normal sync would make old customer master data
      // look newer than another device's real customer edit.
      await db.update(
        'customers',
        {
          'total_amount': totalBill,
          'paid_amount': totalPaid,
          'due_amount': due > 0 ? due : 0,
          'payment_date': latestPaymentDate,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    }
  
    Future<void> _pushRecalculatedCustomers(Database db) async {
    final rows = await db.query(
      'customers',
      columns: [
        'billing_id',
        'user_id',
        'total_amount',
        'paid_amount',
        'due_amount',
        'payment_date',
      ],
    );

    for (final row in rows) {
      final userId = _string(row['user_id']).trim();
      if (userId.isEmpty) continue;

      // Only derived billing totals are synchronized here.
      // Customer master information such as name, mobile, package,
      // bill date, status, etc. must never be overwritten by a
      // recalculation running on another device.
      await _setCloud(
        'customers',
        _key(
          '${_int(row['billing_id'], fallback: 1)}__$userId',
        ),
        {
          'total_amount': _double(row['total_amount']),
          'paid_amount': _double(row['paid_amount']),
          'due_amount': _double(row['due_amount']),
          'payment_date': _string(row['payment_date']),
          'cloud_updated_at': FieldValue.serverTimestamp(),
        },
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
