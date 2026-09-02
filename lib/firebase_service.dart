import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// Firebase service for Digital 24 Online Billing.
///
/// মূল উদ্দেশ্য:
/// 1. Firebase account-এর সাথে স্থায়ী cloud data রাখা
/// 2. SQLite দিয়ে offline কাজ চালানো
/// 3. Internet এলে local data cloud-এ sync করা
/// 4. App uninstall/reinstall হলেও একই account দিয়ে login করলে
///    cloud থেকে আগের customer/bill/payment/staff/package data ফেরত পাওয়া
/// 5. একাধিক device-এ একই business account ব্যবহার করা
class FirebaseService {
  FirebaseService._();

  static final FirebaseService instance = FirebaseService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ---------------------------------------------------------------------------
  // AUTH
  // ---------------------------------------------------------------------------

  User? get currentUser => _auth.currentUser;

  bool get isSignedIn => _auth.currentUser != null;

  String? get uid => _auth.currentUser?.uid;

  // ---------------------------------------------------------------------------
  // FIRESTORE REFERENCES
  // ---------------------------------------------------------------------------

  DocumentReference<Map<String, dynamic>> get _businessRef {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('User is not signed in.');
    }

    return _firestore.collection('businesses').doc(user.uid);
  }

  CollectionReference<Map<String, dynamic>> _collection(
    String name,
  ) {
    return _businessRef.collection(name);
  }

  // ---------------------------------------------------------------------------
  // ACCOUNT CREATE
  // ---------------------------------------------------------------------------

  Future<UserCredential> createAccount({
    required String email,
    required String password,
  }) async {
    final result = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    await _ensureBusinessDocument();

    return result;
  }

  // ---------------------------------------------------------------------------
  // LOGIN
  // ---------------------------------------------------------------------------

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    final result = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    await _ensureBusinessDocument();

    return result;
  }

  // ---------------------------------------------------------------------------
  // LOGOUT
  // ---------------------------------------------------------------------------

  Future<void> signOut() async {
    await _auth.signOut();
  }

  // ---------------------------------------------------------------------------
  // PASSWORD RESET
  // ---------------------------------------------------------------------------

  Future<void> sendPasswordResetEmail(
    String email,
  ) async {
    await _auth.sendPasswordResetEmail(
      email: email.trim(),
    );
  }

  // ---------------------------------------------------------------------------
  // BUSINESS MASTER DOCUMENT
  // ---------------------------------------------------------------------------

  Future<void> _ensureBusinessDocument() async {
    final user = _auth.currentUser;

    if (user == null) return;

    await _firestore
        .collection('businesses')
        .doc(user.uid)
        .set(
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

  // ---------------------------------------------------------------------------
  // CHECK FIRESTORE CONNECTION
  // ---------------------------------------------------------------------------

  Future<bool> cloudAvailable() async {
    if (!isSignedIn) {
      return false;
    }

    try {
      await _businessRef.get(
        const GetOptions(
          source: Source.server,
        ),
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // MAIN SYNC
  // ---------------------------------------------------------------------------

  /// Local SQLite -> Firebase Cloud -> Local SQLite
  ///
  /// Local database offline অবস্থায় কাজ চালিয়ে যাবে।
  /// Internet পাওয়া গেলে এই method চালালে cloud master update হবে।
  Future<void> syncNow() async {
    if (!isSignedIn) {
      throw StateError(
        'Please sign in first.',
      );
    }

    await _ensureBusinessDocument();

    await _uploadLocalData();

    await _restoreCloudData();
  }

  // ---------------------------------------------------------------------------
  // RESTORE AFTER LOGIN
  // ---------------------------------------------------------------------------

  /// Login করার পর এই method ব্যবহার করা হবে।
  ///
  /// নতুন install হলে local customer না থাকায়
  /// cloud থেকে data restore হবে।
  ///
  /// পুরোনো local data থাকলে normal synchronization হবে।
  Future<void> restoreAfterLogin() async {
    if (!isSignedIn) {
      return;
    }

    await _ensureBusinessDocument();

    final hasLocalData = await _hasLocalCustomerData();

    if (!hasLocalData) {
      await _restoreCloudData();
    } else {
      await syncNow();
    }
  }

  // ---------------------------------------------------------------------------
  // CHECK LOCAL CUSTOMER DATA
  // ---------------------------------------------------------------------------

  Future<bool> _hasLocalCustomerData() async {
    final db = await DatabaseHelper.instance.database;

    final result = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM customers',
    );

    if (result.isEmpty) {
      return false;
    }

    final total = _toInt(
      result.first['total'],
    );

    return total > 0;
  }

  // ---------------------------------------------------------------------------
  // UPLOAD ALL LOCAL TABLES
  // ---------------------------------------------------------------------------

  Future<void> _uploadLocalData() async {
    final db = await DatabaseHelper.instance.database;

    // Customers
    await _uploadTable(
      db: db,
      table: 'customers',
      collection: 'customers',
      keyBuilder: (row) {
        return _string(
          row['user_id'],
        );
      },
      converter: (row) async {
        return _customerToCloud(row);
      },
    );

    // Packages
    await _uploadTable(
      db: db,
      table: 'packages',
      collection: 'packages',
      keyBuilder: (row) {
        return _string(
          row['name'],
        );
      },
      converter: (row) async {
        return _packageToCloud(row);
      },
    );

    // Staff
    await _uploadTable(
      db: db,
      table: 'staff',
      collection: 'staff',
      keyBuilder: (row) {
        return _string(
          row['name'],
        );
      },
      converter: (row) async {
        return _staffToCloud(row);
      },
    );

    // Bills
    await _uploadTable(
      db: db,
      table: 'bills',
      collection: 'bills',
      keyBuilder: (row) {
        return '${_string(row['customer_id'])}'
            '__'
            '${_string(row['billing_month'])}';
      },
      converter: (row) async {
        return _billToCloud(
          db,
          row,
        );
      },
    );

    // Payments
    await _uploadTable(
      db: db,
      table: 'payments',
      collection: 'payments',
      keyBuilder: (row) {
        return _string(
          row['receipt_no'],
        );
      },
      converter: (row) async {
        return _paymentToCloud(
          db,
          row,
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // GENERIC TABLE UPLOAD
  // ---------------------------------------------------------------------------

  Future<void> _uploadTable({
    required Database db,
    required String table,
    required String collection,
    required String Function(
      Map<String, dynamic> row,
    ) keyBuilder,
    required Future<Map<String, dynamic>> Function(
      Map<String, dynamic> row,
    ) converter,
  }) async {
    final rows = await db.query(
      table,
    );

    // Firestore batch limit নিরাপদ রাখার জন্য।
    const batchSize = 350;

    for (
      int start = 0;
      start < rows.length;
      start += batchSize
    ) {
      final int end =
          (start + batchSize < rows.length)
              ? start + batchSize
              : rows.length;

      final batch = _firestore.batch();

      for (
        final row
        in rows.sublist(
          start,
          end,
        )
      ) {
        final rawKey = keyBuilder(
          row,
        );

        final documentId = _safeDocumentId(
          rawKey,
        );

        if (documentId.isEmpty) {
          continue;
        }

        final data = await converter(
          row,
        );

        data['cloud_updated_at'] =
            FieldValue.serverTimestamp();

        batch.set(
          _collection(
            collection,
          ).doc(
            documentId,
          ),
          data,
          SetOptions(
            merge: true,
          ),
        );
      }

      if (end > start) {
        await batch.commit();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // CUSTOMER -> CLOUD
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _customerToCloud(
    Map<String, dynamic> row,
  ) {
    return {
      'id_local': _toInt(
        row['id'],
      ),
      'user_id': _string(
        row['user_id'],
      ),
      'name': _string(
        row['name'],
      ),
      'mobile': _string(
        row['mobile'],
      ),
      'address': _string(
        row['address'],
      ),
      'package_id': _toInt(
        row['package_id'],
      ),
      'package_name': _string(
        row['package_name'],
      ),
      'bill_date': _string(
        row['bill_date'],
      ),
      'amount': _toDouble(
        row['amount'],
      ),
      'total_amount': _toDouble(
        row['total_amount'],
      ),
      'paid_amount': _toDouble(
        row['paid_amount'],
      ),
      'due_amount': _toDouble(
        row['due_amount'],
      ),
      'payment_date': _string(
        row['payment_date'],
      ),
      'status': _string(
        row['status'],
      ),
      'active': _toInt(
        row['active'],
        fallback: 1,
      ),
      'created_at': _string(
        row['created_at'],
      ),
      'updated_at': _string(
        row['updated_at'],
      ),
    };
  }

  // ---------------------------------------------------------------------------
  // PACKAGE -> CLOUD
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _packageToCloud(
    Map<String, dynamic> row,
  ) {
    return {
      'id_local': _toInt(
        row['id'],
      ),
      'name': _string(
        row['name'],
      ),
      'speed': _string(
        row['speed'],
      ),
      'price': _toDouble(
        row['price'],
      ),
      'active': _toInt(
        row['active'],
        fallback: 1,
      ),
      'created_at': _string(
        row['created_at'],
      ),
    };
  }

  // ---------------------------------------------------------------------------
  // STAFF -> CLOUD
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _staffToCloud(
    Map<String, dynamic> row,
  ) {
    return {
      'id_local': _toInt(
        row['id'],
      ),
      'name': _string(
        row['name'],
      ),
      'mobile': _string(
        row['mobile'],
      ),
      'active': _toInt(
        row['active'],
        fallback: 1,
      ),
      'created_at': _string(
        row['created_at'],
      ),
    };
  }

  // ---------------------------------------------------------------------------
  // BILL -> CLOUD
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _billToCloud(
    Database db,
    Map<String, dynamic> row,
  ) async {
    final customerRows = await db.query(
      'customers',
      columns: [
        'user_id',
      ],
      where: 'id = ?',
      whereArgs: [
        row['customer_id'],
      ],
      limit: 1,
    );

    final customerUserId =
        customerRows.isEmpty
            ? ''
            : _string(
                customerRows.first['user_id'],
              );

    return {
      'id_local': _toInt(
        row['id'],
      ),
      'customer_user_id': customerUserId,
      'billing_month': _string(
        row['billing_month'],
      ),
      'bill_date': _string(
        row['bill_date'],
      ),
      'amount': _toDouble(
        row['amount'],
      ),
      'created_at': _string(
        row['created_at'],
      ),
    };
  }

  // ---------------------------------------------------------------------------
  // PAYMENT -> CLOUD
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _paymentToCloud(
    Database db,
    Map<String, dynamic> row,
  ) async {
    String customerUserId = '';

    final customerRows = await db.query(
      'customers',
      columns: [
        'user_id',
      ],
      where: 'id = ?',
      whereArgs: [
        row['customer_id'],
      ],
      limit: 1,
    );

    if (customerRows.isNotEmpty) {
      customerUserId = _string(
        customerRows.first['user_id'],
      );
    }

    String billingMonth = '';

    final billId = row['bill_id'];

    if (billId != null) {
      final billRows = await db.query(
        'bills',
        columns: [
          'billing_month',
        ],
        where: 'id = ?',
        whereArgs: [
          billId,
        ],
        limit: 1,
      );

      if (billRows.isNotEmpty) {
        billingMonth = _string(
          billRows.first['billing_month'],
        );
      }
    }

    String staffName = '';

    final staffId = row['staff_id'];

    if (staffId != null) {
      final staffRows = await db.query(
        'staff',
        columns: [
          'name',
        ],
        where: 'id = ?',
        whereArgs: [
          staffId,
        ],
        limit: 1,
      );

      if (staffRows.isNotEmpty) {
        staffName = _string(
          staffRows.first['name'],
        );
      }
    }

    return {
      'id_local': _toInt(
        row['id'],
      ),
      'customer_user_id': customerUserId,
      'billing_month': billingMonth,
      'bill_id_local': _toInt(
        row['bill_id'],
      ),
      'user_id': _string(
        row['user_id'],
      ),
      'amount': _toDouble(
        row['amount'],
      ),
      'payment_date': _string(
        row['payment_date'],
      ),
      'receipt_no': _string(
        row['receipt_no'],
      ),
      'staff_id_local': _toInt(
        row['staff_id'],
      ),
      'staff_name': staffName,
      'note': _string(
        row['note'],
      ),
      'created_at': _string(
        row['created_at'],
      ),
    };
  }

  // ---------------------------------------------------------------------------
  // SAFE FIRESTORE DOCUMENT ID
  // ---------------------------------------------------------------------------

  String _safeDocumentId(
    String value,
  ) {
    var result = value.trim();

    if (result.isEmpty) {
      return '';
    }

    // Firestore document ID-তে '/' রাখা যায় না।
    result = result.replaceAll(
      '/',
      '_',
    );

    if (result == '.' ||
        result == '..') {
      result = '_$result';
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // VALUE CONVERTERS
  // ---------------------------------------------------------------------------

  static String _string(
    Object? value,
  ) {
    if (value == null) {
      return '';
    }

    return value.toString();
  }

  static int _toInt(
    Object? value, {
    int fallback = 0,
  }) {
    if (value == null) {
      return fallback;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          value.toString(),
        ) ??
        fallback;
  }

  static double _toDouble(
    Object? value, {
    double fallback = 0.0,
  }) {
    if (value == null) {
      return fallback;
    }

    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value.toString(),
        ) ??
        fallback;
  }
}
// ============================================================================
// PART 2 / 4
// CLOUD -> LOCAL RESTORE
// ============================================================================

  Future<void> _restoreCloudData() async {
    if (!isSignedIn) {
      throw StateError(
        'Please sign in first.',
      );
    }

    final db = await DatabaseHelper.instance.database;

    // Cloud থেকে সব collection পড়া হচ্ছে।
    final packages = await _readCloudCollection(
      'packages',
    );

    final staff = await _readCloudCollection(
      'staff',
    );

    final customers = await _readCloudCollection(
      'customers',
    );

    final bills = await _readCloudCollection(
      'bills',
    );

    final payments = await _readCloudCollection(
      'payments',
    );

    // সব data একই SQLite transaction-এর মধ্যে restore করা হবে।
    //
    // এতে মাঝপথে সমস্যা হলে অসম্পূর্ণ restore হওয়ার ঝুঁকি কমে।
    await db.transaction(
      (txn) async {
        await _restorePackages(
          txn,
          packages,
        );

        await _restoreStaff(
          txn,
          staff,
        );

        await _restoreCustomers(
          txn,
          customers,
        );

        await _restoreBills(
          txn,
          bills,
        );

        await _restorePayments(
          txn,
          payments,
        );

        // Payment restore হওয়ার পরে customer-এর
        // paid/due আবার হিসাব করা হবে।
        await _recalculateCustomerTotals(
          txn,
        );
      },
    );
  }

// ============================================================================
// READ CLOUD COLLECTION
// ============================================================================

  Future<List<Map<String, dynamic>>> _readCloudCollection(
    String collectionName,
  ) async {
    final snapshot = await _collection(
      collectionName,
    ).get();

    final result = <Map<String, dynamic>>[];

    for (final document in snapshot.docs) {
      final data = Map<String, dynamic>.from(
        document.data(),
      );

      // প্রয়োজন হলে debugging / future migration-এর জন্য
      // Firestore document ID-টিও রাখা হচ্ছে।
      data['_cloud_document_id'] = document.id;

      result.add(
        data,
      );
    }

    return result;
  }

// ============================================================================
// RESTORE PACKAGES
// ============================================================================

  Future<void> _restorePackages(
    Transaction txn,
    List<Map<String, dynamic>> rows,
  ) async {
    for (final row in rows) {
      final name = _string(
        row['name'],
      ).trim();

      if (name.isEmpty) {
        continue;
      }

      // Package-এর natural unique key হচ্ছে name।
      final existing = await txn.query(
        'packages',
        where: 'name = ?',
        whereArgs: [
          name,
        ],
        limit: 1,
      );

      final values = <String, dynamic>{
        'name': name,
        'speed': _string(
          row['speed'],
        ),
        'price': _toDouble(
          row['price'],
        ),
        'active': _toInt(
          row['active'],
          fallback: 1,
        ),
        'created_at': _string(
          row['created_at'],
        ),
      };

      if (existing.isEmpty) {
        await txn.insert(
          'packages',
          values,
        );
      } else {
        await txn.update(
          'packages',
          values,
          where: 'id = ?',
          whereArgs: [
            existing.first['id'],
          ],
        );
      }
    }
  }

// ============================================================================
// RESTORE STAFF
// ============================================================================

  Future<void> _restoreStaff(
    Transaction txn,
    List<Map<String, dynamic>> rows,
  ) async {
    for (final row in rows) {
      final name = _string(
        row['name'],
      ).trim();

      if (name.isEmpty) {
        continue;
      }

      // Staff-এর natural unique key হচ্ছে name।
      final existing = await txn.query(
        'staff',
        where: 'name = ?',
        whereArgs: [
          name,
        ],
        limit: 1,
      );

      final values = <String, dynamic>{
        'name': name,
        'mobile': _string(
          row['mobile'],
        ),
        'active': _toInt(
          row['active'],
          fallback: 1,
        ),
        'created_at': _string(
          row['created_at'],
        ),
      };

      if (existing.isEmpty) {
        await txn.insert(
          'staff',
          values,
        );
      } else {
        await txn.update(
          'staff',
          values,
          where: 'id = ?',
          whereArgs: [
            existing.first['id'],
          ],
        );
      }
    }
  }

// ============================================================================
// RESTORE CUSTOMERS
// ============================================================================

  Future<void> _restoreCustomers(
    Transaction txn,
    List<Map<String, dynamic>> rows,
  ) async {
    for (final row in rows) {
      final userId = _string(
        row['user_id'],
      ).trim();

      if (userId.isEmpty) {
        continue;
      }

      // User ID-ই customer-এর permanent natural key।
      //
      // Local SQLite id device বদলালে পরিবর্তিত হতে পারে।
      // কিন্তু User ID একই থাকবে।
      final existing = await txn.query(
        'customers',
        where: 'user_id = ?',
        whereArgs: [
          userId,
        ],
        limit: 1,
      );

      int? packageId;

      final packageName = _string(
        row['package_name'],
      ).trim();

      if (packageName.isNotEmpty) {
        final packageRows = await txn.query(
          'packages',
          columns: [
            'id',
          ],
          where: 'name = ?',
          whereArgs: [
            packageName,
          ],
          limit: 1,
        );

        if (packageRows.isNotEmpty) {
          packageId = _toInt(
            packageRows.first['id'],
          );
        }
      }

      final values = <String, dynamic>{
        'user_id': userId,
        'name': _string(
          row['name'],
        ),
        'mobile': _string(
          row['mobile'],
        ),
        'address': _string(
          row['address'],
        ),
        'package_id': packageId,
        'package_name': packageName,
        'bill_date': _string(
          row['bill_date'],
        ),
        'amount': _toDouble(
          row['amount'],
        ),
        'total_amount': _toDouble(
          row['total_amount'],
        ),
        'paid_amount': _toDouble(
          row['paid_amount'],
        ),
        'due_amount': _toDouble(
          row['due_amount'],
        ),
        'payment_date': _string(
          row['payment_date'],
        ),
        'status': _string(
          row['status'],
        ),
        'active': _toInt(
          row['active'],
          fallback: 1,
        ),
        'created_at': _string(
          row['created_at'],
        ),
        'updated_at': _string(
          row['updated_at'],
        ),
      };

      if (existing.isEmpty) {
        await txn.insert(
          'customers',
          values,
        );
      } else {
        await txn.update(
          'customers',
          values,
          where: 'id = ?',
          whereArgs: [
            existing.first['id'],
          ],
        );
      }
    }
  }

// ============================================================================
// RESTORE BILLS
// ============================================================================

  Future<void> _restoreBills(
    Transaction txn,
    List<Map<String, dynamic>> rows,
  ) async {
    for (final row in rows) {
      final customerUserId = _string(
        row['customer_user_id'],
      ).trim();

      final billingMonth = _string(
        row['billing_month'],
      ).trim();

      if (customerUserId.isEmpty ||
          billingMonth.isEmpty) {
        continue;
      }

      // Cloud-এর customer_user_id দিয়ে local customer খুঁজে বের করা।
      final customerRows = await txn.query(
        'customers',
        columns: [
          'id',
        ],
        where: 'user_id = ?',
        whereArgs: [
          customerUserId,
        ],
        limit: 1,
      );

      if (customerRows.isEmpty) {
        // Customer না থাকলে bill insert করা যাবে না।
        continue;
      }

      final customerId =
          customerRows.first['id'];

      // একই customer + একই billing month = একই bill।
      final existing = await txn.query(
        'bills',
        where:
            'customer_id = ? AND billing_month = ?',
        whereArgs: [
          customerId,
          billingMonth,
        ],
        limit: 1,
      );

      final values = <String, dynamic>{
        'customer_id': customerId,
        'billing_month': billingMonth,
        'bill_date': _string(
          row['bill_date'],
        ),
        'amount': _toDouble(
          row['amount'],
        ),
        'created_at': _string(
          row['created_at'],
        ),
      };

      if (existing.isEmpty) {
        await txn.insert(
          'bills',
          values,
        );
      } else {
        await txn.update(
          'bills',
          values,
          where: 'id = ?',
          whereArgs: [
            existing.first['id'],
          ],
        );
      }
    }
  }

// ============================================================================
// RESTORE PAYMENTS
// ============================================================================

  Future<void> _restorePayments(
    Transaction txn,
    List<Map<String, dynamic>> rows,
  ) async {
    for (final row in rows) {
      final receiptNo = _string(
        row['receipt_no'],
      ).trim();

      final customerUserId = _string(
        row['customer_user_id'],
      ).trim();

      if (receiptNo.isEmpty ||
          customerUserId.isEmpty) {
        continue;
      }

      // Customer lookup।
      final customerRows = await txn.query(
        'customers',
        columns: [
          'id',
        ],
        where: 'user_id = ?',
        whereArgs: [
          customerUserId,
        ],
        limit: 1,
      );

      if (customerRows.isEmpty) {
        continue;
      }

      final customerId =
          customerRows.first['id'];

      // -----------------------------------------------------------------------
      // BILL ID
      // -----------------------------------------------------------------------

      int? billId;

      final billingMonth = _string(
        row['billing_month'],
      ).trim();

      if (billingMonth.isNotEmpty) {
        final billRows = await txn.query(
          'bills',
          columns: [
            'id',
          ],
          where:
              'customer_id = ? AND billing_month = ?',
          whereArgs: [
            customerId,
            billingMonth,
          ],
          limit: 1,
        );

        if (billRows.isNotEmpty) {
          billId = _toInt(
            billRows.first['id'],
          );
        }
      }

      // -----------------------------------------------------------------------
      // STAFF ID
      // -----------------------------------------------------------------------

      int? staffId;

      final staffName = _string(
        row['staff_name'],
      ).trim();

      if (staffName.isNotEmpty) {
        final staffRows = await txn.query(
          'staff',
          columns: [
            'id',
          ],
          where: 'name = ?',
          whereArgs: [
            staffName,
          ],
          limit: 1,
        );

        if (staffRows.isNotEmpty) {
          staffId = _toInt(
            staffRows.first['id'],
          );
        }
      }

      // -----------------------------------------------------------------------
      // PAYMENT VALUES
      // -----------------------------------------------------------------------

      final values = <String, dynamic>{
        'customer_id': customerId,
        'bill_id': billId,
        'user_id': customerUserId,
        'amount': _toDouble(
          row['amount'],
        ),
        'payment_date': _string(
          row['payment_date'],
        ),
        'receipt_no': receiptNo,
        'staff_id': staffId,
        'note': _string(
          row['note'],
        ),
        'created_at': _string(
          row['created_at'],
        ),
      };

      // Receipt No. হচ্ছে payment-এর permanent natural key।
      final existing = await txn.query(
        'payments',
        where: 'receipt_no = ?',
        whereArgs: [
          receiptNo,
        ],
        limit: 1,
      );

      if (existing.isEmpty) {
        await txn.insert(
          'payments',
          values,
        );
      } else {
        await txn.update(
          'payments',
          values,
          where: 'id = ?',
          whereArgs: [
            existing.first['id'],
          ],
        );
      }
    }
  }

// ============================================================================
// RECALCULATE CUSTOMER TOTALS
// ============================================================================

  Future<void> _recalculateCustomerTotals(
    Transaction txn,
  ) async {
    final customers = await txn.query(
      'customers',
    );

    for (final customer in customers) {
      final customerId =
          customer['id'];

      // ঐ customer-এর সব payment যোগ করা।
      final paymentResult =
          await txn.rawQuery(
        '''
        SELECT COALESCE(SUM(amount), 0) AS total
        FROM payments
        WHERE customer_id = ?
        ''',
        [
          customerId,
        ],
      );

      final paidAmount = _toDouble(
        paymentResult.isEmpty
            ? 0
            : paymentResult.first['total'],
      );

      // Total amount না থাকলে package/bill amount fallback হিসেবে ব্যবহার।
      double totalAmount =
          _toDouble(
        customer['total_amount'],
      );

      if (totalAmount <= 0) {
        totalAmount = _toDouble(
          customer['amount'],
        );
      }

      double dueAmount =
          totalAmount - paidAmount;

      if (dueAmount < 0) {
        dueAmount = 0;
      }

      await txn.update(
        'customers',
        {
          'paid_amount': paidAmount,
          'due_amount': dueAmount,
          'updated_at':
              DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [
          customerId,
        ],
      );
    }
  }

  Future<void> _restorePayments(
    DatabaseExecutor txn,
    List<Map<String, dynamic>> rows,
  ) async {
    for (final cloud in rows) {
      final receiptNo = _string(cloud['receipt_no']);

      if (receiptNo.isEmpty) {
        continue;
      }

      final customerUserId = _string(cloud['customer_user_id']);
      final billingMonth = _string(cloud['billing_month']);

      int? customerId;
      int? billId;

      if (customerUserId.isNotEmpty) {
        final customerRows = await txn.query(
          'customers',
          columns: ['id'],
          where: 'user_id = ?',
          whereArgs: [customerUserId],
          limit: 1,
        );

        if (customerRows.isNotEmpty) {
          customerId = _toInt(customerRows.first['id']);
        }
      }

      if (customerId != null && billingMonth.isNotEmpty) {
        final billRows = await txn.query(
          'bills',
          columns: ['id'],
          where: 'customer_id = ? AND billing_month = ?',
          whereArgs: [customerId, billingMonth],
          limit: 1,
        );

        if (billRows.isNotEmpty) {
          billId = _toInt(billRows.first['id']);
        }
      }

      final data = <String, dynamic>{
        'customer_id': customerId,
        'bill_id': billId,
        'user_id': customerUserId,
        'amount': _toDouble(cloud['amount']),
        'payment_date': _string(cloud['payment_date']),
        'receipt_no': receiptNo,
        'staff_id': _toIntOrNull(cloud['staff_id']),
        'note': _string(cloud['note']),
        'created_at': _string(cloud['created_at']).isEmpty
            ? DateTime.now().toIso8601String()
            : _string(cloud['created_at']),
      };

      final existing = await txn.query(
        'payments',
        columns: ['id'],
        where: 'receipt_no = ?',
        whereArgs: [receiptNo],
        limit: 1,
      );

      if (existing.isEmpty) {
        await txn.insert(
          'payments',
          data,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      } else {
        await txn.update(
          'payments',
          data,
          where: 'receipt_no = ?',
          whereArgs: [receiptNo],
        );
      }
    }
  }

  Future<void> _restoreBills(
    DatabaseExecutor txn,
    List<Map<String, dynamic>> rows,
  ) async {
    for (final cloud in rows) {
      final customerUserId = _string(cloud['customer_user_id']);
      final billingMonth = _string(cloud['billing_month']);

      if (customerUserId.isEmpty || billingMonth.isEmpty) {
        continue;
      }

      final customerRows = await txn.query(
        'customers',
        columns: ['id'],
        where: 'user_id = ?',
        whereArgs: [customerUserId],
        limit: 1,
      );

      if (customerRows.isEmpty) {
        continue;
      }

      final customerId = _toInt(customerRows.first['id']);

      final data = <String, dynamic>{
        'customer_id': customerId,
        'billing_month': billingMonth,
        'bill_date': _string(cloud['bill_date']),
        'amount': _toDouble(cloud['amount']),
        'created_at': _string(cloud['created_at']).isEmpty
            ? DateTime.now().toIso8601String()
            : _string(cloud['created_at']),
      };

      final existing = await txn.query(
        'bills',
        columns: ['id'],
        where: 'customer_id = ? AND billing_month = ?',
        whereArgs: [customerId, billingMonth],
        limit: 1,
      );

      if (existing.isEmpty) {
        await txn.insert(
          'bills',
          data,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      } else {
        await txn.update(
          'bills',
          data,
          where: 'customer_id = ? AND billing_month = ?',
          whereArgs: [customerId, billingMonth],
        );
      }
    }
  }

  Future<void> _restoreCustomers(
    DatabaseExecutor txn,
    List<Map<String, dynamic>> rows,
  ) async {
    for (final cloud in rows) {
      final userId = _string(cloud['user_id']);

      if (userId.isEmpty) {
        continue;
      }

      final data = <String, dynamic>{
        'user_id': userId,
        'name': _string(cloud['name']),
        'mobile': _string(cloud['mobile']),
        'address': _string(cloud['address']),
        'package_id': _toIntOrNull(cloud['package_id']),
        'package_name': _string(cloud['package_name']),
        'bill_date': _string(cloud['bill_date']),
        'amount': _toDouble(cloud['amount']),
        'total_amount': _toDouble(cloud['total_amount']),
        'paid_amount': _toDouble(cloud['paid_amount']),
        'due_amount': _toDouble(cloud['due_amount']),
        'payment_date': _string(cloud['payment_date']),
        'status': _string(cloud['status']).isEmpty
            ? 'active'
            : _string(cloud['status']),
        'active': _toInt(cloud['active']) == 0 ? 0 : 1,
        'created_at': _string(cloud['created_at']).isEmpty
            ? DateTime.now().toIso8601String()
            : _string(cloud['created_at']),
        'updated_at': _string(cloud['updated_at']).isEmpty
            ? DateTime.now().toIso8601String()
            : _string(cloud['updated_at']),
      };

      final existing = await txn.query(
        'customers',
        columns: ['id'],
        where: 'user_id = ?',
        whereArgs: [userId],
        limit: 1,
      );

      if (existing.isEmpty) {
        await txn.insert(
          'customers',
          data,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      } else {
        await txn.update(
          'customers',
          data,
          where: 'user_id = ?',
          whereArgs: [userId],
        );
      }
    }
  }

  Future<void> _restorePackages(
    DatabaseExecutor txn,
    List<Map<String, dynamic>> rows,
  ) async {
    for (final cloud in rows) {
      final name = _string(cloud['name']);

      if (name.isEmpty) {
        continue;
      }

      final data = <String, dynamic>{
        'name': name,
        'speed': _string(cloud['speed']),
        'price': _toDouble(cloud['price']),
        'active': _toInt(cloud['active']) == 0 ? 0 : 1,
        'created_at': _string(cloud['created_at']).isEmpty
            ? DateTime.now().toIso8601String()
            : _string(cloud['created_at']),
      };

      final existing = await txn.query(
        'packages',
        columns: ['id'],
        where: 'name = ?',
        whereArgs: [name],
        limit: 1,
      );

      if (existing.isEmpty) {
        await txn.insert(
          'packages',
          data,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      } else {
        await txn.update(
          'packages',
          data,
          where: 'name = ?',
          whereArgs: [name],
        );
      }
    }
  }

  Future<void> _restoreStaff(
    DatabaseExecutor txn,
    List<Map<String, dynamic>> rows,
  ) async {
    for (final cloud in rows) {
      final name = _string(cloud['name']);

      if (name.isEmpty) {
        continue;
      }

      final data = <String, dynamic>{
        'name': name,
        'mobile': _string(cloud['mobile']),
        'active': _toInt(cloud['active']) == 0 ? 0 : 1,
        'created_at': _string(cloud['created_at']).isEmpty
            ? DateTime.now().toIso8601String()
            : _string(cloud['created_at']),
      };

      final existing = await txn.query(
        'staff',
        columns: ['id'],
        where: 'name = ?',
        whereArgs: [name],
        limit: 1,
      );

      if (existing.isEmpty) {
        await txn.insert(
          'staff',
          data,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      } else {
        await txn.update(
          'staff',
          data,
          where: 'name = ?',
          whereArgs: [name],
        );
      }
    }
  }

  int? _toIntOrNull(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return int.tryParse(text);
  }

  Future<void> _repairPaymentRelations(
    DatabaseExecutor txn,
  ) async {
    final payments = await txn.query(
      'payments',
      columns: [
        'id',
        'user_id',
        'customer_id',
        'bill_id',
      ],
    );

    for (final payment in payments) {
      final paymentId = _toInt(payment['id']);

      if (paymentId <= 0) {
        continue;
      }

      final userId = _string(payment['user_id']);

      int? customerId = _toIntOrNull(payment['customer_id']);
      int? billId = _toIntOrNull(payment['bill_id']);

      if (customerId == null && userId.isNotEmpty) {
        final customerRows = await txn.query(
          'customers',
          columns: ['id'],
          where: 'user_id = ?',
          whereArgs: [userId],
          limit: 1,
        );

        if (customerRows.isNotEmpty) {
          customerId = _toIntOrNull(customerRows.first['id']);
        }
      }

      if (customerId != null && billId == null) {
        final billRows = await txn.query(
          'bills',
          columns: ['id'],
          where: 'customer_id = ?',
          whereArgs: [customerId],
          orderBy: 'id DESC',
          limit: 1,
        );

        if (billRows.isNotEmpty) {
          billId = _toIntOrNull(billRows.first['id']);
        }
      }

      await txn.update(
        'payments',
        {
          'customer_id': customerId,
          'bill_id': billId,
        },
        where: 'id = ?',
        whereArgs: [paymentId],
      );
    }
  }

  Future<void> _repairBillRelations(
    DatabaseExecutor txn,
  ) async {
    final bills = await txn.query(
      'bills',
      columns: [
        'id',
        'customer_id',
      ],
    );

    for (final bill in bills) {
      final billId = _toInt(bill['id']);
      final customerId = _toIntOrNull(bill['customer_id']);

      if (billId <= 0 || customerId == null) {
        continue;
      }

      final customerRows = await txn.query(
        'customers',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [customerId],
        limit: 1,
      );

      if (customerRows.isEmpty) {
        await txn.update(
          'bills',
          {
            'customer_id': null,
          },
          where: 'id = ?',
          whereArgs: [billId],
        );
      }
    }
  }

  Future<void> _recalculateAllCustomerBalances(
    DatabaseExecutor txn,
  ) async {
    final customers = await txn.query(
      'customers',
      columns: [
        'id',
        'amount',
        'total_amount',
      ],
    );

    for (final customer in customers) {
      final customerId = _toInt(customer['id']);

      if (customerId <= 0) {
        continue;
      }

      final paymentRows = await txn.rawQuery(
        '''
        SELECT COALESCE(SUM(amount), 0) AS total_paid
        FROM payments
        WHERE customer_id = ?
        ''',
        [customerId],
      );

      final paid =
          _toDouble(paymentRows.first['total_paid']);

      final amount =
          _toDouble(customer['amount']);

      final totalAmount =
          _toDouble(customer['total_amount']);

      final baseAmount =
          totalAmount > 0 ? totalAmount : amount;

      final due =
          baseAmount - paid;

      await txn.update(
        'customers',
        {
          'paid_amount': paid,
          'due_amount': due > 0 ? due : 0.0,
        },
        where: 'id = ?',
        whereArgs: [customerId],
      );
    }
  }
  Future<void> _repairCustomerPackageRelations(
    DatabaseExecutor txn,
  ) async {
    final customers = await txn.query(
      'customers',
      columns: [
        'id',
        'package_id',
        'package_name',
      ],
    );

    for (final customer in customers) {
      final customerId = _toInt(customer['id']);

      if (customerId <= 0) {
        continue;
      }

      final packageId = _toIntOrNull(customer['package_id']);
      final packageName = _string(customer['package_name']);

      if (packageId != null) {
        final packageRows = await txn.query(
          'packages',
          columns: ['id', 'name'],
          where: 'id = ?',
          whereArgs: [packageId],
          limit: 1,
        );

        if (packageRows.isNotEmpty) {
          final actualName =
              _string(packageRows.first['name']);

          await txn.update(
            'customers',
            {
              'package_name': actualName,
            },
            where: 'id = ?',
            whereArgs: [customerId],
          );

          continue;
        }
      }

      if (packageName.isNotEmpty) {
        final packageRows = await txn.query(
          'packages',
          columns: ['id', 'name'],
          where: 'name = ?',
          whereArgs: [packageName],
          limit: 1,
        );

        if (packageRows.isNotEmpty) {
          final actualId =
              _toIntOrNull(packageRows.first['id']);

          await txn.update(
            'customers',
            {
              'package_id': actualId,
              'package_name': packageName,
            },
            where: 'id = ?',
            whereArgs: [customerId],
          );
        }
      }
    }
  }

  Future<void> _repairStaffRelations(
    DatabaseExecutor txn,
  ) async {
    final payments = await txn.query(
      'payments',
      columns: [
        'id',
        'staff_id',
      ],
    );

    for (final payment in payments) {
      final paymentId = _toInt(payment['id']);

      if (paymentId <= 0) {
        continue;
      }

      final staffId =
          _toIntOrNull(payment['staff_id']);

      if (staffId == null) {
        continue;
      }

      final staffRows = await txn.query(
        'staff',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [staffId],
        limit: 1,
      );

      if (staffRows.isEmpty) {
        await txn.update(
          'payments',
          {
            'staff_id': null,
          },
          where: 'id = ?',
          whereArgs: [paymentId],
        );
      }
    }
  }

  Future<void> _runDatabaseRepairs(
    DatabaseExecutor txn,
  ) async {
    await _repairCustomerPackageRelations(txn);
    await _repairBillRelations(txn);
    await _repairPaymentRelations(txn);
    await _repairStaffRelations(txn);
    await _recalculateAllCustomerBalances(txn);
  }

  Future<bool> hasCloudData() async {
    if (!isSignedIn) {
      return false;
    }

    try {
      final collections = <String>[
        'customers',
        'packages',
        'staff',
        'bills',
        'payments',
      ];

      for (final name in collections) {
        final snapshot = await _collection(name)
            .limit(1)
            .get();

        if (snapshot.docs.isNotEmpty) {
          return true;
        }
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  Future<int> cloudCustomerCount() async {
    if (!isSignedIn) {
      return 0;
    }

    try {
      final snapshot = await _collection('customers').get();
      return snapshot.docs.length;
    } catch (_) {
      return 0;
    }
  }

  Future<int> cloudPaymentCount() async {
    if (!isSignedIn) {
      return 0;
    }

    try {
      final snapshot = await _collection('payments').get();
      return snapshot.docs.length;
    } catch (_) {
      return 0;
    }
  }

  Future<Map<String, int>> cloudCounts() async {
    if (!isSignedIn) {
      return {
        'customers': 0,
        'packages': 0,
        'staff': 0,
        'bills': 0,
        'payments': 0,
      };
    }

    final result = <String, int>{
      'customers': 0,
      'packages': 0,
      'staff': 0,
      'bills': 0,
      'payments': 0,
    };

    for (final name in result.keys.toList()) {
      try {
        final snapshot =
            await _collection(name).get();

        result[name] = snapshot.docs.length;
      } catch (_) {
        result[name] = 0;
      }
    }

    return result;
  }

  Future<void> deleteCloudData() async {
    if (!isSignedIn) {
      throw Exception(
        'Firebase account is not signed in.',
      );
    }

    final names = <String>[
      'payments',
      'bills',
      'customers',
      'packages',
      'staff',
    ];

    for (final name in names) {
      final snapshot =
          await _collection(name).get();

      if (snapshot.docs.isEmpty) {
        continue;
      }

      final docs = snapshot.docs;

      const batchSize = 400;

      for (int start = 0;
          start < docs.length;
          start += batchSize) {
        final end =
            (start + batchSize < docs.length)
                ? start + batchSize
                : docs.length;

        final batch = _firestore.batch();

        for (final doc
            in docs.sublist(start, end)) {
          batch.delete(doc.reference);
        }

        await batch.commit();
      }
    }
  }

  Future<void> forceUploadLocalToCloud() async {
    if (!isSignedIn) {
      throw Exception(
        'Firebase account is not signed in.',
      );
    }

    await _ensureBusinessDocument();
    await _uploadLocalData();
  }

  Future<void> forceRestoreCloudToLocal() async {
    if (!isSignedIn) {
      throw Exception(
        'Firebase account is not signed in.',
      );
    }

    await _restoreCloudData();
  }

  Future<void> syncIfSignedIn() async {
    if (!isSignedIn) {
      return;
    }

    await syncNow();
  }

  Future<void> restoreIfSignedIn() async {
    if (!isSignedIn) {
      return;
    }

    await restoreAfterLogin();
  }

  Stream<User?> authStateChanges() {
    return _auth.authStateChanges();
  }

  Future<void> dispose() async {
    try {
      await DatabaseHelper.instance.closeDatabase();
    } catch (_) {
      // Database may already be closed.
    }
  }
}
