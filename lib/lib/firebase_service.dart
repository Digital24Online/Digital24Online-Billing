import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// Digital 24 Online Billing
/// Firebase Authentication + Cloud Firestore Master Sync
///
/// গুরুত্বপূর্ণ:
/// - Local SQLite = Offline working database
/// - Firestore = Cloud Master Database
/// - Stable business identifiers are used instead of local SQLite IDs
/// - This prevents different devices from overwriting each other's records
class FirebaseService {
FirebaseService._();

static final FirebaseService instance = FirebaseService._();

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore =
FirebaseFirestore.instance;

DatabaseHelper get _local => DatabaseHelper.instance;

User? get currentUser => _auth.currentUser;

bool get isSignedIn => currentUser != null;

String? get uid => currentUser?.uid;

// ============================================================
// AUTHENTICATION
// ============================================================

Future<UserCredential> createAccount({
required String email,
required String password,
}) async {
final cleanEmail = email.trim();

if (cleanEmail.isEmpty) {
  throw ArgumentError('Email is required.');
}

if (password.length < 6) {
  throw ArgumentError(
    'Password must be at least 6 characters.',
  );
}

final credential =
    await _auth.createUserWithEmailAndPassword(
  email: cleanEmail,
  password: password,
);

await _createBusinessProfile(
  credential.user!,
  cleanEmail,
);

return credential;

}

Future<UserCredential> signIn({
required String email,
required String password,
}) async {
final cleanEmail = email.trim();

final credential =
    await _auth.signInWithEmailAndPassword(
  email: cleanEmail,
  password: password,
);

return credential;

}

Future<void> signOut() async {
await _auth.signOut();
}

Future<void> sendPasswordResetEmail(
String email,
) async {
await _auth.sendPasswordResetEmail(
email: email.trim(),
);
}

// ============================================================
// BUSINESS PROFILE
// ============================================================

Future<void> _createBusinessProfile(
User user,
String email,
) async {
await _firestore
.collection('businesses')
.doc(user.uid)
.set(
{
'email': email,
'company_name': 'Digital 24 Online Billing',
'address':
'Seroil Colony, 4 No. Road, Ghoramara, Chandrima Rajshahi-6100',
'created_at': FieldValue.serverTimestamp(),
'updated_at': FieldValue.serverTimestamp(),
},
SetOptions(merge: true),
);
}

// ============================================================
// ROOT CLOUD REFERENCE
// ============================================================

DocumentReference<Map<String, dynamic>>
get _businessRef {
final user = currentUser;

if (user == null) {
  throw StateError(
    'Firebase account is not signed in.',
  );
}

return _firestore
    .collection('businesses')
    .doc(user.uid);

}

CollectionReference<Map<String, dynamic>>
_collection(String name) {
return _businessRef.collection(name);
}

// ============================================================
// FULL CLOUD SYNC
// ============================================================

/// Uploads the current Local SQLite data to Cloud.
///
/// This method DOES NOT delete Cloud documents.
/// It only creates/updates the local records.
///
/// This is intentional so an accidental local deletion cannot
/// immediately destroy the Cloud Master Database.
Future<void> uploadLocalData() async {
_requireSignedIn();

final db = await _local.database;

await _uploadCustomers(db);
await _uploadPackages(db);
await _uploadStaff(db);
await _uploadBills(db);
await _uploadPayments(db);

}

/// Downloads Cloud Master data and merges it into Local SQLite.
///
/// Cloud data is treated as the recovery source.
/// Existing local records are updated where their stable business
/// identifier matches.
Future<void> restoreCloudData() async {
_requireSignedIn();

final db = await _local.database;

await db.transaction(
  (txn) async {
    await _restoreCustomers(txn);
    await _restorePackages(txn);
    await _restoreStaff(txn);
    await _restoreBills(txn);
    await _restorePayments(txn);
  },
);

}

/// Main synchronization entry point.
///
/// First downloads Cloud Master data, then uploads local changes.
/// Cloud records are never blindly deleted.
Future<void> syncNow() async {
_requireSignedIn();

await restoreCloudData();
await uploadLocalData();

}

// ============================================================
// CUSTOMERS
// Stable ID = user_id
// ============================================================

Future<void> _uploadCustomers(Database db) async {
final rows = await db.query('customers');

await _writeChunks(
  'customers',
  rows.map((row) {
    final userId =
        row['user_id']?.toString().trim() ?? '';

    return _CloudRecord(
      documentId: _safeId(userId),
      data: _cleanData({
        ...row,
        'local_id': row['id'],
        'user_id': userId,
        'synced_at': FieldValue.serverTimestamp(),
      }),
    );
  }).where((r) => r.documentId.isNotEmpty).toList(),
);

}

Future<void> _restoreCustomers(
DatabaseExecutor db,
) async {
final snapshot =
await _collection('customers').get();

for (final doc in snapshot.docs) {
  final data = doc.data();

  final userId =
      data['user_id']?.toString().trim() ?? '';

  if (userId.isEmpty) continue;

  final existing = await db.query(
    'customers',
    where: 'user_id = ?',
    whereArgs: [userId],
    limit: 1,
  );

  final values = _customerValues(data);

  if (existing.isEmpty) {
    await db.insert(
      'customers',
      values,
      conflictAlgorithm:
          ConflictAlgorithm.ignore,
    );
  } else {
    await db.update(
      'customers',
      values,
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }
}

}

// ============================================================
// PACKAGES
// Stable ID = package name
// ============================================================

Future<void> _uploadPackages(Database db) async {
final rows = await db.query('packages');

await _writeChunks(
  'packages',
  rows.map((row) {
    final name =
        row['name']?.toString().trim() ?? '';

    return _CloudRecord(
      documentId: _safeId(name),
      data: _cleanData({
        ...row,
        'local_id': row['id'],
        'name': name,
        'synced_at': FieldValue.serverTimestamp(),
      }),
    );
  }).where((r) => r.documentId.isNotEmpty).toList(),
);

}

Future<void> _restorePackages(
DatabaseExecutor db,
) async {
final snapshot =
await _collection('packages').get();

for (final doc in snapshot.docs) {
  final data = doc.data();

  final name =
      data['name']?.toString().trim() ?? '';

  if (name.isEmpty) continue;

  final values = {
    'name': name,
    'speed': data['speed']?.toString() ?? '',
    'price': _doubleValue(data['price']),
    'active': _intValue(data['active'], 1),
    'created_at':
        data['created_at']?.toString() ??
            DateTime.now().toIso8601String(),
  };

  final existing = await db.query(
    'packages',
    where: 'name = ?',
    whereArgs: [name],
    limit: 1,
  );

  if (existing.isEmpty) {
    await db.insert(
      'packages',
      values,
      conflictAlgorithm:
          ConflictAlgorithm.ignore,
    );
  } else {
    await db.update(
      'packages',
      values,
      where: 'name = ?',
      whereArgs: [name],
    );
  }
}

}

// ============================================================
// STAFF
// Stable ID = staff name
// ============================================================

Future<void> _uploadStaff(Database db) async {
final rows = await db.query('staff');

await _writeChunks(
  'staff',
  rows.map((row) {
    final name =
        row['name']?.toString().trim() ?? '';

    return _CloudRecord(
      documentId: _safeId(name),
      data: _cleanData({
        ...row,
        'local_id': row['id'],
        'name': name,
        'synced_at': FieldValue.serverTimestamp(),
      }),
    );
  }).where((r) => r.documentId.isNotEmpty).toList(),
);

}

Future<void> _restoreStaff(
DatabaseExecutor db,
) async {
final snapshot =
await _collection('staff').get();

for (final doc in snapshot.docs) {
  final data = doc.data();

  final name =
      data['name']?.toString().trim() ?? '';

  if (name.isEmpty) continue;

  final values = {
    'name': name,
    'mobile': data['mobile']?.toString() ?? '',
    'active': _intValue(data['active'], 1),
    'created_at':
        data['created_at']?.toString() ??
            DateTime.now().toIso8601String(),
  };

  final existing = await db.query(
    'staff',
    where: 'name = ?',
    whereArgs: [name],
    limit: 1,
  );

  if (existing.isEmpty) {
    await db.insert(
      'staff',
      values,
      conflictAlgorithm:
          ConflictAlgorithm.ignore,
    );
  } else {
    await db.update(
      'staff',
      values,
      where: 'name = ?',
      whereArgs: [name],
    );
  }
}

}

// ============================================================
// BILLS
// Stable ID = customer user_id + billing month
// ============================================================

Future<void> _uploadBills(Database db) async {
final rows = await db.rawQuery('''
SELECT
bills.*,
customers.user_id AS customer_user_id
FROM bills
LEFT JOIN customers
ON customers.id = bills.customer_id
''');

await _writeChunks(
  'bills',
  rows.map((row) {
    final userId =
        row['customer_user_id']?.toString() ?? '';

    final month =
        row['billing_month']?.toString() ?? '';

    final docId =
        '${_safeId(userId)}__${_safeId(month)}';

    return _CloudRecord(
      documentId: docId,
      data: _cleanData({
        ...row,
        'local_id': row['id'],
        'customer_user_id': userId,
        'synced_at': FieldValue.serverTimestamp(),
      }),
    );
  }).where((r) => r.documentId.isNotEmpty).toList(),
);

}

Future<void> _restoreBills(
DatabaseExecutor db,
) async {
final snapshot =
await _collection('bills').get();

for (final doc in snapshot.docs) {
  final data = doc.data();

  final userId =
      data['customer_user_id']?.toString() ?? '';

  final month =
      data['billing_month']?.toString() ?? '';

  if (userId.isEmpty || month.isEmpty) {
    continue;
  }

  final customer = await db.query(
    'customers',
    columns: ['id'],
    where: 'user_id = ?',
    whereArgs: [userId],
    limit: 1,
  );

  if (customer.isEmpty) continue;

  final customerId =
      customer.first['id'] as int;

  final values = {
    'customer_id': customerId,
    'billing_month': month,
    'bill_date':
        _intValue(data['bill_date'], 7),
    'amount': _doubleValue(data['amount']),
    'created_at':
        data['created_at']?.toString() ??
            DateTime.now().toIso8601String(),
  };

  final existing = await db.query(
    'bills',
    where:
        'customer_id = ? AND billing_month = ?',
    whereArgs: [customerId, month],
    limit: 1,
  );

  if (existing.isEmpty) {
    await db.insert(
      'bills',
      values,
      conflictAlgorithm:
          ConflictAlgorithm.ignore,
    );
  } else {
    await db.update(
      'bills',
      values,
      where:
          'customer_id = ? AND billing_month = ?',
      whereArgs: [customerId, month],
    );
  }
}

}

// ============================================================
// PAYMENTS
// Stable ID = receipt number
// ============================================================

Future<void> _uploadPayments(Database db) async {
final rows = await db.rawQuery('''
SELECT
payments.*,
customers.user_id AS customer_user_id
FROM payments
LEFT JOIN customers
ON customers.id = payments.customer_id
''');

await _writeChunks(
  'payments',
  rows.map((row) {
    final receipt =
        row['receipt_no']?.toString().trim() ?? '';

    final userId =
        row['customer_user_id']?.toString() ?? '';

    return _CloudRecord(
      documentId: _safeId(receipt),
      data: _cleanData({
        ...row,
        'local_id': row['id'],
        'customer_user_id': userId,
        'synced_at': FieldValue.serverTimestamp(),
      }),
    );
  }).where((r) => r.documentId.isNotEmpty).toList(),
);

}

Future<void> _restorePayments(
DatabaseExecutor db,
) async {
final snapshot =
await _collection('payments').get();

for (final doc in snapshot.docs) {
  final data = doc.data();

  final receipt =
      data['receipt_no']?.toString().trim() ?? '';

  final userId =
      data['customer_user_id']?.toString() ?? '';

  if (receipt.isEmpty || userId.isEmpty) {
    continue;
  }

  final customer = await db.query(
    'customers',
    columns: ['id'],
    where: 'user_id = ?',
    whereArgs: [userId],
    limit: 1,
  );

  if (customer.isEmpty) continue;

  final customerId =
      customer.first['id'] as int;

  int? staffId;

  final staffName =
      data['staff_name']?.toString().trim() ?? '';

  if (staffName.isNotEmpty) {
    final staff = await db.query(
      'staff',
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [staffName],
      limit: 1,
    );

    if (staff.isNotEmpty) {
      staffId = staff.first['id'] as int;
    }
  }

  int? billId;

  final month =
      data['billing_month']?.toString() ?? '';

  if (month.isNotEmpty) {
    final bill = await db.query(
      'bills',
      columns: ['id'],
      where:
          'customer_id = ? AND billing_month = ?',
      whereArgs: [customerId, month],
      limit: 1,
    );

    if (bill.isNotEmpty) {
      billId = bill.first['id'] as int;
    }
  }

  final values = {
    'customer_id': customerId,
    'bill_id': billId,
    'user_id':
        data['user_id']?.toString() ?? '',
    'amount': _doubleValue(data['amount']),
    'payment_date':
        data['payment_date']?.toString() ?? '',
    'receipt_no': receipt,
    'staff_id': staffId,
    'note': data['note']?.toString() ?? '',
    'created_at':
        data['created_at']?.toString() ??
            DateTime.now().toIso8601String(),
  };

  final existing = await db.query(
    'payments',
    where: 'receipt_no = ?',
    whereArgs: [receipt],
    limit: 1,
  );

  if (existing.isEmpty) {
    await db.insert(
      'payments',
      values,
      conflictAlgorithm:
          ConflictAlgorithm.ignore,
    );
  } else {
    await db.update(
      'payments',
      values,
      where: 'receipt_no = ?',
      whereArgs: [receipt],
    );
  }
}

}

// ============================================================
// FIRESTORE BATCH WRITER
// ============================================================

Future<void> _writeChunks(
String collectionName,
List<_CloudRecord> records,
) async {
const chunkSize = 400;

for (
  var start = 0;
  start < records.length;
  start += chunkSize
) {
  final end =
      (start + chunkSize < records.length)
          ? start + chunkSize
          : records.length;

  final batch = _firestore.batch();

  for (final record
      in records.sublist(start, end)) {
    final ref = _collection(collectionName)
        .doc(record.documentId);

    batch.set(
      ref,
      record.data,
      SetOptions(merge: true),
    );
  }

  await batch.commit();
}

}

// ============================================================
// HELPERS
// ============================================================

void _requireSignedIn() {
if (currentUser == null) {
throw StateError(
'Please sign in to Firebase first.',
);
}
}

Map<String, dynamic> _customerValues(
Map<String, dynamic> data,
) {
return {
'user_id':
data['user_id']?.toString() ?? '',
'name':
data['name']?.toString() ?? '',
'mobile':
data['mobile']?.toString() ?? '',
'address':
data['address']?.toString() ?? '',
'package_id':
_nullableInt(data['package_id']),
'package_name':
data['package_name']?.toString() ?? '',
'bill_date':
_intValue(data['bill_date'], 7),
'amount':
_doubleValue(data['amount']),
'total_amount':
_doubleValue(data['total_amount']),
'paid_amount':
_doubleValue(data['paid_amount']),
'due_amount':
_doubleValue(data['due_amount']),
'payment_date':
data['payment_date']?.toString() ?? '',
'status':
_intValue(data['status'], 1),
'active':
_intValue(data['active'], 1),
'created_at':
data['created_at']?.toString() ??
DateTime.now().toIso8601String(),
'updated_at':
data['updated_at']?.toString() ??
DateTime.now().toIso8601String(),
};
}

Map<String, dynamic> _cleanData(
Map<String, dynamic> source,
) {
final result = <String, dynamic>{};

source.forEach((key, value) {
  if (value is DateTime) {
    result[key] = value.toIso8601String();
  } else {
    result[key] = value;
  }
});

return result;

}

String _safeId(String value) {
final text = value.trim();

if (text.isEmpty) return '';

return text
    .replaceAll('/', '_')
    .replaceAll('\\', '_')
    .replaceAll('#', '_')
    .replaceAll('?', '_')
    .replaceAll('%', '_')
    .replaceAll('[', '_')
    .replaceAll(']', '_');

}

double _doubleValue(dynamic value) {
if (value is num) {
return value.toDouble();
}

return double.tryParse(
      value?.toString() ?? '',
    ) ??
    0;

}

int _intValue(
dynamic value,
int fallback,
) {
if (value is int) return value;

if (value is num) {
  return value.toInt();
}

return int.tryParse(
      value?.toString() ?? '',
    ) ??
    fallback;

}

int? _nullableInt(dynamic value) {
if (value == null) return null;

if (value is int) return value;

if (value is num) {
  return value.toInt();
}

return int.tryParse(
  value.toString(),
);

}
}

class _CloudRecord {
final String documentId;
final Map<String, dynamic> data;

const _CloudRecord({
required this.documentId,
required this.data,
});
}
