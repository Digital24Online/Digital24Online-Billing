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

  int get totalUsers => customers.length;

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

    final loadedCustomers = data.map((item) {
      final bill = (item['amount'] as num?)?.toDouble() ?? 0;
      final paid = (item['paid_amount'] as num?)?.toDouble() ?? 0;

      return Customer(
        id: item['id'] as int?,
        userId: item['user_id']?.toString() ?? '',
        name: item['name']?.toString() ?? '',
        mobile: item['mobile']?.toString() ?? '',
        packageName: item['package_name']?.toString() ?? '',
        billDate: int.tryParse(item['bill_date']?.toString() ?? '') ?? 7,
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
        ..addAll(loadedCustomers);
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
        final isDesktop =
            MediaQuery.of(dialogContext).size.width >= 700;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('নতুন ইউজার যোগ করুন'),
              content: SizedBox(
                width: isDesktop ? 500 : double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
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
                          labelText: 'পরিশোধ',
                        ),
                      ),
                    ],
                  ),
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

                    final today = DateTime.now()
                        .toLocal()
                        .toString()
                        .split(' ')
                        .first;

                    final customerData = {
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
                    };

                    await db.addCustomer(customerData);

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

  String billDateTitle() {
    if (selectedBillDate == 7) return '৭ তারিখের বিল ডেট';
    if (selectedBillDate == 14) return '১৪ তারিখের বিল ডেট';
    if (selectedBillDate == 21) return '২১ তারিখের বিল ডেট';
    return 'সকল ইউজার';
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 900;

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

      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isDesktop ? 1400 : double.infinity,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 24 : 8,
            ),
            child: Column(
              children: [
                const SizedBox(height: 16),

                const Text(
                  'Digital 24 Online',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 5),

                const Text(
                  'Seroil Colony, 4 No. Road, Ghoramara, Chandrima Rajshahi-6100',
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 5),

                const Text(
                  'বিলিং নাম: Digital 24 Online Billing',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 18),

                _billDateButtons(),

                const SizedBox(height: 10),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Text(
                          billDateTitle(),
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 10),

                        Row(
                          children: [
                            Expanded(
                              child: _reportCard(
                                'ইউজার',
                                '$totalUsers জন',
                                Icons.people,
                              ),
                            ),
                            Expanded(
                              child: _reportCard(
                                'বিল',
                                '${totalBill.toStringAsFixed(0)} ৳',
                                Icons.receipt_long,
                              ),
                            ),
                            Expanded(
                              child: _reportCard(
                                'পরিশোধ',
                                '${totalPaid.toStringAsFixed(0)} ৳',
                                Icons.payments,
                              ),
                            ),
                            Expanded(
                              child: _reportCard(
                                'বকেয়া',
                                '${totalDue.toStringAsFixed(0)} ৳',
                                Icons.pending_actions,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                Expanded(
                  child: loading
                      ? const Center(
                          child: CircularProgressIndicator(),
                        )
                      : customers.isEmpty
                          ? Center(
                              child: Text(
                                selectedBillDate == 0
                                    ? 'কোনো ইউজার নেই'
                                    : '$selectedBillDate তারিখের কোনো ইউজার নেই',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 17,
                                ),
                              ),
                            )
                          : isDesktop
                              ? _desktopCustomerTable()
                              : _mobileCustomerList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _billDateButtons() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
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
        ],
      ),
    );
  }

  Widget _reportCard(
    String title,
    String value,
    IconData icon,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 10,
          horizontal: 4,
        ),
        child: Column(
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 3),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileCustomerList() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 90),
      itemCount: customers.length,
      itemBuilder: (context, index) {
        final customer = customers[index];

        return Card(
          margin: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 5,
          ),
          child: ListTile(
            leading: CircleAvatar(
              child: Text('${index + 1}'),
            ),

            title: Text(
              '${customer.userId} - ${customer.name}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),

            subtitle: Text(
              'মোবাইল: ${customer.mobile}\n'
              'প্যাকেজ: ${customer.packageName}\n'
              'বিল ডেট: ${customer.billDate} তারিখ\n'
              'বিল: ${customer.bill.toStringAsFixed(0)} টাকা | '
              'পরিশোধ: ${customer.paid.toStringAsFixed(0)} টাকা | '
              'বকেয়া: ${customer.due.toStringAsFixed(0)} টাকা',
            ),

            isThreeLine: true,

            trailing: Switch(
              value: customer.active,
              onChanged: (_) => toggleCustomer(index),
            ),
          ),
        );
      },
    );
  }

  Widget _desktopCustomerTable() {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            columns: const [
              DataColumn(label: Text('ক্রমিক')),
              DataColumn(label: Text('ইউজার আইডি')),
              DataColumn(label: Text('নাম')),
              DataColumn(label: Text('মোবাইল')),
              DataColumn(label: Text('প্যাকেজ')),
              DataColumn(label: Text('বিল ডেট')),
              DataColumn(label: Text('বিল')),
              DataColumn(label: Text('পরিশোধ')),
              DataColumn(label: Text('বকেয়া')),
              DataColumn(label: Text('স্ট্যাটাস')),
            ],

            rows: customers.asMap().entries.map((entry) {
              final index = entry.key;
              final customer = entry.value;

              return DataRow(
                cells: [
                  DataCell(Text('${index + 1}')),
                  DataCell(Text(customer.userId)),
                  DataCell(Text(customer.name)),
                  DataCell(Text(customer.mobile)),
                  DataCell(Text(customer.packageName)),
                  DataCell(Text('${customer.billDate} তারিখ')),
                  DataCell(
                    Text(
                      '${customer.bill.toStringAsFixed(0)} ৳',
                    ),
                  ),
                  DataCell(
                    Text(
                      '${customer.paid.toStringAsFixed(0)} ৳',
                    ),
                  ),
                  DataCell(
                    Text(
                      '${customer.due.toStringAsFixed(0)} ৳',
                    ),
                  ),
                  DataCell(
                    Switch(
                      value: customer.active,
                      onChanged: (_) => toggleCustomer(index),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
