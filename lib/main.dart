import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database_helper.dart';
import 'master_report_center.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'firebase_auth_screen.dart';
import 'firebase_service.dart' as cloud_service;

const _brandBlue = Color(0xFF0867C8);
const _brandCyan = Color(0xFF11A8C7);
const _brandPurple = Color(0xFF6D3FD3);
const _brandPink = Color(0xFFE91E63);
const _pageBg = Color(0xFFF4F7FB);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const Digital24OnlineBilling());
}

class Digital24OnlineBilling extends StatefulWidget {
  const Digital24OnlineBilling({super.key});

  @override
  State<Digital24OnlineBilling> createState() => _AppState();
}

class _AppState extends State<Digital24OnlineBilling> {
  bool locked = false;
bool ready = false;
bool english = false;
bool authenticated = false;
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
  final p = await SharedPreferences.getInstance();

  if (!mounted) return;

  setState(() {
    locked = p.getBool('app_lock_enabled') ?? false;
    english = p.getBool('english_language') ?? false;
    authenticated = cloud_service.FirebaseService.instance.isSignedIn;
    ready = true;
  });
  }

  void unlock() => setState(() => locked = false);

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Digital 24 Online Billing',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _brandBlue,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: _pageBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF10233F),
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: Color(0xFFDCE5F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: _brandBlue, width: 1.5),
          ),
        ),
      ),
            home: !authenticated
          ? FirebaseAuthScreen(
              onAuthenticated: () async {
                await cloud_service.FirebaseService.instance.restoreAfterLogin();

                if (!mounted) return;

                setState(() {
                  authenticated = true;
                });
              },
            )
          : locked
              ? LockScreen(onUnlocked: unlock)
              : BillingHomePage(
                  english: english,
                  onLanguageChanged: (v) => setState(() => english = v),
                ),
    );
  }
}
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final controller = TextEditingController();
  bool busy = false;
  String? error;

  String _hash(String value) => sha256.convert(value.codeUnits).toString();

  Future<void> unlock() async {
    if (controller.text.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    final p = await SharedPreferences.getInstance();
    final saved = p.getString('app_lock_hash');
    if (saved != null && _hash(controller.text) == saved) {
      if (!mounted) return;
      widget.onUnlocked();
      return;
    }
    if (!mounted) return;
    setState(() {
      busy = false;
      error = 'পাসওয়ার্ড সঠিক নয়';
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircleAvatar(radius: 38, child: Icon(Icons.lock, size: 38)),
                  const SizedBox(height: 16),
                  const Text('Digital 24 Online Billing', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('অ্যাপ আনলক করতে পাসওয়ার্ড দিন'),
                  const SizedBox(height: 18),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    onSubmitted: (_) => unlock(),
                    decoration: InputDecoration(
                      labelText: 'পাসওয়ার্ড',
                      errorText: error,
                      prefixIcon: const Icon(Icons.password),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: busy ? null : unlock,
                      icon: busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.login),
                      label: const Text('আনলক'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Customer {
  final int? id;
  final String userId;
  final String name;
  final String mobile;
  final String address;
  final String packageName;
  final int billDate;
  final double bill;
  final double paid;
  final String paymentDate;
  bool active;

  Customer({
    this.id,
    required this.userId,
    required this.name,
    required this.mobile,
    required this.address,
    required this.packageName,
    required this.billDate,
    required this.bill,
    required this.paid,
    required this.paymentDate,
    required this.active,
  });

  double get due => (bill - paid).clamp(0, double.infinity).toDouble();

  factory Customer.fromMap(Map<String, dynamic> m) {
    return Customer(
      id: (m['id'] as num?)?.toInt(),
      userId: '${m['user_id'] ?? ''}',
      name: '${m['name'] ?? ''}',
      mobile: '${m['mobile'] ?? ''}',
      address: '${m['address'] ?? ''}',
      packageName: '${m['package_name'] ?? ''}',
      billDate: (m['bill_date'] as num?)?.toInt() ?? 7,
      bill: ((m['total_bill'] ?? 0) as num).toDouble(),
      paid: ((m['total_paid'] ?? 0) as num).toDouble(),
      paymentDate: '${m['payment_date'] ?? ''}',
      active: (m['status'] ?? 1) == 1,
    );
  }
}

class BillingHomePage extends StatefulWidget {
  final bool english;
  final ValueChanged<bool> onLanguageChanged;
  const BillingHomePage({super.key, required this.english, required this.onLanguageChanged});

  @override
  State<BillingHomePage> createState() => _BillingHomePageState();
}

class _BillingHomePageState extends State<BillingHomePage> {
  final db = DatabaseHelper.instance;
  final customers = <Customer>[];
  int selectedBillDate = 0;
  String searchText = '';
  bool loading = true;

  String t(String bn, String en) => widget.english ? en : bn;
  String today() => DateFormat('yyyy-MM-dd').format(DateTime.now());
  String monthKey() => DateFormat('yyyy-MM').format(DateTime.now());
  String money(num n) => n.toDouble() % 1 == 0 ? n.toStringAsFixed(0) : n.toStringAsFixed(2);

  String bnNumber(num n) {
    const e = '0123456789';
    const b = '০১২৩৪৫৬৭৮৯';
    return n.toString().split('').map((x) {
      final i = e.indexOf(x);
      return i < 0 ? x : b[i];
    }).join();
  }

  double get totalBill => customers.fold(0, (s, c) => s + c.bill);
  double get totalPaid => customers.fold(0, (s, c) => s + c.paid);
  double get totalDue => customers.fold(0, (s, c) => s + c.due);
  int get activeCount => customers.where((c) => c.active).length;
  int get closedCount => customers.where((c) => !c.active).length;

  List<Customer> get filtered {
    final q = searchText.trim().toLowerCase();
    if (q.isEmpty) return customers;
    return customers.where((c) {
      return c.userId.toLowerCase().contains(q) ||
          c.name.toLowerCase().contains(q) ||
          c.mobile.contains(q) ||
          c.packageName.toLowerCase().contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    loadCustomers();
  }

  void msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> loadCustomers() async {
    if (mounted) setState(() => loading = true);
    try {
      final rows = await db.getCustomers(
        billDate: selectedBillDate == 0 ? null : selectedBillDate,
        search: searchText,
      );
      final currentBills = await db.getBills(monthKey());
      final packages = await db.getPackages();
      final packagePrices = <String, double>{};
      for (final p in packages) {
        if ((p['active'] ?? 1) == 1) {
          packagePrices['${p['name'] ?? ''}'.trim().toLowerCase()] =
              ((p['price'] ?? 0) as num).toDouble();
        }
      }
      final billsByCustomer = <int, Map<String, dynamic>>{};
      for (final b in currentBills) {
        final id = b['customer_id'];
        if (id is num) billsByCustomer[id.toInt()] = b;
      }
      final list = <Customer>[];
      for (final r in rows) {
        final id = (r['id'] as num?)?.toInt();
        final current = id == null ? null : billsByCustomer[id];
        final packageName = '${r['package_name'] ?? ''}'.trim();
        final packagePrice = packagePrices[packageName.toLowerCase()] ?? 0;
        final billAmount = current == null
            ? packagePrice
            : ((current['amount'] ?? 0) as num).toDouble();
        final paidAmount = current == null
            ? 0.0
            : ((current['paid'] ?? 0) as num).toDouble();
        list.add(Customer(
          id: id,
          userId: '${r['user_id'] ?? ''}',
          name: '${r['name'] ?? ''}',
          mobile: '${r['mobile'] ?? ''}',
          address: '${r['address'] ?? ''}',
          packageName: packageName,
          billDate: (r['bill_date'] as num?)?.toInt() ?? 7,
          bill: billAmount,
          paid: paidAmount,
          paymentDate: '${r['payment_date'] ?? ''}',
          active: (r['status'] ?? 1) == 1,
        ));
      }
      if (!mounted) return;
      setState(() {
        customers..clear()..addAll(list);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      msg('${t('ডেটা লোডে সমস্যা: ', 'Load error: ')}$e');
    }
  }

  Future<bool> userIdExists(String uid, {int? exceptId}) async {
    final rows = await db.getCustomers(search: uid.trim());
    return rows.any((r) => '${r['user_id']}'.toLowerCase() == uid.trim().toLowerCase() && r['id'] != exceptId);
  }

  Future<void> addCustomer() async {
    final uid = TextEditingController();
    final name = TextEditingController();
    final mobile = TextEditingController();
    final address = TextEditingController();
    final pkg = TextEditingController();
    final bill = TextEditingController();
    final paid = TextEditingController(text: '0');
    int date = 7;
    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(t('নতুন ইউজার যোগ করুন', 'Add New Customer')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              field(uid, t('ইউজার আইডি *', 'User ID *'), Icons.badge),
              const SizedBox(height: 10),
              field(name, t('ইউজারের নাম *', 'Customer name *'), Icons.person),
              const SizedBox(height: 10),
              field(mobile, t('মোবাইল', 'Mobile'), Icons.phone, type: TextInputType.phone),
              const SizedBox(height: 10),
              field(address, t('ঠিকানা', 'Address'), Icons.home),
              const SizedBox(height: 10),
              field(pkg, t('প্যাকেজ', 'Package'), Icons.speed),
              const SizedBox(height: 10),
              dateDrop(date, (v) => setD(() => date = v)),
              const SizedBox(height: 10),
              field(bill, t('মাসিক বিল *', 'Monthly Bill *'), Icons.receipt, type: const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 10),
              field(paid, t('প্রাথমিক পরিশোধ', 'Initial Payment'), Icons.payments, type: const TextInputType.numberWithOptions(decimal: true)),
            ]),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: Text(t('বাতিল', 'Cancel'))),
            FilledButton.icon(
              onPressed: saving ? null : () async {
                final id = uid.text.trim();
                final nm = name.text.trim();
                final b = double.tryParse(bill.text.trim()) ?? 0;
                final p = double.tryParse(paid.text.trim()) ?? 0;
                if (id.isEmpty || nm.isEmpty || b <= 0 || p < 0 || p > b) {
                  msg(t('আইডি, নাম ও সঠিক বিল/পরিশোধ দিন', 'Enter valid ID, name, bill and payment'));
                  return;
                }
                setD(() => saving = true);
                try {
                  if (await userIdExists(id)) throw Exception(t('এই ইউজার আইডি ইতোমধ্যে আছে', 'User ID already exists'));
                  final cid = await db.addCustomer({
                    'user_id': id,
                    'name': nm,
                    'mobile': mobile.text.trim(),
                    'address': address.text.trim(),
                    'package_name': pkg.text.trim(),
                    'bill_date': date,
                    'status': 1,
                  });
                  final bid = await db.ensureBill(cid, monthKey(), date, b);
                  if (p > 0) {
                    await db.addPayment({'customer_id': cid, 'bill_id': bid, 'amount': p, 'payment_date': today(), 'note': 'প্রাথমিক পরিশোধ'});
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  await loadCustomers();
                  msg(t('ইউজার সফলভাবে সংরক্ষণ হয়েছে', 'Customer saved successfully'));
                } catch (e) {
                  if (ctx.mounted) setD(() => saving = false);
                  msg('$e');
                }
              },
              icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
              label: Text(t('সংরক্ষণ', 'Save')),
            ),
          ],
        ),
      ),
    );
    for (final c in [uid, name, mobile, address, pkg, bill, paid]) c.dispose();
  }

  Widget field(TextEditingController c, String label, IconData icon, {TextInputType type = TextInputType.text}) {
    return TextField(controller: c, keyboardType: type, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), border: const OutlineInputBorder()));
  }

  Widget dateDrop(int value, ValueChanged<int> onChanged) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(labelText: t('বিল ডেট', 'Billing Date'), prefixIcon: const Icon(Icons.calendar_month), border: const OutlineInputBorder()),
      items: const [7, 14, 21].map((x) => DropdownMenuItem(value: x, child: Text('$x'))).toList(),
      onChanged: (v) => onChanged(v ?? 7),
    );
  }

  Future<void> editCustomer(Customer c) async {
  if (c.id == null) return;

  final uid = TextEditingController(text: c.userId);
  final name = TextEditingController(text: c.name);
  final mobile = TextEditingController(text: c.mobile);
  final address = TextEditingController(text: c.address);
  final pkg = TextEditingController(text: c.packageName);
  final bill = TextEditingController(text: c.bill.toStringAsFixed(0));

  int date = c.billDate;
  bool saving = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(
          t('ইউজার তথ্য পরিবর্তন', 'Edit Customer'),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              field(
                uid,
                t('ইউজার আইডি', 'User ID'),
                Icons.badge,
              ),
              const SizedBox(height: 10),

              field(
                name,
                t('নাম', 'Name'),
                Icons.person,
              ),
              const SizedBox(height: 10),

              field(
                mobile,
                t('মোবাইল', 'Mobile'),
                Icons.phone,
                type: TextInputType.phone,
              ),
              const SizedBox(height: 10),

              field(
                address,
                t('ঠিকানা', 'Address'),
                Icons.home,
              ),
              const SizedBox(height: 10),

              field(
                pkg,
                t('প্যাকেজ', 'Package'),
                Icons.speed,
              ),
              const SizedBox(height: 10),

              // =========================
              // BILL FIELD
              // =========================
              field(
                bill,
                t('বিল', 'Bill'),
                Icons.receipt_long,
                type: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 10),

              dateDrop(
                date,
                (v) => setD(() => date = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving
                ? null
                : () => Navigator.pop(ctx),
            child: Text(
              t('বাতিল', 'Cancel'),
            ),
          ),

          FilledButton.icon(
            onPressed: saving
                ? null
                : () async {
                    final userId = uid.text.trim();
                    final customerName = name.text.trim();

                    final billText = bill.text
                        .trim()
                        .replaceAll(',', '')
                        .replaceAll(' ', '');

                    final billAmount =
                        double.tryParse(billText);

                    if (userId.isEmpty ||
                        customerName.isEmpty) {
                      msg(
                        t(
                          'ইউজার আইডি ও নাম দিন',
                          'Enter User ID and name',
                        ),
                      );
                      return;
                    }

                    if (billAmount == null ||
                        billAmount < 0) {
                      msg(
                        t(
                          'সঠিক বিলের পরিমাণ দিন',
                          'Enter a valid bill amount',
                        ),
                      );
                      return;
                    }

                    setD(() => saving = true);

                    try {
                      if (await userIdExists(
                        userId,
                        exceptId: c.id,
                      )) {
                        throw Exception(
                          t(
                            'এই ইউজার আইডি অন্য একজন ব্যবহার করছে',
                            'User ID is already used',
                          ),
                        );
                      }

                      await db.updateCustomer(
                        c.id!,
                        {
                          'user_id': userId,
                          'name': customerName,
                          'mobile': mobile.text.trim(),
                          'address': address.text.trim(),
                          'package_name': pkg.text.trim(),
                          'amount': billAmount,
                          'bill_date': date,
                        },
                      );

                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }

                      await loadCustomers();

                      msg(
                        t(
                          'ইউজারের তথ্য ও বিল সফলভাবে পরিবর্তন হয়েছে',
                          'Customer information and bill updated successfully',
                        ),
                      );
                    } catch (e) {
                      if (ctx.mounted) {
                        setD(() => saving = false);
                      }

                      msg('$e');
                    }
                  },
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.save),
            label: Text(
              t('সংরক্ষণ', 'Save'),
            ),
          ),
        ],
      ),
    ),
  );

  for (final controller in [
    uid,
    name,
    mobile,
    address,
    pkg,
    bill,
  ]) {
    controller.dispose();
  }
  }

  Future<void> toggleCustomer(Customer c) async {
    if (c.id == null) return;
    try {
      await db.setCustomerStatus(c.id!, !c.active);
      await loadCustomers();
      msg(c.active ? t('ইউজার Closed করা হয়েছে', 'Customer closed') : t('ইউজার Active করা হয়েছে', 'Customer activated'));
    } catch (e) { msg('$e'); }
  }

  Future<void> deleteCustomer(Customer c) async {
    if (c.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('ইউজার মুছে ফেলবেন?', 'Delete customer?')),
        content: Text('${c.userId} - ${c.name}\n\n${t('এই কাজটি ফিরিয়ে আনা যাবে না।', 'This action cannot be undone.')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('বাতিল', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('মুছে ফেলুন', 'Delete'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
            await db.deleteCustomer(c.id!);
      await loadCustomers();
      msg(t('ইউজার মুছে ফেলা হয়েছে', 'Customer deleted'));
    } catch (e) { msg('$e'); }
  }

  Future<void> showDetails(Customer c) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('ইউজারের বিস্তারিত তথ্য', 'Customer Details')),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          detail('ইউজার আইডি', c.userId), detail('নাম', c.name), detail('মোবাইল', c.mobile.isEmpty ? '-' : c.mobile),
          detail('ঠিকানা', c.address.isEmpty ? '-' : c.address), detail('প্যাকেজ', c.packageName.isEmpty ? '-' : c.packageName),
          detail('বিল ডেট', '${bnNumber(c.billDate)} তারিখ'), detail('মোট বিল', '${money(c.bill)} ৳'),
          detail('মোট পরিশোধ', '${money(c.paid)} ৳'), detail('মোট বকেয়া', '${money(c.due)} ৳'),
          detail('সর্বশেষ পেমেন্ট', c.paymentDate.isEmpty ? '-' : c.paymentDate), detail('স্ট্যাটাস', c.active ? 'Active' : 'Closed'),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('বন্ধ', 'Close'))),
          FilledButton.icon(onPressed: () { Navigator.pop(ctx); showPaymentHistory(c); }, icon: const Icon(Icons.history), label: Text(t('পেমেন্ট হিস্ট্রি', 'Payment History'))),
        ],
      ),
    );
  }
  
    Widget detail(String a, String b) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 110, child: Text('$a:', style: const TextStyle(fontWeight: FontWeight.bold))), Expanded(child: Text(b))]));

  Future<int> currentBill(Customer c) async => db.ensureBill(c.id!, monthKey(), c.billDate, c.bill > 0 ? c.bill : 0);

  Future<void> takePayment(Customer c) async {
  if (c.id == null) return;

  try {
    // বর্তমান মাসের Bill নিশ্চিত করা
    final bid = await currentBill(c);

    final monthRows = await db.getBills(monthKey());

    final current = monthRows.where((r) {
      final id = r['id'];
      return id is num && id.toInt() == bid;
    }).toList();

    final billAmount = current.isEmpty
        ? c.bill
        : ((current.first['amount'] ?? 0) as num).toDouble();

    final paidAmount = current.isEmpty
        ? 0.0
        : ((current.first['paid'] ?? 0) as num).toDouble();

    final due =
        (billAmount - paidAmount).clamp(0, double.infinity).toDouble();

    if (due <= 0) {
      msg(
        t(
          'এই বিলের কোনো বকেয়া নেই।',
          'There is no due for this bill.',
        ),
      );
      return;
    }

    final amount = TextEditingController(
      text: due.toStringAsFixed(2),
    );

    final note = TextEditingController();

    final staff = await db.getStaff();

    int? staffId;
    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(
            t('পেমেন্ট গ্রহণ', 'Receive Payment'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${c.userId} - ${c.name}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  '${t('এই মাসের বিল', 'Current month bill')}: '
                  '${money(billAmount)} ৳',
                ),

                Text(
                  '${t('পরিশোধ', 'Paid')}: '
                  '${money(paidAmount)} ৳',
                ),

                Text(
                  '${t('বকেয়া', 'Due')}: '
                  '${money(due)} ৳',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                field(
                  amount,
                  t('পরিমাণ *', 'Amount *'),
                  Icons.payments,
                  type: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),

                if (staff.isNotEmpty) ...[
                  const SizedBox(height: 10),

                  DropdownButtonFormField<int?>(
                    initialValue: staffId,
                    decoration: InputDecoration(
                      labelText: t('স্টাফ', 'Staff'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text(
                          t(
                            'নিজে/নির্ধারিত নয়',
                            'Self / Not assigned',
                          ),
                        ),
                      ),
                      ...staff.map(
                        (s) => DropdownMenuItem<int?>(
                          value: (s['id'] as num).toInt(),
                          child: Text('${s['name']}'),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setD(() => staffId = v);
                    },
                  ),
                ],

                const SizedBox(height: 10),

                field(
                  note,
                  t('নোট', 'Note'),
                  Icons.note,
                ),
              ],
            ),
          ),

          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.pop(ctx),
              child: Text(
                t('বাতিল', 'Cancel'),
              ),
            ),

            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      final cleanedAmount = amount.text
                          .trim()
                          .replaceAll(',', '')
                          .replaceAll(' ', '');

                      final a = double.tryParse(
                        cleanedAmount,
                      );

                      if (a == null || a <= 0) {
                        msg(
                          t(
                            'সঠিক টাকার পরিমাণ দিন',
                            'Enter a valid payment amount',
                          ),
                        );
                        return;
                      }

                      if (a > due + 0.0001) {
                        msg(
                          t(
                            'বকেয়ার চেয়ে বেশি টাকা নেওয়া যাবে না',
                            'Payment cannot be greater than the due amount',
                          ),
                        );
                        return;
                      }

                      setD(() => saving = true);

                      try {
                        // ------------------------------------------------
                        // 1. প্রথমে Database-এ Payment SAVE
                        // ------------------------------------------------
                        final paymentId = await db.addPayment({
                          'customer_id': c.id!,
                          'bill_id': bid,
                          'amount': a,
                          'payment_date': today(),
                          'staff_id': staffId,
                          'note': note.text.trim(),
                        });

                        // ------------------------------------------------
                        // 2. Save হওয়ার পর Payment আবার Database থেকে
                        //    নিশ্চিতভাবে পড়ে নেওয়া
                        // ------------------------------------------------
                        final history =
                            await db.getPaymentHistory(
                          c.id!,
                          billId: bid,
                        );

                        Map<String, dynamic>? payment;

                        for (final row in history) {
                          final rowId = row['id'];

                          if (rowId is num &&
                              rowId.toInt() == paymentId) {
                            payment = row;
                            break;
                          }
                        }

                        payment ??=
                            history.isNotEmpty ? history.first : null;

                        if (payment == null) {
                          throw Exception(
                            'Payment সংরক্ষণ হয়েছে, কিন্তু Payment History-তে পাওয়া যায়নি।',
                          );
                        }

                        // ------------------------------------------------
                        // 3. Dialog বন্ধ
                        // ------------------------------------------------
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                        }

                        // ------------------------------------------------
                        // 4. Customer list reload
                        //    এখানে সমস্যা হলেও Payment ইতিমধ্যে SAVE।
                        // ------------------------------------------------
                        try {
                          await loadCustomers();
                        } catch (_) {
                          // Payment নষ্ট হবে না
                        }

                        // ------------------------------------------------
                        // 5. Receipt তৈরি/Print/Save
                        //    Receipt-এ সমস্যা হলেও Payment সফল থাকবে।
                        // ------------------------------------------------
                        try {
                          await printReceipt(
                            c,
                            payment,
                          );

                          msg(
                            t(
                              'পেমেন্ট গ্রহণ হয়েছে এবং Receipt প্রস্তুত।',
                              'Payment received and receipt prepared.',
                            ),
                          );
                        } catch (e) {
                          msg(
                            t(
                              'পেমেন্ট সফলভাবে সংরক্ষণ হয়েছে। Receipt তৈরি/Print করতে সমস্যা হয়েছে।',
                              'Payment was saved successfully, but the receipt could not be prepared/printed.',
                            ),
                          );
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          setD(() => saving = false);
                        }

                        msg(
                          '${t(
                            'পেমেন্টে সমস্যা: ',
                            'Payment error: ',
                          )}$e',
                        );
                      }
                    },

              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.receipt_long,
                    ),

              label: Text(
                t(
                  'গ্রহণ ও Receipt',
                  'Receive & Receipt',
                ),
              ),
            ),
          ],
        ),
      ),
    );

        amount.dispose();
    note.dispose();
  } catch (e) {
    msg(
      '${t(
        'পেমেন্ট অপশন খুলতে সমস্যা: ',
        'Unable to open payment: ',
      )}$e',
    );
  }
  }
  
  Future<void> showPaymentHistory(Customer c) async {
    if (c.id == null) return;
    final rows = await db.getPaymentHistory(c.id!);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${t('পেমেন্ট হিস্ট্রি', 'Payment History')}\n${c.userId} - ${c.name}'),
        content: SizedBox(
          width: double.maxFinite,
          height: 440,
          child: rows.isEmpty
              ? Center(child: Text(t('কোনো পেমেন্ট নেই', 'No payments')))
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    final a = ((r['amount'] ?? 0) as num).toDouble();
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.payments)),
                      title: Text('${money(a)} ৳', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${r['payment_date'] ?? ''}\n${r['receipt_no'] ?? ''}\n${r['billing_month'] ?? ''} • ${r['staff_name'] ?? ''}'),
                      trailing: IconButton(icon: const Icon(Icons.print), onPressed: () => printReceipt(c, r)),
                    );
                  },
                ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(t('বন্ধ', 'Close')))],
      ),
    );
  }
  
  Future<void> monthlyBilling() async {
    try {
      final rows = await db.getCustomers();
      final existingBills = await db.getBills(monthKey());
      final packages = await db.getPackages();
      final existingIds = <int>{
        for (final b in existingBills)
          if (b['customer_id'] is num) (b['customer_id'] as num).toInt(),
      };
      final packagePrices = <String, double>{};
      for (final p in packages) {
        if ((p['active'] ?? 1) == 1) {
          packagePrices['${p['name'] ?? ''}'.trim().toLowerCase()] =
              ((p['price'] ?? 0) as num).toDouble();
        }
      }
      int prepared = 0;
      int skipped = 0;
      for (final r in rows) {
        if ((r['status'] ?? 1) != 1) continue;
        final id = (r['id'] as num).toInt();
        if (existingIds.contains(id)) continue;
        final packageName = '${r['package_name'] ?? ''}'.trim().toLowerCase();
        final amount = packagePrices[packageName] ?? 0;
        if (amount <= 0) {
          skipped++;
          continue;
        }
        await db.ensureBill(
          id,
          monthKey(),
          (r['bill_date'] as num?)?.toInt() ?? 7,
          amount,
        );
        prepared++;
      }
      final suffix = skipped > 0
          ? ' • ${t('$skipped জনের active package/price নেই', '$skipped customers have no active package/price')}'
          : '';
      msg('${t('এই মাসের Billing প্রস্তুত: ', 'Monthly billing prepared: ')}$prepared$suffix');
      await loadCustomers();
      await showMonthlyBills(monthKey());
    } catch (e) {
      msg('${t('Billing তৈরিতে সমস্যা: ', 'Billing error: ')}$e');
    }
  }

  Future<void> showMonthlyBills(String month) async {
    try {
      final rows = await db.getBills(month);
      double bill = 0, paid = 0;
      for (final r in rows) {
        bill += ((r['amount'] ?? 0) as num).toDouble();
        paid += ((r['paid'] ?? 0) as num).toDouble();
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${t('মাসিক Billing', 'Monthly Billing')} — $month'),
          content: SizedBox(
            width: double.maxFinite,
            height: 500,
                        child: Column(children: [
              reportLine(t('মোট বিল', 'Total Bill'), '${money(bill)} ৳'),
              reportLine(t('মোট পরিশোধ', 'Total Paid'), '${money(paid)} ৳'),
              reportLine(t('বকেয়া', 'Due'), '${money((bill - paid).clamp(0, double.infinity))} ৳'),
              const Divider(),
              Expanded(child: ListView.builder(itemCount: rows.length, itemBuilder: (_, i) {
                final r = rows[i];
                final a = ((r['amount'] ?? 0) as num).toDouble();
                final p = ((r['paid'] ?? 0) as num).toDouble();
                return ListTile(
                  title: Text('${r['user_id']} - ${r['name']}'),
                  subtitle: Text('${r['package_name'] ?? ''} • ${t('বিল', 'Bill')} ${money(a)} • ${t('পরিশোধ', 'Paid')} ${money(p)}'),
                  trailing: Text('${money((a - p).clamp(0, double.infinity))} ৳', style: const TextStyle(fontWeight: FontWeight.bold)),
                );
              })),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => printMonthlyReport(month), child: Text(t('PDF Report', 'PDF Report'))),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(t('বন্ধ', 'Close'))),
          ],
        ),
      );
    } catch (e) { msg('$e'); }
  }

  Widget reportLine(String a, String b) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [Expanded(child: Text(a)), Text(b, style: const TextStyle(fontWeight: FontWeight.bold))]));

  Future<void> _showPdfActions(Uint8List bytes, String fileName) async {
    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('PDF প্রস্তুত', 'PDF Ready')),
        content: Text(t('PDF-টি Save/Download অথবা Print করতে পারেন।', 'You can save/download or print this PDF.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'print'),
            child: Text(t('Print', 'Print')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, 'save'),
            icon: const Icon(Icons.download_rounded),
            label: Text(t('Save / Download', 'Save / Download')),
          ),
        ],
      ),
    );
        if (action == 'print') {
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: fileName,
      );
    } else if (action == 'save') {
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: t('PDF সংরক্ষণ করুন', 'Save PDF'),
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: bytes,
      );
      if (saved != null && !Platform.isAndroid) {
        final file = File(saved);
        if (!await file.exists() || await file.length() == 0) {
          await file.writeAsBytes(bytes, flush: true);
        }
      }
      msg(t('PDF সংরক্ষণ হয়েছে।', 'PDF saved successfully.'));
    }
  }

  Future<void> printReceipt(Customer c, Map<String, dynamic> p) async {
    final doc = pw.Document();
    final amount = ((p['amount'] ?? 0) as num).toDouble();
    final receipt = '${p['receipt_no'] ?? ''}';
    final date = '${p['payment_date'] ?? ''}';
    final month = '${p['billing_month'] ?? monthKey()}';
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Center(child: pw.Text('DIGITAL 24 ONLINE', style: pw.TextStyle(fontSize: 21, fontWeight: pw.FontWeight.bold))),
        pw.Center(child: pw.Text('Internet Service Provider')),
        pw.Divider(),
        pw.Center(child: pw.Text('PAYMENT RECEIPT', style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 14),
        pw.Text('Receipt No: $receipt'), pw.Text('Date: $date'), pw.Text('Bill Month: $month'),
        pw.SizedBox(height: 10),
        pw.Text('Customer ID: ${c.userId}'), pw.Text('Name: ${c.name}'), pw.Text('Phone: ${c.mobile}'), pw.Text('Package: ${c.packageName}'), pw.Text('Bill Date: ${c.billDate}'),
        pw.SizedBox(height: 14),
        pw.Table(border: pw.TableBorder.all(), columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(1)}, children: [
          pw.TableRow(children: [pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Description')), pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Amount'))]),
          pw.TableRow(children: [pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Paid Amount')), pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('BDT ${money(amount)}'))]),
          pw.TableRow(children: [pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Payment Note')), pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${p['note'] ?? ''}'))]),
        ]),
        pw.SizedBox(height: 24),
        pw.Text('Thank you for your payment.'),
        pw.SizedBox(height: 30),
        pw.Text('Digital 24 Online Billing'),
        pw.Text('Seroil Colony, 4 No. Road, Ghoramara, Chandrima Rajshahi-6100'),
      ],
    )));
        final bytes = Uint8List.fromList(await doc.save());
    await _showPdfActions(
      bytes,
      'Digital24Online_Receipt_${receipt.isEmpty ? DateFormat('yyyyMMdd_HHmmss').format(DateTime.now()) : receipt}.pdf',
    );
  }
  
  Future<void> printMonthlyReport(String month) async {
    final rows = await db.getBills(month);
    double total = 0, paid = 0;
    for (final r in rows) { total += ((r['amount'] ?? 0) as num).toDouble(); paid += ((r['paid'] ?? 0) as num).toDouble(); }
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        pw.Center(child: pw.Text('DIGITAL 24 ONLINE', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold))),
        pw.Center(child: pw.Text('Monthly Billing Report - $month')),
        pw.SizedBox(height: 14),
        pw.Table.fromTextArray(
          headers: ['User ID', 'Name', 'Package', 'Bill', 'Paid', 'Due'],
          data: rows.map((r) {
            final b = ((r['amount'] ?? 0) as num).toDouble();
            final p = ((r['paid'] ?? 0) as num).toDouble();
            return ['${r['user_id']}', '${r['name']}', '${r['package_name'] ?? ''}', money(b), money(p), money((b - p).clamp(0, double.infinity))];
          }).toList(),
        ),
        pw.SizedBox(height: 12),
        pw.Text('Total Bill: BDT ${money(total)}'), pw.Text('Total Paid: BDT ${money(paid)}'), pw.Text('Total Due: BDT ${money((total - paid).clamp(0, double.infinity))}'),
        pw.SizedBox(height: 20), pw.Text('Printed: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
      ],
    ));
    final bytes = Uint8List.fromList(await doc.save());
    await _showPdfActions(bytes, 'Digital24Online_Monthly-Report-$month.pdf');
  }

  Future<void> todayCollection() async {
    final date = today();
    try {
      final rows = await db.getPaymentsReport(date, date);
      final total = rows.fold<double>(0, (sum, r) => sum + ((r['amount'] ?? 0) as num).toDouble());
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('আজকের Collection', 'Today Collection')),
          content: SizedBox(
            width: double.maxFinite, height: 440,
            child: Column(children: [
              reportLine(t('মোট Collection', 'Total Collection'), '${money(total)} ৳'),
              const Divider(),
              Expanded(child: rows.isEmpty
                ? Center(child: Text(t('আজ কোনো পেমেন্ট নেই', 'No payments today')))
                : ListView.separated(
                    itemCount: rows.length, separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      return ListTile(
                        title: Text('${r['user_id'] ?? ''} - ${r['name'] ?? ''}'),
                        subtitle: Text('${r['payment_date'] ?? ''} • ${r['staff_name'] ?? ''}\n${r['receipt_no'] ?? ''}'),
                        trailing: Text('${money(((r['amount'] ?? 0) as num).toDouble())} ৳'),
                      );
                    },
                  )),
            ]),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(t('বন্ধ', 'Close'))) ],
        ),
      );
         } catch (e) { msg('${t('আজকের Collection দেখাতে সমস্যা: ', 'Today collection error: ')}$e'); }
  }
  
  Future<void> reports() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => MasterReportCenter(
        db: db,
        english: widget.english,
      ),
    );
  }

  Future<void> packageManagement() async {
    await showDialog<void>(context: context, builder: (ctx) => PackageManager(db: db, english: widget.english));
  }

  Future<void> staffManagement() async {
    await showDialog<void>(context: context, builder: (ctx) => StaffManager(db: db, english: widget.english));
  }

  Future<void> appLockSettings() async {
    final p = await SharedPreferences.getInstance();
    final enabled = p.getBool('app_lock_enabled') ?? false;
    if (enabled) {
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: Text(t('App Lock বন্ধ করবেন?', 'Disable App Lock?')),
        content: Text(t('পাসওয়ার্ড সুরক্ষা বন্ধ হবে।', 'Password protection will be disabled.')),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('না', 'No'))), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('হ্যাঁ', 'Yes')))],
      ));
      if (ok == true) { await p.setBool('app_lock_enabled', false); msg(t('App Lock বন্ধ হয়েছে', 'App Lock disabled')); }
      return;
    }
    final a = TextEditingController(), b = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(t('App Lock চালু করুন', 'Enable App Lock')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: a, obscureText: true, decoration: InputDecoration(labelText: t('নতুন পাসওয়ার্ড', 'New password'))),
        const SizedBox(height: 10), TextField(controller: b, obscureText: true, decoration: InputDecoration(labelText: t('আবার লিখুন', 'Confirm password'))),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('বাতিল', 'Cancel'))), FilledButton(onPressed: () => Navigator.pop(ctx, a.text.isNotEmpty && a.text == b.text), child: Text(t('চালু করুন', 'Enable')))],
    ));
        if (ok == true) {
      await p.setString('app_lock_hash', sha256.convert(a.text.codeUnits).toString());
      await p.setBool('app_lock_enabled', true);
      msg(t('App Lock চালু হয়েছে', 'App Lock enabled'));
    }
    a.dispose(); b.dispose();
  }

  Future<void> searchDialog() async {
    final c = TextEditingController(text: searchText);
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: Text(t('ইউজার খুঁজুন', 'Search Customer')),
      content: TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: t('আইডি/নাম/মোবাইল/প্যাকেজ', 'ID/name/mobile/package'), prefixIcon: const Icon(Icons.search), border: const OutlineInputBorder())),
      actions: [
        TextButton(onPressed: () { setState(() => searchText = ''); Navigator.pop(ctx); loadCustomers(); }, child: Text(t('পরিষ্কার', 'Clear'))),
        FilledButton(onPressed: () { setState(() => searchText = c.text.trim()); Navigator.pop(ctx); loadCustomers(); }, child: Text(t('খুঁজুন', 'Search'))),
      ],
    ));
    c.dispose();
  }

  Future<void> languageSwitch() async {
    final next = !widget.english;
    final p = await SharedPreferences.getInstance();
    await p.setBool('english_language', next);
    widget.onLanguageChanged(next);
  }

  Future<void> backupDatabase() async {
    try {
      await db.exportBackupToFile();
      msg(t(
        'Database Backup সফলভাবে সংরক্ষণ করা হয়েছে।',
        'Database backup saved successfully.',
      ));
    } catch (e) {
      msg('${t('Backup-এ সমস্যা: ', 'Backup error: ')}$e');
    }
  }
  
  Future<void> restoreBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Restore Backup', 'Restore Backup')),
        content: Text(t(
          'Restore করলে বর্তমান Customer, Billing, Payment, Package ও Staff data নির্বাচিত Backup-এর data দিয়ে প্রতিস্থাপিত হবে। আগে একটি Backup রেখে নিন। আপনি কি চালিয়ে যেতে চান?',
          'Restore will replace the current Customer, Billing, Payment, Package and Staff data with the selected backup. Please keep a backup first. Continue?',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('বাতিল', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Restore করুন', 'Restore'))),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      Uint8List? bytes = picked.bytes;
      if (bytes == null && picked.path != null) {
        final file = File(picked.path!);
        if (await file.exists()) bytes = await file.readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) throw Exception(t('Backup ফাইলটি পড়া যায়নি।', 'Backup file could not be read.'));
      final name = picked.name.toLowerCase();
      if (name.endsWith('.json') || name.contains('json')) {
        await db.restoreJsonDatabase(bytes);
      } else if (name.endsWith('.db') || name.contains('backup')) {
        await db.restoreDatabase(bytes);
      } else {
        throw Exception(t('শুধু .db অথবা .json Backup ফাইল নির্বাচন করুন।', 'Select a .db or .json backup file.'));
      }
      await loadCustomers();
      msg(t('Backup সফলভাবে Restore হয়েছে।', 'Backup restored successfully.'));
    } catch (e) {
      msg('${t('Restore-এ সমস্যা: ', 'Restore error: ')}$e');
    }
  }

  Future<void> exportUserListPdf() async {
    try {
      final rows = List<Customer>.from(filtered);
      if (rows.isEmpty) {
        msg(t('PDF করার মতো কোনো ইউজার নেই।', 'There are no customers to export.'));
        return;
      }

      final logoData = await rootBundle.load('assets/logo.png');
      final logo = pw.MemoryImage(
        logoData.buffer.asUint8List(),
      );

      final doc = pw.Document();

      double totalBillValue = 0;
      double totalPaidValue = 0;
      double totalDueValue = 0;

      for (final c in rows) {
        totalBillValue += c.bill;
        totalPaidValue += c.paid;
        totalDueValue += c.due;
      }

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          header: (_) => pw.Column(
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(
                    width: 72,
                    height: 42,
                    child: pw.Image(logo, fit: pw.BoxFit.contain),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'DIGITAL 24 ONLINE',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text('Internet Service Provider'),
                      pw.Text(
                        'Seroil Colony, 4 No. Road, Ghoramara, Chandrima Rajshahi-6100',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ],
              ),
                            pw.SizedBox(height: 10),
              pw.Divider(),
              pw.Center(
                child: pw.Text(
                  'CUSTOMER / PAYMENT REPORT',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 8),
            ],
          ),
          footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Page ${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
          build: (_) => [
            pw.TableHelper.fromTextArray(
              headers: const [
                'SN',
                'Cust ID',
                'Username',
                'Name',
                'Mobile',
                'Package',
                'Bill Date',
                'Bill',
                'Paid',
                'Due',
                'Status',
              ],
              data: rows.asMap().entries.map((entry) {
                final i = entry.key;
                final c = entry.value;
                return [
                  '${i + 1}',
                  '${c.id ?? '-'}',
                  c.userId,
                  c.name,
                  c.mobile,
                  c.packageName,
                  '${c.billDate}',
                  money(c.bill),
                  money(c.paid),
                  money(c.due),
                  c.active ? 'Active' : 'Closed',
                ];
              }).toList(),
              cellStyle: const pw.TextStyle(fontSize: 7),
              headerStyle: pw.TextStyle(
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
              ),
              cellPadding: const pw.EdgeInsets.all(4),
              border: pw.TableBorder.all(width: 0.35),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blueGrey100,
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Customers: ${rows.length}'),
                pw.Text('Total Bill: BDT ${money(totalBillValue)}'),
                pw.Text('Total Paid: BDT ${money(totalPaidValue)}'),
                pw.Text('Total Due: BDT ${money(totalDueValue)}'),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      );
      
      final bytes = Uint8List.fromList(await doc.save());
      final fileName =
          'Digital24Online_Customer_Report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';

      await _showPdfActions(bytes, fileName);
    } catch (e) {
      msg('${t('PDF তৈরিতে সমস্যা: ', 'PDF error: ')}$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 12,
            title: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Image.asset(
                    'assets/logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Digital 24 Online',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        t(
                          'Internet Service Provider',
                          'Internet Service Provider',
                        ),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
                            IconButton(
                tooltip: t('সার্চ', 'Search'),
                onPressed: searchDialog,
                icon: const Icon(Icons.search_rounded),
              ),
              IconButton(
                tooltip: t('Customer PDF', 'Customer PDF'),
                onPressed: exportUserListPdf,
                icon: const Icon(Icons.picture_as_pdf_rounded),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'today') await todayCollection();
                  if (v == 'monthly') await monthlyBilling();
                  if (v == 'packages') await packageManagement();
                  if (v == 'staff') await staffManagement();
                  if (v == 'reports') await reports();
                  if (v == 'lock') await appLockSettings();
                  if (v == 'language') await languageSwitch();
                  if (v == 'refresh') await loadCustomers();
                  if (v == 'backup') await backupDatabase();
                  if (v == 'restore') await restoreBackup();
                  if (v == 'pdf') await exportUserListPdf();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'today',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.today_rounded),
                      title: Text(t('আজকের Collection', 'Today Collection')),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'monthly',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_month_rounded),
                      title: Text(t('Monthly Billing', 'Monthly Billing')),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'packages',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.speed_rounded),
                      title: Text(t('Package Management', 'Package Management')),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'staff',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.groups_rounded),
                      title: Text(t('Staff Collection', 'Staff Collection')),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'reports',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.assessment_rounded),
                      title: Text(t('Reports', 'Reports')),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'pdf',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.picture_as_pdf_rounded),
                      title: Text(
                        t('সম্পূর্ণ User List PDF', 'Full User List PDF'),
                      ),
                    ),
                  ),
                                    PopupMenuItem(
                    value: 'backup',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.backup_rounded),
                      title: Text(t('Backup Database', 'Backup Database')),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'restore',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.restore_rounded),
                      title: Text(t('Restore Backup', 'Restore Backup')),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'lock',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.lock_rounded),
                      title: Text(t('App Lock / Password', 'App Lock / Password')),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'language',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.language_rounded),
                      title: Text(widget.english ? 'বাংলা' : 'English'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'refresh',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.refresh_rounded),
                      title: Text(t('Refresh', 'Refresh')),
                    ),
                  ),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: addCustomer,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: Text(t('ইউজার যোগ', 'Add Customer')),
          ),
          body: RefreshIndicator(
            onRefresh: loadCustomers,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
              children: [
                _heroHeader(desktop),
                const SizedBox(height: 12),
                _summaryStrip(),
                const SizedBox(height: 12),
                _filterBar(),
                const SizedBox(height: 12),
                if (searchText.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '${t('খোঁজা হচ্ছে', 'Searching')}: $searchText • ${filtered.length}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                                const SizedBox(height: 8),
                if (loading)
                  const SizedBox(
                    height: 300,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (filtered.isEmpty)
                  SizedBox(
                    height: 300,
                    child: Center(
                      child: Text(
                        t('কোনো ইউজার পাওয়া যায়নি', 'No customer found'),
                      ),
                    ),
                  )
                else if (desktop)
                  _customerTable()
                else
                  ...filtered.map(customerCard),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _heroHeader(bool desktop) {
    return Container(
      padding: EdgeInsets.all(desktop ? 22 : 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [_brandBlue, _brandPurple, _brandPink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            blurRadius: 22,
            offset: Offset(0, 10),
            color: Color(0x22000000),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: desktop ? 78 : 64,
            height: desktop ? 78 : 64,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Image.asset('assets/logo.png', fit: BoxFit.contain),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Digital 24 Online',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: desktop ? 27 : 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Internet Service Provider',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Seroil Colony, 4 No. Road, Ghoramara, Chandrima Rajshahi-6100',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _summaryStrip() {
    final items = [
      ('মোট ইউজার', '${bnNumber(customers.length)}', Icons.people_alt_rounded, _brandBlue),
      ('Active', '$activeCount', Icons.wifi_rounded, Colors.green),
      ('Closed', '$closedCount', Icons.wifi_off_rounded, Colors.red),
      ('মোট বিল', '${money(totalBill)} ৳', Icons.receipt_long_rounded, _brandPurple),
      ('পরিশোধ', '${money(totalPaid)} ৳', Icons.payments_rounded, _brandCyan),
      ('বকেয়া', '${money(totalDue)} ৳', Icons.money_off_rounded, _brandPink),
    ];

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final item = items[i];
          return Container(
            width: 154,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E9F2)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: (item.$4 as Color).withOpacity(.12),
                  foregroundColor: item.$4 as Color,
                  child: Icon(item.$3, size: 20),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _filterBar() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E9F2)),
      ),
      child: Row(
        children: [
          Expanded(child: chip('সকল', 0)),
          Expanded(child: chip('৭ তারিখ', 7)),
          Expanded(child: chip('১৪ তারিখ', 14)),
          Expanded(child: chip('২১ তারিখ', 21)),
        ],
      ),
    );
  }
  
  Widget _customerTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE6F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 50,
          dataRowMinHeight: 58,
          dataRowMaxHeight: 70,
          columnSpacing: 22,
          headingRowColor: WidgetStatePropertyAll(
            const Color(0xFF129EB7),
          ),
          columns: [
            DataColumn(
              label: Text(
                'SN',
                style: _tableHeaderStyle,
              ),
            ),
            DataColumn(
              label: Text(
                t('Cust ID', 'Cust ID'),
                style: _tableHeaderStyle,
              ),
            ),
            DataColumn(
              label: Text(
                t('Username', 'Username'),
                style: _tableHeaderStyle,
              ),
            ),
            DataColumn(
              label: Text(
                t('Name', 'Name'),
                style: _tableHeaderStyle,
              ),
            ),
            DataColumn(
              label: Text(
                t('Package', 'Package'),
                style: _tableHeaderStyle,
              ),
            ),
            DataColumn(
              label: Text(
                t('Bill', 'Bill'),
                style: _tableHeaderStyle,
              ),
            ),
            DataColumn(
              label: Text(
                t('Paid', 'Paid'),
                style: _tableHeaderStyle,
              ),
            ),
            DataColumn(
              label: Text(
                t('Balance/Due', 'Balance/Due'),
                style: _tableHeaderStyle,
              ),
            ),
            DataColumn(
              label: Text(
                t('Status', 'Status'),
                style: _tableHeaderStyle,
              ),
            ),
          ],
          rows: filtered.asMap().entries.map((entry) {
            final index = entry.key;
            final c = entry.value;
            return DataRow(
              onSelectChanged: (_) => showDetails(c),
              cells: [
                DataCell(Text('${index + 1}')),
                DataCell(Text('${c.id ?? '-'}')),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        c.active ? Icons.lock_open_rounded : Icons.lock_rounded,
                        size: 18,
                        color: c.active ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Text(c.userId),
                    ],
                  ),
                ),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 190),
                    child: Text(
                      c.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(Text(c.packageName.isEmpty ? '-' : c.packageName)),
                DataCell(Text('${money(c.bill)} ৳')),
                DataCell(Text('${money(c.paid)} ৳')),
                DataCell(
                  Text(
                    '${money(c.due)} ৳',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: c.due > 0 ? Colors.red : Colors.green,
                    ),
                  ),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: (c.active ? Colors.green : Colors.red).withOpacity(.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      c.active ? 'Active' : 'Closed',
                      style: TextStyle(
                        color: c.active ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  TextStyle get _tableHeaderStyle => const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      );

  Widget chip(String label, int value) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ChoiceChip(
          label: Text(
            widget.english
                ? ({'সকল': 'All', '৭ তারিখ': '7', '১৪ তারিখ': '14', '২১ তারিখ': '21'}[label] ?? label)
                : label,
          ),
          selected: selectedBillDate == value,
          showCheckmark: false,
          onSelected: (_) async {
            setState(() {
              selectedBillDate = value;
              searchText = '';
            });
            await loadCustomers();
          },
        ),
      );

  Widget summary(String title, String value, IconData icon) => Container(width: 142, height: 82, margin: const EdgeInsets.symmetric(horizontal: 4), padding: const EdgeInsets.all(9), decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)), child: Row(children: [CircleAvatar(radius: 19, child: Icon(icon, size: 19)), const SizedBox(width: 7), Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 11)), Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))]))]));

  Widget customerCard(Customer c) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: InkWell(
          onTap: () => showDetails(c),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_brandBlue, _brandCyan],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.person_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ক্রমিক নং: ${customers.indexOf(c) + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          Text(c.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                          Text(
                            'ID: ${c.userId}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                                        PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'details') await showDetails(c);
                        if (v == 'edit') await editCustomer(c);
                        if (v == 'history') await showPaymentHistory(c);
                        if (v == 'status') await toggleCustomer(c);
                        if (v == 'delete') await deleteCustomer(c);
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'details', child: Text(t('বিস্তারিত', 'Details'))),
                        PopupMenuItem(value: 'edit', child: Text(t('তথ্য পরিবর্তন', 'Edit'))),
                        PopupMenuItem(value: 'history', child: Text(t('পেমেন্ট হিস্ট্রি', 'Payment History'))),
                        PopupMenuItem(
                          value: 'status',
                          child: Text(c.active ? t('Closed করুন', 'Close') : t('Active করুন', 'Activate')),
                        ),
                        PopupMenuItem(value: 'delete', child: Text(t('মুছে ফেলুন', 'Delete'))),
                      ],
                    ),
                  ],
                ),
                const Divider(),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _tag(Icons.phone, c.mobile.isEmpty ? t('মোবাইল নেই', 'No mobile') : c.mobile),
                    _tag(Icons.speed, c.packageName.isEmpty ? t('প্যাকেজ নেই', 'No package') : c.packageName),
                    _tag(Icons.calendar_month, '${t('বিল ডেট: ', 'Billing date ')}${c.billDate}'),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: amountBox(t('বিল', 'Bill'), c.bill)),
                    const SizedBox(width: 6),
                    Expanded(child: amountBox(t('পরিশোধ', 'Paid'), c.paid)),
                    const SizedBox(width: 6),
                    Expanded(child: amountBox(t('বকেয়া', 'Due'), c.due, due: c.due > 0)),
                  ],
                ),
                const SizedBox(height: 8),
                                Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.active ? '● Active' : '● Closed',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: c.active ? Colors.green : Colors.red,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => takePayment(c),
                      icon: const Icon(Icons.payments, size: 18),
                      label: Text(t('পেমেন্ট', 'Payment')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    
  Widget _tag(IconData i, String text) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 15), const SizedBox(width: 4), Text(text)]));
  Widget amountBox(String title, double value, {bool due = false}) => Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Theme.of(context).colorScheme.surfaceContainerHighest), child: Column(children: [Text(title, style: const TextStyle(fontSize: 11)), Text('${money(value)} ৳', style: TextStyle(fontWeight: FontWeight.bold, color: due ? Colors.red : null))]));
}

