import 'package:flutter/material.dart';

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
  String userId;
  String name;
  String mobile;
  String packageName;
  double bill;
  double paid;
  String billDate;
  String paymentDate;
  bool active;

  Customer({
    required this.userId,
    required this.name,
    required this.mobile,
    required this.packageName,
    required this.bill,
    required this.paid,
    required this.billDate,
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
  final List<Customer> customers = [];

  double get totalBill =>
      customers.fold(0, (sum, customer) => sum + customer.bill);

  double get totalPaid =>
      customers.fold(0, (sum, customer) => sum + customer.paid);

  double get totalDue =>
      customers.fold(0, (sum, customer) => sum + customer.due);

  void addCustomer() {
    final userId = TextEditingController();
    final name = TextEditingController();
    final mobile = TextEditingController();
    final packageName = TextEditingController();
    final bill = TextEditingController();
    final paid = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        final isDesktop = MediaQuery.of(context).size.width >= 700;

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
              onPressed: () => Navigator.pop(context),
              child: const Text('বাতিল'),
            ),
            FilledButton(
              onPressed: () {
                if (userId.text.trim().isEmpty ||
                    name.text.trim().isEmpty) {
                  return;
                }

                final today = DateTime.now()
                    .toLocal()
                    .toString()
                    .split(' ')
                    .first;

                final paidAmount = double.tryParse(paid.text) ?? 0;

                setState(() {
                  customers.add(
                    Customer(
                      userId: userId.text.trim(),
                      name: name.text.trim(),
                      mobile: mobile.text.trim(),
                      packageName: packageName.text.trim(),
                      bill: double.tryParse(bill.text) ?? 0,
                      paid: paidAmount,
                      billDate: today,
                      paymentDate: paidAmount > 0 ? today : '',
                    ),
                  );
                });

                Navigator.pop(context);
              },
              child: const Text('সংরক্ষণ'),
            ),
          ],
        );
      },
    );
  }

  void toggleCustomer(int index) {
    setState(() {
      customers[index].active = !customers[index].active;
    });
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

                const SizedBox(height: 20),

                isDesktop
                    ? Row(
                        children: [
                          Expanded(
                            child: _summaryCard(
                              'মোট বিল',
                              totalBill,
                              Icons.receipt_long,
                            ),
                          ),
                          Expanded(
                            child: _summaryCard(
                              'পরিশোধ',
                              totalPaid,
                              Icons.payments,
                            ),
                          ),
                          Expanded(
                            child: _summaryCard(
                              'বকেয়া',
                              totalDue,
                              Icons.pending_actions,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: _summaryCard(
                              'মোট বিল',
                              totalBill,
                              Icons.receipt_long,
                            ),
                          ),
                          Expanded(
                            child: _summaryCard(
                              'পরিশোধ',
                              totalPaid,
                              Icons.payments,
                            ),
                          ),
                          Expanded(
                            child: _summaryCard(
                              'বকেয়া',
                              totalDue,
                              Icons.pending_actions,
                            ),
                          ),
                        ],
                      ),

                const SizedBox(height: 12),

                Expanded(
                  child: customers.isEmpty
                      ? const Center(
                          child: Text(
                            'কোনো ইউজার নেই\n\nনিচের “ইউজার যোগ” বাটনে চাপুন',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16),
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

  Widget _summaryCard(
    String title,
    double amount,
    IconData icon,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 8,
        ),
        child: Column(
          children: [
            Icon(icon, size: 26),
            const SizedBox(height: 5),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '${amount.toStringAsFixed(0)} ৳',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}