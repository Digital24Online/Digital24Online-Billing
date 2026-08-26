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
        return AlertDialog(
          title: const Text('নতুন ইউজার যোগ করুন'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: userId,
                  decoration:
                      const InputDecoration(labelText: 'ইউজার আইডি নাম্বার'),
                ),
                TextField(
                  controller: name,
                  decoration:
                      const InputDecoration(labelText: 'ইউজার আইডি ও নাম'),
                ),
                TextField(
                  controller: mobile,
                  keyboardType: TextInputType.phone,
                  decoration:
                      const InputDecoration(labelText: 'মোবাইল নাম্বার'),
                ),
                TextField(
                  controller: packageName,
                  decoration:
                      const InputDecoration(labelText: 'প্যাকেজ'),
                ),
                TextField(
                  controller: bill,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'টাকা'),
                ),
                TextField(
                  controller: paid,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'পরিশোধ'),
                ),
              ],
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

                setState(() {
                  customers.add(
                    Customer(
                      userId: userId.text.trim(),
                      name: name.text.trim(),
                      mobile: mobile.text.trim(),
                      packageName: packageName.text.trim(),
                      bill: double.tryParse(bill.text) ?? 0,
                      paid: double.tryParse(paid.text) ?? 0,
                      billDate: DateTime.now()
                          .toLocal()
                          .toString()
                          .split(' ')
                          .first,
                      paymentDate: double.tryParse(paid.text) != null &&
                              (double.tryParse(paid.text) ?? 0) > 0
                          ? DateTime.now()
                              .toLocal()
                              .toString()
                              .split(' ')
                              .first
                          : '',
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
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: const Column(
              children: [
                Text(
                  'Digital 24 Online',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Seroil Colony, 4 No. Road, Ghoramara, Chandrima Rajshahi-6100',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13),
                ),
                SizedBox(height: 4),
                Text(
                  'বিলিং নাম: Digital 24 Online Billing',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _summaryCard('মোট বিল', totalBill),
                _summaryCard('পরিশোধ', totalPaid),
                _summaryCard('বকেয়া', totalDue),
              ],
            ),
          ),

          const SizedBox(height: 10),

          Expanded(
            child: customers.isEmpty
                ? const Center(
                    child: Text(
                      'কোনো ইউজার নেই\n\nনিচের “ইউজার যোগ” বাটনে চাপুন',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: customers.length,
                    itemBuilder: (context, index) {
                      final customer = customers[index];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
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
                  ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(String title, double amount) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 12,
            horizontal: 4,
          ),
          child: Column(
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                '${amount.toStringAsFixed(0)} ৳',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