class PackageManager extends StatefulWidget {
  final DatabaseHelper db;
  final bool english;
  const PackageManager({super.key, required this.db, required this.english});
  @override State<PackageManager> createState() => _PackageManagerState();
}

class _PackageManagerState extends State<PackageManager> {
  List<Map<String, dynamic>> rows = [];
  String t(String b, String e) => widget.english ? e : b;

  @override void initState() { super.initState(); load(); }

  Future<void> load() async {
    try {
      final r = await widget.db.getPackages();
      if (mounted) setState(() => rows = r);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> edit([Map<String, dynamic>? old]) async {
    final n = TextEditingController(text: '${old?['name'] ?? ''}');
    final speed = TextEditingController(text: '${old?['speed'] ?? ''}');
    final price = TextEditingController(text: '${old?['price'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(old == null ? t('নতুন প্যাকেজ', 'New Package') : t('প্যাকেজ পরিবর্তন', 'Edit Package')),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: n, decoration: InputDecoration(labelText: t('প্যাকেজের নাম', 'Package name'))),
          const SizedBox(height: 10),
          TextField(controller: speed, decoration: InputDecoration(labelText: t('স্পিড', 'Speed'))),
          const SizedBox(height: 10),
          TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: t('মূল্য', 'Price'))),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('বাতিল', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('সংরক্ষণ', 'Save'))),
        ],
      ),
    );
            if (ok == true) {
      try {
        final name = n.text.trim();
        final p = double.tryParse(price.text.trim()) ?? -1;
        if (name.isEmpty || p < 0) throw Exception(t('সঠিক প্যাকেজ ও মূল্য দিন', 'Enter a valid package and price'));
        if (old == null) {
          await widget.db.addPackage(name, speed.text.trim(), p);
        } else {
          await widget.db.updatePackage((old['id'] as num).toInt(), name, speed.text.trim(), p);
        }
        await load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    n.dispose(); speed.dispose(); price.dispose();
  }

  @override Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('Package Management', 'Package Management')),
      content: SizedBox(
        width: double.maxFinite,
        height: 460,
        child: rows.isEmpty
            ? Center(child: Text(t('কোনো প্যাকেজ নেই', 'No packages')))
            : ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final r = rows[i];
                  final active = (r['active'] ?? 1) == 1;
                  return ListTile(
                    title: Text('${r['name'] ?? ''}'),
                    subtitle: Text('${r['speed'] ?? ''} • ${r['price'] ?? 0} ৳'),
                    leading: Icon(active ? Icons.speed : Icons.speed_outlined),
                    trailing: Wrap(children: [
                      IconButton(onPressed: () => edit(r), icon: const Icon(Icons.edit)),
                      Switch(value: active, onChanged: (v) async {
                        await widget.db.setPackageActive((r['id'] as num).toInt(), v);
                        await load();
                      }),
                    ]),
                  );
                },
              ),
      ),
      actions: [
        TextButton(onPressed: () => edit(), child: Text(t('নতুন প্যাকেজ', 'Add Package'))),
        FilledButton(onPressed: () => Navigator.pop(context), child: Text(t('বন্ধ', 'Close'))),
      ],
    );
  }
}

