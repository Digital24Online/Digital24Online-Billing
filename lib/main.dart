import 'package:flutter/material.dart';
import 'database_helper.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Digital24OnlineBilling());
}

class Digital24OnlineBilling extends StatelessWidget {
  const Digital24OnlineBilling({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Digital 24 Online Billing',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(),
        ),
      ),
      home: const BillingHomePage(),
    );
  }
}

class Customer {
  int? id;
  String userId;
  String name;
  String mobile;
  String packageName;
  int billDate;
  double bill;
  double paid;
  String paymentDate;
  bool active;

  Customer({
    this.id,
    required this.userId,
    required this.name,
    required this.mobile,
    required this.packageName,
    required this.billDate,
    required this.bill,
    required this.paid,
    required this.paymentDate,
    this.active = true,
  });

  double get due {
    final value = bill - paid;
    return value < 0 ? 0 : value;
  }
}

class PaymentHistoryPage extends StatelessWidget {
  final DatabaseHelper db;
  final Customer customer;

  const PaymentHistoryPage({
    super.key,
    required this.db,
    required this.customer,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('পেমেন্ট হিস্ট্রি'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: db.getPaymentHistory(customer.id!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'হিসাব দেখাতে সমস্যা হয়েছে\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final payments = snapshot.data ?? [];

          if (payments.isEmpty) {
            return const Center(
              child: Text(
                'এখনও কোনো পেমেন্ট হিস্ট্রি নেই',
                style: TextStyle(fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: payments.length,
            itemBuilder: (context, index) {
              final payment = payments[index];

              final amount =
                  (payment['amount'] as num?)?.toDouble() ?? 0;

              final date =
                  payment['payment_date']?.toString() ?? '';

              final note =
                  payment['note']?.toString() ?? '';

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.payments),
                  ),
                  title: Text(
                    '${amount.toStringAsFixed(0)} ৳',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'তারিখ: $date'
                      '${note.isNotEmpty ? '\n$note' : ''}',
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class BillingHomePage extends StatefulWidget {
  const BillingHomePage({super.key});

  @override
  State<BillingHomePage> createState() => _BillingHomePageState();
}

class _BillingHomePageState extends State<BillingHomePage> {
  final DatabaseHelper db = DatabaseHelper.instance;

  final List<Customer> customers = [];

  int selectedBillDate = 0;
  bool loading = true;

  String searchText = '';

  List<Customer> get filteredCustomers {
    final query = searchText.trim().toLowerCase();

    if (query.isEmpty) {
      return customers;
    }

    return customers.where((customer) {
      return customer.userId.toLowerCase().contains(query) ||
          customer.name.toLowerCase().contains(query) ||
          customer.mobile.toLowerCase().contains(query) ||
          customer.packageName.toLowerCase().contains(query);
    }).toList();
  }

  double get totalBill {
    return customers.fold(
      0,
      (sum, customer) => sum + customer.bill,
    );
  }

  double get totalPaid {
    return customers.fold(
      0,
      (sum, customer) => sum + customer.paid,
    );
  }

  double get totalDue {
    return customers.fold(
      0,
      (sum, customer) => sum + customer.due,
    );
  }

  int get totalUsers => customers.length;

  int get activeUsers {
    return customers.where((customer) => customer.active).length;
  }

  int get closedUsers {
    return customers.where((customer) => !customer.active).length;
  }

  String get reportTitle {
    if (selectedBillDate == 0) {
      return 'সকল ইউজারের হিসাব';
    }

    return '${selectedBillDate.toString()} তারিখের হিসাব';
  }

  @override
  void initState() {
    super.initState();
    loadCustomers();
  }

  Future<void> loadCustomers() async {
    if (mounted) {
      setState(() {
        loading = true;
      });
    }

    try {
      final data = selectedBillDate == 0
          ? await db.getCustomers()
          : await db.getCustomersByBillDate(selectedBillDate);

      final list = data.map((item) {
        final bill =
            (item['amount'] as num?)?.toDouble() ?? 0;

        final paid =
            (item['paid_amount'] as num?)?.toDouble() ?? 0;

        return Customer(
          id: item['id'] as int?,
          userId: item['user_id']?.toString() ?? '',
          name: item['name']?.toString() ?? '',
          mobile: item['mobile']?.toString() ?? '',
          packageName:
              item['package_name']?.toString() ?? '',
          billDate: int.tryParse(
                item['bill_date']?.toString() ?? '',
              ) ??
              7,
          bill: bill,
          paid: paid,
          paymentDate:
              item['payment_date']?.toString() ?? '',
          active: (item['active'] ?? 1) == 1,
        );
      }).toList();

      if (!mounted) return;

      setState(() {
        customers
          ..clear()
          ..addAll(list);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ডেটা লোড করতে সমস্যা হয়েছে: $e',
          ),
        ),
      );
    }
  }

  Future<void> selectBillDate(int date) async {
    setState(() {
      selectedBillDate = date;
    });

    await loadCustomers();
  }

  Future<void> showAllUsers() async {
    setState(() {
      selectedBillDate = 0;
    });

    await loadCustomers();
  }

  String todayDate() {
    return DateTime.now()
        .toLocal()
        .toString()
        .split(' ')
        .first;
  }

  String money(double value) {
    return value.toStringAsFixed(0);
  }

  Widget summaryCard(
    String title,
    String value,
    IconData icon,
  ) {
    return Card(
      margin: const EdgeInsets.only(left: 8, right: 4),
      child: SizedBox(
        width: 145,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 21,
                child: Icon(icon, size: 21),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> addCustomer() async {
    final userId = TextEditingController();
    final name = TextEditingController();
    final mobile = TextEditingController();
    final packageName = TextEditingController();
    final bill = TextEditingController();
    final paid = TextEditingController();

    int selectedDate = 7;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'নতুন ইউজার যোগ করুন',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: userId,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'ইউজার আইডি নাম্বার *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: name,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'ইউজার আইডি ও নাম *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: mobile,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'মোবাইল নাম্বার',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: packageName,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'প্যাকেজ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: selectedDate,
                      decoration: const InputDecoration(
                        labelText: 'বিল ডেট',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 7,
                          child: Text('৭ তারিখ'),
                        ),
                        DropdownMenuItem(
                          value: 14,
                          child: Text('১৪ তারিখ'),
                        ),
                        DropdownMenuItem(
                          value: 21,
                          child: Text('২১ তারিখ'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            selectedDate = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bill,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'বিলের টাকা *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: paid,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'প্রাথমিক পরিশোধ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('বাতিল'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    if (userId.text.trim().isEmpty ||
                        name.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'ইউজার আইডি ও নাম লিখুন',
                          ),
                        ),
                      );
                      return;
                    }

                    final billAmount =
                        double.tryParse(bill.text.trim()) ?? 0;

                    final paidAmount =
                        double.tryParse(paid.text.trim()) ?? 0;

                    if (billAmount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'বিলের টাকা লিখুন',
                          ),
                        ),
                      );
                      return;
                    }

                    if (paidAmount < 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'সঠিক পরিশোধের টাকা লিখুন',
                          ),
                        ),
                      );
                      return;
                    }

                    if (paidAmount > billAmount) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'পরিশোধের টাকা বিলের চেয়ে বেশি হতে পারবে না',
                          ),
                        ),
                      );
                      return;
                    }

                    final existing =
                        await db.getCustomerByUserId(
                      userId.text.trim(),
                    );

                    if (existing != null) {
                      if (!context.mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'এই ইউজার আইডি আগে থেকেই আছে',
                          ),
                        ),
                      );
                      return;
                    }

