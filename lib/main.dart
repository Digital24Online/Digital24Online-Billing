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

  double get totalBill =>
      customers.fold(0, (sum, customer) => sum + customer.bill);

  double get totalPaid =>
      customers.fold(0, (sum, customer) => sum + customer.paid);

  double get totalDue =>
      customers.fold(0, (sum, customer) => sum + customer.due);

  @override
  void initState() {
    super.initState();
    loadCustomers();
  }

  Future<void> loadCustomers() async {
    setState(() {
      loading = true;
    });

    final data = selectedBillDate == 0
        ? await db.getCustomers()
        : await db.getCustomersByBillDate(selectedBillDate);

    final list = data.map((item) {
      final bill = (item['amount'] as num?)?.toDouble() ?? 0;
      final paid = (item['paid_amount'] as num?)?.toDouble() ?? 0;

      return Customer(
        id: item['id'] as int?,
        userId: item['user_id']?.toString() ?? '',
        name: item['name']?.toString() ?? '',
        mobile: item['mobile']?.toString() ?? '',
        packageName: item['package_name']?.toString() ?? '',
        billDate:
            int.tryParse(item['bill_date']?.toString() ?? '') ?? 7,
        bill: bill,
        paid: paid,
        paymentDate: item['payment_date']?.toString() ?? '',
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
              title: const Text('নতুন ইউজার যোগ করুন'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: userId,
                      decoration: const InputDecoration(
                        labelText: 'ইউজার আইডি নাম্বার',
                      ),
                    ),
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'ইউজার আইডি ও নাম',
                      ),
                    ),
                    TextField(
                      controller: mobile,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'মোবাইল নাম্বার',
                      ),
                    ),
                    TextField(
                      controller: packageName,
                      decoration: const InputDecoration(
                        labelText: 'প্যাকেজ',
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
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'বিলের টাকা',
                      ),
                    ),
                    TextField(
                      controller: paid,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'প্রাথমিক পরিশোধ',
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
                      return;
                    }

                    final billAmount =
                        double.tryParse(bill.text) ?? 0;

                    final paidAmount =
                        double.tryParse(paid.text) ?? 0;

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
                      'package_name': packageName.text.trim(),
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
          content: Text('এই ইউজারের কোনো বকেয়া নেই'),
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
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'মোট বিল: ${customer.bill.toStringAsFixed(0)} টাকা',
                ),
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
                  keyboardType: TextInputType.number,
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
            FilledButton(
              onPressed: () async {
                final payment =
                    double.tryParse(paymentController.text) ?? 0;

                if (payment <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('সঠিক পরিমাণ টাকা লিখুন'),
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

                final newPaid = customer.paid + payment;
                final newDue = customer.bill - newPaid;

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

                if (!mounted) return;

                Navigator.pop(dialogContext);

                await loadCustomers();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${payment.toStringAsFixed(0)} টাকা '
                      'পেমেন্ট গ্রহণ করা হয়েছে',
                    ),
                  ),
                );
              },
              child: const Text('পেমেন্ট সংরক্ষণ'),
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

    setState(() {
      customer.active = newStatus;
    });
  }

  String get reportTitle {
    if (selectedBillDate == 7) return '৭ তারিখের বিল';
    if (selectedBillDate == 14) return '১৪ তারিখের বিল';
    if (selectedBillDate == 21) return '২১ তারিখের বিল';
    return 'সকল ইউজার';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Digital 24 Online Billing',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
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
            const Text(
              'Seroil Colony, 4 No. Road, Ghoramara, Chandrima Rajshahi-6100',
              textAlign: TextAlign.center,
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
                    onSelected: (_) => showAllUsers(),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('৭ তারিখ'),
                    selected: selectedBillDate == 7,
                    onSelected: (_) => selectBillDate(7),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('১৪ তারিখ'),
                    selected: selectedBillDate == 14,
                    onSelected: (_) => selectBillDate(14),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('২১ তারিখ'),
                    selected: selectedBillDate == 21,
                    onSelected: (_) => selectBillDate(21),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),

            const SizedBox(height: 10),

            Text(
              reportTitle,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _summaryCard(
                    'ইউজার',
                    '${customers.length} জন',
                    Icons.people,
                  ),
                  _summaryCard(
                    'মোট বিল',
                    '${totalBill.toStringAsFixed(0)} ৳',
                    Icons.receipt_long,
                  ),
                  _summaryCard(
                    'পরিশোধ',
                    '${totalPaid.toStringAsFixed(0)} ৳',
                    Icons.payments,
                  ),
                  _summaryCard(
                    'বকেয়া',
                    '${totalDue.toStringAsFixed(0)} ৳',
                    Icons.pending_actions,
                  ),
                ],
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
                            'কোনো ইউজার নেই\n\n'
                            'নিচের “ইউজার যোগ” বাটনে চাপুন',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(
                            bottom: 90,
                          ),
                          itemCount: customers.length,
                          itemBuilder: (context, index) {
                            final customer = customers[index];

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text('${index + 1}'),
                                ),
                                title: Text(
                                  '${customer.userId} - '
                                  '${customer.name}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  'মোবাইল: ${customer.mobile}\n'
                                  'প্যাকেজ: ${customer.packageName}\n'
                                  'বিল ডেট: ${customer.billDate} তারিখ\n'
                                  'বিল: '
                                  '${customer.bill.toStringAsFixed(0)} টাকা\n'
                                  'পরিশোধ: '
                                  '${customer.paid.toStringAsFixed(0)} টাকা\n'
                                  'বকেয়া: '
                                  '${customer.due.toStringAsFixed(0)} টাকা',
                                ),
                                isThreeLine: true,
                                trailing: SizedBox(
                                  width: 55,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints:
                                            const BoxConstraints(),
 