class StaffManager extends StatefulWidget {
  final DatabaseHelper db;
  final bool english;
  const StaffManager({super.key, required this.db, required this.english});
  @override State<StaffManager> createState() => _StaffManagerState();
}

class _StaffManagerState extends State<StaffManager> {
  List<Map<String, dynamic>> rows = [];
  String t(String b, String e) => widget.english ? e : b;

  @override void initState() { super.initState(); load(); }

  Future<void> load() async {
    try {
      final r = await widget.db.getStaff();
      if (mounted) setState(() => rows = r);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
  
  Future<void> collectionReport() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => MasterReportCenter(
        db: widget.db,
        english: widget.english,
      ),
    );
  }

  Future<void> add() async {
    final n = TextEditingController();
    final m = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('স্টাফ যোগ', 'Add Staff')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: n, decoration: InputDecoration(labelText: t('নাম', 'Name'))),
          const SizedBox(height: 10),
          TextField(controller: m, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: t('মোবাইল', 'Mobile'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('বাতিল', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('সংরক্ষণ', 'Save'))),
        ],
      ),
    );
    if (ok == true && n.text.trim().isNotEmpty) {
      try {
        await widget.db.addStaff(n.text.trim(), m.text.trim());
        await load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    n.dispose(); m.dispose();
  }
  
  @override Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('Staff Collection', 'Staff Collection')),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: rows.isEmpty
            ? Center(child: Text(t('কোনো active staff নেই', 'No active staff')))
            : ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) => ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text('${rows[i]['name'] ?? ''}'),
                  subtitle: Text('${rows[i]['mobile'] ?? ''}'),
                ),
              ),
      ),
      actions: [
        TextButton.icon(
          onPressed: collectionReport,
          icon: const Icon(Icons.assessment_rounded),
          label: Text(t('Collection Report', 'Collection Report')),
        ),
        TextButton(onPressed: add, child: Text(t('স্টাফ যোগ', 'Add Staff'))),
        FilledButton(onPressed: () => Navigator.pop(context), child: Text(t('বন্ধ', 'Close'))),
      ],
    );
  }
}

