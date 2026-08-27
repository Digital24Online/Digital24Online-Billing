import 'package:flutter/material.dart';
import 'database_helper.dart';

void main() {
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

  double get due => bill - paid;
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
                      decoration: const InputDecoration(
                        labelText: 'ইউজার আইডি নাম্বার',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
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
                      value: selectedDate,
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
                        labelText: 'বিলের টাকা',
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
                FilledButton(
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
                        double.tryParse(bill.text) ?? 0;

                    final paidAmount =
                        double.tryParse(paid.text) ?? 0;

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

                    final today = DateTime.now()
                        .toLocal()
                        .toString()
                        .split(' ')
                        .first;

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
                  child: const Text('সংরক্ষণ'),
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

    final paymentController =
        TextEditingController();

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
                  'মোট বিল: '
                  '${customer.bill.toStringAsFixed(0)} টাকা',
                ),
                const SizedBox(height: 4),
                Text(
                  'ইতোমধ্যে পরিশোধ: '
                  '${customer.paid.toStringAsFixed(0)} টাকা',
                ),
                const SizedBox(height: 4),
                Text(
                  'বর্তমান বকেয়া: '
                  '${customer.due.toStringAsFixed(0)} টাকা',
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
                    labelText:
                        'আজ কত টাকা পরিশোধ করেছে?',
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
            FilledButton(
              onPressed: () async {
                final payment =
                    double.tryParse(
                          paymentController.text,
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
                        'সর্বোচ্চ '
                        '${customer.due.toStringAsFixed(0)} '
                        'টাকা নেওয়া যাবে',
                      ),
                    ),
                  );
                  return;
                }

                final newPaid =
                    customer.paid + payment;

                final newDue =
                    customer.bill - newPaid;

                final today = DateTime.now()
                    .toLocal()
                    .toString()
                    .split(' ')
                    .first;

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
                      '${payment.toStringAsFixed(0)} টাকা '
                      'পেমেন্ট গ্রহণ করা হয়েছে',
                    ),
                  ),
                );
              },
              child: const Text(
                'পেমেন্ট সংরক্ষণ',
              ),
            ),
          ],
        );
      },
    );

    paymentController.dispose();
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
            'এই ইউজারের তথ্য স্থায়ীভাবে মুছে যাবে।',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text('না'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: const Text('মুছে ফেলুন'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    await db.deleteCustomer(customer.id!);

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

  String get reportTitle {
    if (selectedBillDate == 7) {
      return '৭ তারিখের বিল';
    }

    if (selectedBillDate == 14) {
      return '১৪ তারিখের বিল';
    }

    if (selectedBillDate == 21) {
      return '২১ তারিখের বিল';
    }

    return 'সকল ইউজার';
  }

  Widget summaryCard(
    String title,
    String value,
    IconData icon,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 4,
      ),
      child: Container(
        width: 130,
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(
              icon,
              size: 28,
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

    Widget customerCard(
    Customer customer,
    int index,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  child: Text(
                    '${index + 1}',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${customer.userId} - ${customer.name}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'মোবাইল: ${customer.mobile}',
                      ),
                      Text(
                        'প্যাকেজ: ${customer.packageName}',
                      ),
                      Text(
                        'বিল ডেট: ${customer.billDate} তারিখ',
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    IconButton(
                      onPressed: () {
                        toggleCustomer(index);
                      },
                      icon: Icon(
                        customer.active
                            ? Icons.check_circle
                            : Icons.cancel,
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        deleteCustomer(index);
                      },
                      icon: const Icon(Icons.delete),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('বিল'),
                    Text(
                      '${customer.bill.toStringAsFixed(0)} ৳',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    const Text('পরিশোধ'),
                    Text(
                      '${customer.paid.toStringAsFixed(0)} ৳',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    const Text('বকেয়া'),
                    Text(
                      '${customer.due.toStringAsFixed(0)} ৳',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: customer.due > 0
                            ? Colors.red
                            : Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

SizedBox(
  width: double.infinity,
  child: FilledButton.icon(
    onPressed: customer.due > 0
        ? () {
            takePayment(index);
          }
        : null,
    icon: const Icon(Icons.payments),
    label: Text(
      customer.due > 0
          ? 'পেমেন্ট গ্রহণ'
          : 'সম্পূর্ণ পরিশোধ',
    ),
  ),
),

const SizedBox(height: 8),

SizedBox(
  width: double.infinity,
  child: OutlinedButton.icon(
    onPressed: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentHistoryPage(
            db: db,
            customer: customer,
          ),
        ),
      );
    },
    icon: const Icon(Icons.history),
    label: const Text('পেমেন্ট হিস্ট্রি'),
  ),
),
          ],
        ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Digital 24 Online Billing',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
  PopupMenuButton<String>(
    onSelected: (value) async {
      if (value == 'backup') {
        await db.backupDatabase();
      } else if (value == 'restore') {
        await db.restoreDatabase();
        await loadCustomers();
      }
    },
    itemBuilder: (context) => const [
      PopupMenuItem(
        value: 'backup',
        child: Text('Database Backup'),
      ),
      PopupMenuItem(
        value: 'restore',
        child: Text('Database Restore'),
      ),
    ],
  ),
],
        centerTitle: true,
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
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Seroil Colony, 4 No. Road, Ghoramara, '
                'Chandrima Rajshahi-6100',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('সকল'),
                    selected: selectedBillDate == 0,
                    onSelected: (_) {
                      showAllUsers();
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('৭ তারিখ'),
                    selected: selectedBillDate == 7,
                    onSelected: (_) {
                      selectBillDate(7);
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('১৪ তারিখ'),
                    selected: selectedBillDate == 14,
                    onSelected: (_) {
                      selectBillDate(14);
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('২১ তারিখ'),
                    selected: selectedBillDate == 21,
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
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    summaryCard(
                      'মোট বিল',
                      '${totalBill.toStringAsFixed(0)} ৳',
                      Icons.receipt_long,
                    ),
                    summaryCard(
                      'পরিশোধ',
                      '${totalPaid.toStringAsFixed(0)} ৳',
                      Icons.payments,
                    ),
                    summaryCard(
                      'বকেয়া',
                      '${totalDue.toStringAsFixed(0)} ৳',
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
                      child: CircularProgressIndicator(),
                    )
                  : customers.isEmpty
                      ? const Center(
                          child: Text(
                            'কোনো ইউজার পাওয়া যায়নি',
                          ),
                        )
                      : ListView.builder(
                          itemCount: customers.length,
                          itemBuilder: (context, index) {
                            return customerCard(
                              customers[index],
                              index,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