                    final today = todayDate();

                    final customerId =
                        await db.addCustomer({
                      'user_id': userId.text.trim(),
                      'name': name.text.trim(),
                      'mobile': mobile.text.trim(),
                      'package_name':
                          packageName.text.trim(),
                      'bill_date': selectedDate,
                      'amount': billAmount,
                      'total_amount': billAmount,
                      'paid_amount': paidAmount,
                      'payment_date':
                          paidAmount > 0 ? today : '',
                      'due_amount':
                          billAmount - paidAmount,
                      'active': 1,
                    });

                    if (paidAmount > 0) {
                      await db.addPayment({
                        'customer_id': customerId,
                        'user_id': userId.text.trim(),
                        'amount': paidAmount,
                        'payment_date': today,
                        'note': 'প্রাথমিক পরিশোধ',
                      });
                    }

                    if (!mounted) return;

                    Navigator.pop(dialogContext);

                    await loadCustomers();

                    if (!mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'ইউজার সফলভাবে সংরক্ষণ হয়েছে',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('সংরক্ষণ'),
                ),
              ],
            );
          },
        );
      },
    );

    userId.dispose();
    name.dispose();
    mobile.dispose();
    packageName.dispose();
    bill.dispose();
    paid.dispose();
  }
    Future<void> takePayment(int index) async {
    final customer = customers[index];

    if (customer.id == null) return;

    if (customer.due <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'এই ইউজারের কোনো বকেয়া নেই',
          ),
        ),
      );
      return;
    }

    final paymentController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('পেমেন্ট গ্রহণ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${customer.userId} - ${customer.name}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'মোট বিল: ${money(customer.bill)} টাকা',
                ),
                const SizedBox(height: 4),
                Text(
                  'ইতোমধ্যে পরিশোধ: ${money(customer.paid)} টাকা',
                ),
                const SizedBox(height: 4),
                Text(
                  'বর্তমান বকেয়া: ${money(customer.due)} টাকা',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: paymentController,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'আজ কত টাকা পরিশোধ করেছে?',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('বাতিল'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final payment =
                    double.tryParse(
                          paymentController.text.trim(),
                        ) ??
                        0;

                if (payment <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'সঠিক পরিমাণ টাকা লিখুন',
                      ),
                    ),
                  );
                  return;
                }

                if (payment > customer.due) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'সর্বোচ্চ ${money(customer.due)} টাকা নেওয়া যাবে',
                      ),
                    ),
                  );
                  return;
                }

                final newPaid =
                    customer.paid + payment;

                final newDue =
                    customer.bill - newPaid;

                final today = todayDate();

                await db.updateCustomer(
                  customer.id!,
                  {
                    'paid_amount': newPaid,
                    'due_amount': newDue,
                    'payment_date': today,
                  },
                );

                await db.addPayment({
                  'customer_id': customer.id!,
                  'user_id': customer.userId,
                  'amount': payment,
                  'payment_date': today,
                  'note': 'Customer Payment',
                });

                if (!mounted) return;

                Navigator.pop(dialogContext);

                await loadCustomers();

                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${money(payment)} টাকা পেমেন্ট গ্রহণ করা হয়েছে',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.save),
              label: const Text('পেমেন্ট সংরক্ষণ'),
            ),
          ],
        );
      },
    );

    paymentController.dispose();
  }

  Future<void> showPaymentHistory(
    Customer customer,
  ) async {
    if (customer.id == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentHistoryPage(
          db: db,
          customer: customer,
        ),
      ),
    );
  }

  Future<void> editCustomer(int index) async {
    final customer = customers[index];

    if (customer.id == null) return;

    final name = TextEditingController(
      text: customer.name,
    );
    final mobile = TextEditingController(
      text: customer.mobile,
    );
    final packageName = TextEditingController(
      text: customer.packageName,
    );
    final bill = TextEditingController(
      text: money(customer.bill),
    );

    int selectedDate = customer.billDate;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('ইউজার তথ্য পরিবর্তন'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'ইউজার আইডি ও নাম',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: mobile,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'মোবাইল নাম্বার',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: packageName,
                      decoration: const InputDecoration(
                        labelText: 'প্যাকেজ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: selectedDate,
                      decoration: const InputDecoration(
                        labelText: 'বিল ডেট',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 7,
                          child: Text('৭ তারিখ'),
                        ),
                        DropdownMenuItem(
                          value: 14,
                          child: Text('১৪ তারিখ'),
                        ),
                        DropdownMenuItem(
                          value: 21,
                          child: Text('২১ তারিখ'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            selectedDate = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bill,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'মাসিক বিল',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: Colors.blue.withValues(
                          alpha: 0.08,
                        ),
                      ),
                      child: Text(
                        'ইউজার আইডি: ${customer.userId}\n'
                        'বর্তমান পরিশোধ: ${money(customer.paid)} টাকা\n'
                        'বর্তমান বকেয়া: ${money(customer.due)} টাকা',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('বাতিল'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final newName =
                        name.text.trim();

                    final newBill =
                        double.tryParse(
                              bill.text.trim(),
                            ) ??
                            0;

                    if (newName.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'নাম লিখুন',
                          ),
                        ),
                      );
                      return;
                    }

                    if (newBill <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'সঠিক মাসিক বিল লিখুন',
                          ),
                        ),
                      );
                      return;
                    }

                    if (newBill < customer.paid) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'মাসিক বিল ইতোমধ্যে পরিশোধ করা টাকার চেয়ে কম হতে পারবে না',
                          ),
                        ),
                      );
                      return;
                    }

                    final newDue =
                        newBill - customer.paid;

                    await db.updateCustomer(
                      customer.id!,
                      {
                        'name': newName,
                        'mobile': mobile.text.trim(),
                        'package_name':
                            packageName.text.trim(),
                        'bill_date': selectedDate,
                        'amount': newBill,
                        'total_amount': newBill,
                        'due_amount': newDue,
                      },
                    );

                    if (!mounted) return;

                    Navigator.pop(dialogContext);

                    await loadCustomers();

                    if (!mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'ইউজারের তথ্য পরিবর্তন হয়েছে',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('পরিবর্তন সংরক্ষণ'),
                ),
              ],
            );
          },
        );
      },
    );

    name.dispose();
    mobile.dispose();
    packageName.dispose();
    bill.dispose();
  }

  Future<void> toggleCustomer(int index) async {
    final customer = customers[index];

    if (customer.id == null) return;

    final newStatus = !customer.active;

    await db.updateCustomerStatus(
      customer.id!,
      newStatus,
    );

    if (!mounted) return;

    setState(() {
      customer.active = newStatus;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newStatus
              ? 'ইউজার Active করা হয়েছে'
              : 'ইউজার Closed করা হয়েছে',
        ),
      ),
    );
  }

  Future<void> deleteCustomer(int index) async {
    final customer = customers[index];

    if (customer.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'ইউজার মুছে ফেলবেন?',
          ),
          content: Text(
            '${customer.userId} - ${customer.name}\n\n'
            'এই ইউজারের তথ্য ও পেমেন্ট হিস্ট্রি মুছে যাবে।\n'
            'এই কাজটি আর ফিরিয়ে আনা যাবে না।',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('বাতিল'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('মুছে ফেলুন'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    await db.deleteCustomer(customer.id!);

    if (!mounted) return;

    await loadCustomers();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'ইউজার মুছে ফেলা হয়েছে',
        ),
      ),
    );
  }

  Widget customerCard(
    Customer customer,
    int index,
  ) {
    final due = customer.due;

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.userId,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        customer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: customer.active
                        ? Colors.green.withValues(alpha: 0.12)
                        : Colors.red.withValues(alpha: 0.12),
                  ),
                  child: Text(
                    customer.active
                        ? 'Active'
                        : 'Closed',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: customer.active
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 18),
            Row(
              children: [
                Expanded(
                  child: _infoItem(
                    'মোবাইল',
                    customer.mobile.isEmpty
                        ? '-'
                        : customer.mobile,
                    Icons.phone,
                  ),
                ),
                Expanded(
                  child: _infoItem(
                    'প্যাকেজ',
                    customer.packageName.isEmpty
                        ? '-'
                        : customer.packageName,
                    Icons.wifi,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _infoItem(
                    'বিল',
                    '${money(customer.bill)} ৳',
                    Icons.receipt_long,
                  ),
                ),
                Expanded(
                  child: _infoItem(
                    'পরিশোধ',
                    '${money(customer.paid)} ৳',
                    Icons.payments,
                  ),
                ),
                Expanded(
                  child: _infoItem(
                    'বকেয়া',
                    '${money(due)} ৳',
                    Icons.money_off,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: due > 0
                        ? () => takePayment(index)
                        : null,
                    icon: const Icon(
                      Icons.payments,
                      size: 18,
                    ),
                    label: const Text('পেমেন্ট'),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'পেমেন্ট হিস্ট্রি',
                  onPressed: () {
                    showPaymentHistory(customer);
                  },
                  icon: const Icon(
                    Icons.history,
                  ),
                ),
                IconButton(
                  tooltip: 'এডিট',
                  onPressed: () {
                    editCustomer(index);
                  },
                  icon: const Icon(
                    Icons.edit,
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'status') {
                      toggleCustomer(index);
                    } else if (value == 'delete') {
                      deleteCustomer(index);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'status',
                      child: Text(
                        customer.active
                            ? 'Closed করুন'
                            : 'Active করুন',
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
    child: Text(
                        'ইউজার মুছে ফেলুন',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoItem(
    String title,
    String value,
    IconData icon,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 17,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  Future<void> showDashboardDetails() async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('হিসাবের সারসংক্ষেপ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dashboardRow(
                  'মোট ইউজার',
                  '$totalUsers জন',
                  Icons.people,
                ),
                _dashboardRow(
                  'Active ইউজার',
                  '$activeUsers জন',
                  Icons.wifi,
                ),
                _dashboardRow(
                  'Closed ইউজার',
                  '$closedUsers জন',
                  Icons.wifi_off,
                ),
                const Divider(),
                _dashboardRow(
                  'মোট বিল',
                  '${money(totalBill)} ৳',
                  Icons.receipt_long,
                ),
                _dashboardRow(
                  'মোট পরিশোধ',
                  '${money(totalPaid)} ৳',
                  Icons.payments,
                ),
                _dashboardRow(
                  'মোট বকেয়া',
                  '${money(totalDue)} ৳',
                  Icons.money_off,
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('বন্ধ করুন'),
            ),
          ],
        );
      },
    );
  }

  Widget _dashboardRow(
    String title,
    String value,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 7,
      ),
      child: Row(
        children: [
          Icon(icon, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> showCustomerDetails(
    Customer customer,
  ) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('ইউজারের বিস্তারিত তথ্য'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                _detailRow(
                  'ইউজার আইডি',
                  customer.userId,
                ),
                _detailRow(
                  'নাম',
                  customer.name,
                ),
                _detailRow(
                  'মোবাইল',
                  customer.mobile.isEmpty
                      ? '-'
                      : customer.mobile,
                ),
                _detailRow(
                  'প্যাকেজ',
                  customer.packageName.isEmpty
                      ? '-'
                      : customer.packageName,
                ),
                _detailRow(
                  'বিল ডেট',
                  '${customer.billDate} তারিখ',
                ),
                _detailRow(
                  'মাসিক বিল',
                  '${money(customer.bill)} টাকা',
                ),
                _detailRow(
                  'পরিশোধ',
                  '${money(customer.paid)} টাকা',
                ),
                _detailRow(
                  'বকেয়া',
                  '${money(customer.due)} টাকা',
                ),
                _detailRow(
                  'সর্বশেষ পেমেন্ট',
                  customer.paymentDate.isEmpty
                      ? 'কোনো পেমেন্ট নেই'
                      : customer.paymentDate,
                ),
                _detailRow(
                  'স্ট্যাটাস',
                  customer.active
                      ? 'Active'
                      : 'Closed',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('বন্ধ করুন'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                showPaymentHistory(customer);
              },
              icon: const Icon(Icons.history),
              label: const Text('পেমেন্ট হিস্ট্রি'),
            ),
          ],
        );
      },
    );
  }

  Widget _detailRow(
    String title,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 5,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 115,
            child: Text(
              '$title:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  Future<void> showTodayPayments() async {
    final today = todayDate();

    try {
      final payments =
          await db.getPaymentsByDate(today);

      final summary =
          await db.getPaymentSummary(today);

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text(
              'আজকের পেমেন্ট',
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: payments.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 20,
                      ),
                      child: Text(
                        'আজ কোনো পেমেন্ট গ্রহণ করা হয়নি',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(10),
                            color: Colors.blue.withValues(
                              alpha: 0.08,
                            ),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'আজ মোট কালেকশন',
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${money(summary['total'] ?? 0)} ৳',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${(summary['payment_count'] ?? 0).toInt()} টি পেমেন্ট',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: payments.length,
                            itemBuilder:
                                (context, index) {
                              final payment =
                                  payments[index];

                              final amount =
                                  (payment['amount']
                                          as num?)
                                      ?.toDouble() ??
                                      0;

                              final userId =
                                  payment['user_id']
                                          ?.toString() ??
                                      '';

                              return ListTile(
                                dense: true,
                                leading:
                                    const CircleAvatar(
                                  radius: 18,
                                  child: Icon(
                                    Icons.payments,
                                    size: 18,
                                  ),
                                ),
                                title: Text(
                                  userId,
                                  style:
                                      const TextStyle(
                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),
                                trailing: Text(
                                  '${money(amount)} ৳',
                                  style:
                                      const TextStyle(
                                   fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text('বন্ধ করুন'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'আজকের পেমেন্ট দেখাতে সমস্যা হয়েছে: $e',
          ),
        ),
      );
    }
  }

  void showSearchBox() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final controller =
            TextEditingController(
          text: searchText,
        );

        return AlertDialog(
          title: const Text('ইউজার খুঁজুন'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText:
                  'আইডি / নাম / মোবাইল / প্যাকেজ',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) {
              setState(() {
                searchText = value;
              });
              Navigator.pop(dialogContext);
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  searchText = '';
                });
                Navigator.pop(dialogContext);
              },
              child: const Text('Clear'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  searchText =
                      controller.text.trim();
                });
                Navigator.pop(dialogContext);
              },
              child: const Text('খুঁজুন'),
            ),
          ],
        );
      },
    );
  }

  Future<void> showMoreMenu(
    String value,
  ) async {
    if (value == 'summary') {
      await showDashboardDetails();
    } else if (value == 'today') {
      await showTodayPayments();
    } else if (value == 'backup') {
      await backupDatabase();
    } else if (value == 'restore') {
      await restoreDatabase();
    }
  }

  Future<void> backupDatabase() async {
    try {
      final path = await db.backupDatabase();

      if (!mounted) return;

      if (path != null && path.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Backup সফলভাবে সংরক্ষণ হয়েছে',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Backup করতে সমস্যা হয়েছে: $e',
          ),
        ),
      );
    }
  }

  Future<void> restoreDatabase() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Backup Restore করবেন?',
          ),
          content: const Text(
            'Restore করলে বর্তমান ইউজার, পেমেন্ট ও বিলের '
            'তথ্য Backup-এর তথ্য দিয়ে প্রতিস্থাপিত হবে।\n\n'
            'চালিয়ে যাওয়ার আগে বর্তমান ডেটার Backup রাখা ভালো।',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('বাতিল'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Restore'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      await db.restoreDatabase();

      if (!mounted) return;

      await loadCustomers();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Backup সফলভাবে Restore হয়েছে',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Restore করতে সমস্যা হয়েছে: $e',
          ),
        ),
      );
    }
  }
              List<Customer> get filteredCustomers {
    if (searchText.trim().isEmpty) {
      return customers;
    }

    final query = searchText.trim().toLowerCase();

    return customers.where((customer) {
      return customer.userId.toLowerCase().contains(query) ||
          customer.name.toLowerCase().contains(query) ||
          customer.mobile.toLowerCase().contains(query) ||
          customer.packageName.toLowerCase().contains(query);
    }).toList();
  }

  int get totalUsers {
    return customers.length;
  }

  int get activeUsers {
    return customers.where((customer) {
      return customer.active;
    }).length;
  }

  int get closedUsers {
    return customers.where((customer) {
      return !customer.active;
    }).length;
  }

  String money(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(2);
  }

  String todayDate() {
    final now = DateTime.now().toLocal();

    final year =
        now.year.toString().padLeft(4, '0');

    final month =
        now.month.toString().padLeft(2, '0');

    final day =
        now.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    final visibleCustomers = filteredCustomers;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Digital 24 Online Billing',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'ইউজার খুঁজুন',
            onPressed: showSearchBox,
            icon: const Icon(Icons.search),
          ),
          PopupMenuButton<String>(
            tooltip: 'আরও',
            onSelected: showMoreMenu,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'summary',
                child: ListTile(
                  leading: Icon(Icons.dashboard),
                  title: Text('হিসাবের সারসংক্ষেপ'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'today',
                child: ListTile(
                  leading: Icon(Icons.today),
                  title: Text('আজকের পেমেন্ট'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'backup',
                child: ListTile(
                  leading: Icon(Icons.backup),
                  title: Text('Backup'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'restore',
                child: ListTile(
                  leading: Icon(Icons.restore),
                  title: Text('Restore'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addCustomer,
        icon: const Icon(Icons.person_add),
        label: const Text('ইউজার যোগ'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            const Text(
              'Digital 24 Online',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 8,
              ),
              child: Text(
                'Seroil Colony, 4 No. Road, Ghoramara, '
                'Chandrima Rajshahi-6100',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),

            if (searchText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                ),
                child: Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.search,
                    ),
                    title: Text(
                      'খোঁজা হচ্ছে: $searchText',
                    ),
                    trailing: IconButton(
                      onPressed: () {
                        setState(() {
                          searchText = '';
                        });
                      },
                      icon: const Icon(
                        Icons.clear,
                      ),
                    ),
                  ),
                ),
              ),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('সকল'),
                    selected:
                        selectedBillDate == 0,
                    onSelected: (_) {
                      showAllUsers();
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('৭ তারিখ'),
                    selected:
                        selectedBillDate == 7,
                    onSelected: (_) {
                      selectBillDate(7);
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('১৪ তারিখ'),
                    selected:
                        selectedBillDate == 14,
                    onSelected: (_) {
                      selectBillDate(14);
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('২১ তারিখ'),
                    selected:
                        selectedBillDate == 21,
                    onSelected: (_) {
                      selectBillDate(21);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            Text(
              reportTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            SizedBox(
              height: 100,
              child: SingleChildScrollView(
                scrollDirection:
                    Axis.horizontal,
                child: Row(
                  children: [
                    summaryCard(
                      'মোট বিল',
                      '${money(totalBill)} ৳',
                      Icons.receipt_long,
                    ),
                    summaryCard(
                      'পরিশোধ',
                      '${money(totalPaid)} ৳',
                      Icons.payments,
                    ),
                    summaryCard(
                      'বকেয়া',
                      '${money(totalDue)} ৳',
                      Icons.money_off,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            Expanded(
              child: loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(),
                    )
                  : visibleCustomers.isEmpty
                      ? Center(
                          child: Text(
                            searchText.isNotEmpty
                                ? 'কোনো ইউজার পাওয়া যায়নি'
                                : 'কোনো ইউজার পাওয়া যায়নি',
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh:
                              loadCustomers,
                          child:
                              ListView.builder(
                            padding:
                                const EdgeInsets.only(
                              bottom: 90,
                            ),
                            itemCount:
                                visibleCustomers.length,
                            itemBuilder:
                                (context, index) {
                              final customer =
                                  visibleCustomers[
                                      index];

                              final realIndex =
                                  customers.indexOf(
                                customer,
                              );

                              return GestureDetector(
                                onTap: () {
                                  showCustomerDetails(
                                    customer,
                                  );
                                },
                                child:
                                    customerCard(
                                  customer,
                                  realIndex,
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
              Widget summaryCard(
    String title,
    String value,
    IconData icon,
  ) {
    return Container(
      width: 145,
      margin: const EdgeInsets.only(
        left: 8,
        right: 4,
      ),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outline
              .withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            child: Icon(
              icon,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
            }