class ReportManager extends StatefulWidget {
  final DatabaseHelper db;
  final bool english;
  final Future<void> Function(Customer, Map<String, dynamic>) onPrintReceipt;
  const ReportManager({super.key, required this.db, required this.english, required this.onPrintReceipt});
  @override State<ReportManager> createState() => _ReportManagerState();
}

class _ReportManagerState extends State<ReportManager> {
  DateTime from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime to = DateTime.now();
  String month = DateFormat('yyyy-MM').format(DateTime.now());
  List<Map<String, dynamic>> payments = [];
  List<Map<String, dynamic>> dues = [];
  bool busy = false;
  String t(String b, String e) => widget.english ? e : b;

  Future<void> loadPayments() async {
    setState(() => busy = true);
    try {
      payments = await widget.db.getPaymentsReport(DateFormat('yyyy-MM-dd').format(from), DateFormat('yyyy-MM-dd').format(to));
      dues = [];
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> loadDue() async {
    setState(() => busy = true);
    try {
      dues = await widget.db.getDueReport(month);
      payments = [];
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pick(bool isFrom) async {
    final d = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDate: isFrom ? from : to);
    if (d != null) setState(() { if (isFrom) from = d; else to = d; });
  }

  double sum(List<Map<String, dynamic>> r) => r.fold(0, (s, x) => s + ((x['amount'] ?? 0) as num).toDouble());

  @override Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('Reports', 'Reports')),
      content: SizedBox(
        width: double.maxFinite,
        height: 540,
        child: Column(children: [
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => pick(true), child: Text(DateFormat('yyyy-MM-dd').format(from)))),
            const SizedBox(width: 6),
            Expanded(child: OutlinedButton(onPressed: () => pick(false), child: Text(DateFormat('yyyy-MM-dd').format(to)))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: FilledButton(onPressed: busy ? null : loadPayments, child: Text(t('Collection Report', 'Collection Report')))),
            const SizedBox(width: 6),
            Expanded(child: OutlinedButton(onPressed: busy ? null : loadDue, child: Text(t('Due Report', 'Due Report')))),
          ]),
                              const SizedBox(height: 8),
          if (busy) const LinearProgressIndicator(),
          Expanded(
            child: payments.isNotEmpty
                ? ListView.separated(
                    itemCount: payments.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (_, i) {
                      final r = payments[i];
                      return ListTile(
                        title: Text('${r['user_id'] ?? ''} - ${r['name'] ?? ''}'),
                        subtitle: Text('${r['payment_date'] ?? ''} • ${r['staff_name'] ?? ''}\n${r['receipt_no'] ?? ''}'),
                        trailing: Text('${r['amount'] ?? 0} ৳'),
                      );
                    },
                  )
                : dues.isNotEmpty
                    ? ListView.separated(
                        itemCount: dues.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (_, i) {
                          final r = dues[i];
                          final due = ((r['amount'] ?? 0) as num).toDouble() - ((r['paid'] ?? 0) as num).toDouble();
                          return ListTile(
                            title: Text('${r['user_id'] ?? ''} - ${r['name'] ?? ''}'),
                            subtitle: Text('${r['package_name'] ?? ''}'),
                            trailing: Text('${due.clamp(0, double.infinity).toStringAsFixed(0)} ৳', style: const TextStyle(fontWeight: FontWeight.bold)),
                          );
                        },
                      )
                    : Center(child: Text(t('রিপোর্ট নির্বাচন করুন', 'Select a report'))),
          ),
          if (payments.isNotEmpty) Text('${t('মোট Collection', 'Total Collection')}: ${sum(payments).toStringAsFixed(0)} ৳', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(t('বন্ধ', 'Close')))],
    );
  }
}
