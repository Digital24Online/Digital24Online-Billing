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
      ),
      home: const BillingHomePage(),
    );
  }
}

class Customer {
  final int? id;
  final String userId;
  final String name;
  final String mobile;
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

class BillingHomePage extends StatefulWidget {
  const BillingHomePage({super.key});

  @override
  State<BillingHomePage> createState() =>
      _BillingHomePageState();
}

class _BillingHomePageState
    extends State<BillingHomePage> {
  final DatabaseHelper db =
      DatabaseHelper.instance;

  final List<Customer> customers = [];

  int selectedBillDate = 0;
  bool loading = true;
  String searchText = '';

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

  int get totalUsers {
    return customers.length;
  }

  int get activeUsers {
    return customers
        .where((customer) => customer.active)
        .length;
  }

  int get closedUsers {
    return customers
        .where((customer) => !customer.active)
        .length;
  }

  String get reportTitle {
    if (selectedBillDate == 0) {
      return 'সকল ইউজারের হিসাব';
    }

    return '${banglaNumber(selectedBillDate)} তারিখের হিসাব';
  }

  List<Customer> get filteredCustomers {
    final query = searchText.trim().toLowerCase();

    if (query.isEmpty) {
      return customers;
    }

    return customers.where((customer) {
      return customer.userId
              .toLowerCase()
              .contains(query) ||
          customer.name
              .toLowerCase()
              .contains(query) ||
          customer.mobile
              .toLowerCase()
              .contains(query) ||
          customer.packageName
              .toLowerCase()
              .contains(query);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    loadCustomers();
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

  String money(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(2);
  }

  String banglaNumber(int number) {
    const english = '0123456789';
    const bangla = '০১২৩৪৫৬৭৮৯';

    return number.toString().split('').map((char) {
      final index = english.indexOf(char);
      return index >= 0
          ? bangla[index]
          : char;
    }).join();
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
          : await db.getCustomersByBillDate(
              selectedBillDate,
            );

      final list = data.map((item) {
        final bill =
            (item['amount'] as num?)
                    ?.toDouble() ??
                0;

        final paid =
            (item['paid_amount'] as num?)
                    ?.toDouble() ??
                0;

        return Customer(
          id: item['id'] as int?,
          userId:
              item['user_id']?.toString() ?? '',
          name:
              item['name']?.toString() ?? '',
          mobile:
              item['mobile']?.toString() ?? '',
          packageName:
              item['package_name']?.toString() ??
                  '',
          billDate: int.tryParse(
                item['bill_date']
                        ?.toString() ??
                    '',
              ) ??
              7,
          bill: bill,
          paid: paid,
          paymentDate:
              item['payment_date']
                      ?.toString() ??
                  '',
          active:
              (item['active'] ?? 1) == 1,
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

  Future<bool> userIdExists(
    String userId,
  ) async {
    final existing =
        await db.getCustomerByUserId(
      userId.trim(),
    );

    return existing != null;
  }
    Future<void> addCustomer() async {
    final userIdController =
        TextEditingController();
    final nameController =
        TextEditingController();
    final mobileController =
        TextEditingController();
    final packageController =
        TextEditingController();
    final billController =
        TextEditingController();
    final paidController =
        TextEditingController();

    int selectedDate = 7;
    bool saving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'নতুন ইউজার যোগ করুন',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller:
                          userIdController,
                      textInputAction:
                          TextInputAction.next,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'ইউজার আইডি নাম্বার *',
                        prefixIcon:
                            Icon(Icons.badge),
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller:
                          nameController,
                      textInputAction:
                          TextInputAction.next,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'ইউজারের নাম *',
                        prefixIcon:
                            Icon(Icons.person),
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller:
                          mobileController,
                      keyboardType:
                          TextInputType.phone,
                      textInputAction:
                          TextInputAction.next,
                      decoration:
                          const InputDecoration(
                        labelText: 'মোবাইল নাম্বার',
                        prefixIcon:
                            Icon(Icons.phone),
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller:
                          packageController,
                      textInputAction:
                          TextInputAction.next,
                      decoration:
                          const InputDecoration(
                        labelText: 'প্যাকেজ',
                        prefixIcon:
                            Icon(Icons.speed),
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: selectedDate,
                      decoration:
                          const InputDecoration(
                        labelText: 'বিল ডেট',
                        prefixIcon:
                            Icon(Icons.calendar_month),
                        border:
                            OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 7,
                          child:
                              Text('৭ তারিখ'),
                        ),
                        DropdownMenuItem(
                          value: 14,
                          child:
                              Text('১৪ তারিখ'),
                        ),
                        DropdownMenuItem(
                          value: 21,
                          child:
                              Text('২১ তারিখ'),
                        ),
                      ],
                      onChanged: saving
                          ? null
                          : (value) {
                              if (value != null) {
                                setDialogState(() {
                                  selectedDate =
                                      value;
                                });
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller:
                          billController,
                      keyboardType:
                          const TextInputType
                              .numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction:
                          TextInputAction.next,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'মাসিক বিলের টাকা *',
                        prefixIcon:
                            Icon(Icons.receipt),
                        suffixText: '৳',
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller:
                          paidController,
                      keyboardType:
                          const TextInputType
                              .numberWithOptions(
                        decimal: true,
                      ),
                      decoration:
                          const InputDecoration(
                        labelText:
                            'প্রাথমিক পরিশোধ',
                        prefixIcon:
                            Icon(Icons.payments),
                        suffixText: '৳',
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () {
                          Navigator.pop(
                            dialogContext,
                          );
                        },
                  child:
                      const Text('বাতিল'),
                ),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final userId =
                              userIdController
                                  .text
                                  .trim();
                          final name =
                              nameController
                                  .text
                                  .trim();

                          if (userId.isEmpty ||
                              name.isEmpty) {
                            ScaffoldMessenger
                                .of(context)
                                .showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'ইউজার আইডি ও নাম লিখুন',
                                ),
                              ),
                            );
                            return;
                          }

                          final billAmount =
                              double.tryParse(
                                    billController
                                        .text
                                        .trim(),
                                  ) ??
                                  0;

                          final paidAmount =
                              double.tryParse(
                                    paidController
                                        .text
                                        .trim(),
                                  ) ??
                                  0;

                          if (billAmount <= 0) {
                            ScaffoldMessenger
                                .of(context)
                                .showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'সঠিক বিলের টাকা লিখুন',
                                ),
                              ),
                            );
                            return;
                          }

                          if (paidAmount < 0) {
                            ScaffoldMessenger
                                .of(context)
                                .showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'সঠিক পরিশোধের টাকা লিখুন',
                                ),
                              ),
                            );
                            return;
                          }

                          if (paidAmount >
                              billAmount) {
                            ScaffoldMessenger
                                .of(context)
                                .showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'পরিশোধের টাকা বিলের চেয়ে বেশি হতে পারবে না',
                                ),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            saving = true;
                          });

                          try {
                            final exists =
                                await userIdExists(
                              userId,
                            );

                            if (exists) {
                              if (dialogContext
                                  .mounted) {
                                setDialogState(() {
                                  saving = false;
                                });
                              }

                              if (context.mounted) {
                                ScaffoldMessenger
                                    .of(context)
                                    .showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'এই ইউজার আইডি ইতোমধ্যে আছে',
                                    ),
                                  ),
                                );
                              }

                              return;
                            }

                            final today =
                                todayDate();

                            final customerId =
                                await db.addCustomer({
                              'user_id': userId,
                              'name': name,
                              'mobile':
                                  mobileController
                                      .text
                                      .trim(),
                              'package_name':
                                  packageController
                                      .text
                                      .trim(),
                              'bill_date':
                                  selectedDate,
                              'amount':
                                  billAmount,
                              'total_amount':
                                  billAmount,
                              'paid_amount':
                                  paidAmount,
                              'due_amount':
                                  billAmount -
                                      paidAmount,
                              'payment_date':
                                  paidAmount > 0
                                      ? today
                                      : '',
                              'active': 1,
                            });

                            if (paidAmount > 0) {
                              await db.addPayment({
                                'customer_id':
                                    customerId,
                                'user_id': userId,
                                'amount':
                                    paidAmount,
                                'payment_date':
                                    today,
                                'note':
                                    'প্রাথমিক পরিশোধ',
                              });
                            }

                            if (!dialogContext
                                .mounted) {
                              return;
                            }

                            Navigator.pop(
                              dialogContext,
                            );

                            await loadCustomers();

                            if (!mounted) return;

                            ScaffoldMessenger
                                .of(context)
                                .showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'ইউজার সফলভাবে সংরক্ষণ হয়েছে',
                                ),
                              ),
                            );
                          } catch (e) {
                            if (dialogContext
                                .mounted) {
                              setDialogState(() {
                                saving = false;
                              });
                            }

                            if (!context.mounted) {
                              return;
                            }

                            ScaffoldMessenger
                                .of(context)
                                .showSnackBar(
                              SnackBar(
                                content: Text(
                                  'ইউজার সংরক্ষণে সমস্যা হয়েছে: $e',
                                ),
                              ),
                            );
                          }
                        },
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.save,
                        ),
                  label: const Text(
                    'সংরক্ষণ',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    userIdController.dispose();
    nameController.dispose();
    mobileController.dispose();
    packageController.dispose();
    billController.dispose();
    paidController.dispose();
  }



  Widget _paymentInfoRow(
    String title,
    String value,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  Future<void> editCustomer(int index) async {
    final customer = customers[index];

    if (customer.id == null) return;

    final userIdController =
        TextEditingController(text: customer.userId);
    final nameController =
        TextEditingController(text: customer.name);
    final mobileController =
        TextEditingController(text: customer.mobile);
    final packageController =
        TextEditingController(text: customer.packageName);
    final billController =
        TextEditingController(
      text: money(customer.bill),
    );

    int selectedDate = customer.billDate;
    bool saving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'ইউজার তথ্য পরিবর্তন',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: userIdController,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'ইউজার আইডি *',
                        prefixIcon:
                            Icon(Icons.badge),
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameController,
                                            enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'ইউজারের নাম *',
                        prefixIcon:
                            Icon(Icons.person),
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: mobileController,
                      enabled: !saving,
                      keyboardType:
                          TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'মোবাইল নাম্বার',
                        prefixIcon:
                            Icon(Icons.phone),
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: packageController,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'প্যাকেজ',
                        prefixIcon:
                            Icon(Icons.speed),
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: selectedDate,
                      decoration:
                          const InputDecoration(
                        labelText: 'বিল ডেট',
                        prefixIcon:
                            Icon(Icons.calendar_month),
                        border:
                            OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 7,
                          child:
                              Text('৭ তারিখ'),
                        ),
                        DropdownMenuItem(
                          value: 14,
                          child:
                              Text('১৪ তারিখ'),
                        ),
                        DropdownMenuItem(
                          value: 21,
                          child:
                              Text('২১ তারিখ'),
                        ),
                      ],
                      onChanged: saving
                          ? null
                          : (value) {
                              if (value != null) {
                                                                setDialogState(() {
                                  selectedDate =
                                      value;
                                });
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: billController,
                      enabled: !saving,
                      keyboardType:
                          const TextInputType
                              .numberWithOptions(
                        decimal: true,
                      ),
                      decoration:
                          const InputDecoration(
                        labelText:
                            'মাসিক বিল *',
                        prefixIcon:
                            Icon(Icons.receipt),
                        suffixText: '৳',
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding:
                          const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(
                          10,
                        ),
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      child: Text(
                        'বর্তমান পরিশোধ: '
                        '${money(customer.paid)} ৳\n'
                        'বর্তমান বকেয়া: '
                        '${money(customer.due)} ৳\n\n'
                        'পেমেন্ট পরিবর্তন করতে '
                        '“পেমেন্ট গ্রহণ” ব্যবহার করুন।',
                        style: const TextStyle(
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () {
                          Navigator.pop(
                            dialogContext,
                          );
                        },
                  child:
                      const Text('বাতিল'),
                ),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final userId =
                              userIdController
                                                              .text
                                  .trim();
                          final name =
                              nameController
                                  .text
                                  .trim();

                          if (userId.isEmpty ||
                              name.isEmpty) {
                            ScaffoldMessenger
                                .of(context)
                                .showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'ইউজার আইডি ও নাম লিখুন',
                                ),
                              ),
                            );
                            return;
                          }

                          final billAmount =
                              double.tryParse(
                                    billController
                                        .text
                                        .trim(),
                                  ) ??
                                  0;

                          if (billAmount <= 0) {
                            ScaffoldMessenger
                                .of(context)
                                .showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'সঠিক বিলের টাকা লিখুন',
                                ),
                              ),
                            );
                            return;
                          }

                          if (customer.paid >
                              billAmount) {
                            ScaffoldMessenger
                                .of(context)
                                .showSnackBar(
                              SnackBar(
                                content: Text(
                                  'নতুন বিল বর্তমান পরিশোধের '
                                  'টাকার চেয়ে কম হতে পারবে না। '
                                  'পরিশোধ: ${money(customer.paid)} ৳',
                                ),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            saving = true;
                          });

                          try {
                            final other =
                                await db
                                    .getCustomerByUserId(
                              userId,
                            );

                            if (other != null &&
                                other['id'] !=
                                    customer.id) {
                              if (dialogContext
                                  .mounted) {
                                setDialogState(() {
                                  saving = false;
                                });
                              }
                              
                              if (context.mounted) {
                                ScaffoldMessenger
                                    .of(context)
                                    .showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'এই ইউজার আইডি অন্য একজন ব্যবহার করছে',
                                    ),
                                  ),
                                );
                              }

                              return;
                            }

                            final newDue =
                                billAmount -
                                    customer.paid;

                            await db.updateCustomer(
                              customer.id!,
                              {
                                'user_id': userId,
                                'name': name,
                                'mobile':
                                    mobileController
                                        .text
                                        .trim(),
                                'package_name':
                                    packageController
                                        .text
                                        .trim(),
                                'bill_date':
                                    selectedDate,
                                'amount':
                                    billAmount,
                                'total_amount':
                                    billAmount,
                                'due_amount':
                                    newDue,
                              },
                            );

                            if (!dialogContext
                                .mounted) {
                              return;
                            }

                            Navigator.pop(
                              dialogContext,
                            );

                            await loadCustomers();

                            if (!mounted) return;

                            ScaffoldMessenger
                                .of(context)
                                .showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'ইউজারের তথ্য সফলভাবে পরিবর্তন হয়েছে',
                                ),
                              ),
                            );
                          } catch (e) {
                            if (dialogContext
                                .mounted) {
                              setDialogState(() {
                                saving = false;
                              });
                            }

                            if (!context.mounted) {
                              return;
                            }

                            ScaffoldMessenger
                                .of(context)
                                .showSnackBar(
                              SnackBar(
                                content: Text(
                                  'তথ্য পরিবর্তনে সমস্যা হয়েছে: $e',
                                ),
                              ),
                            );
                          }
                        },
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: const Text(
                    'সংরক্ষণ',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    userIdController.dispose();
    nameController.dispose();
    mobileController.dispose();
    packageController.dispose();
    billController.dispose();
  }

  Future<void> toggleCustomer(
    int index,
  ) async {
    final customer = customers[index];

    if (customer.id == null) return;

    final newStatus = !customer.active;

    try {
      await db.updateCustomerStatus(
        customer.id!,
        newStatus,
      );

      if (!mounted) return;

      setState(() {
        customer.active = newStatus;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            newStatus
                ? 'ইউজার Active করা হয়েছে'
                : 'ইউজার Closed করা হয়েছে',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'স্ট্যাটাস পরিবর্তন করা যায়নি: $e',
          ),
        ),
      );
    }
  }

  Future<void> deleteCustomer(
    int index,
  ) async {
    final customer = customers[index];

    if (customer.id == null) return;

    final confirm =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
                    title: const Text(
            'ইউজার মুছে ফেলবেন?',
          ),
          content: Text(
            '${customer.userId} - ${customer.name}\n\n'
            'এই ইউজারের তথ্য এবং সংশ্লিষ্ট '
            'পেমেন্ট/বিল হিস্ট্রি মুছে যাবে।\n\n'
            'এই কাজটি পরে ফিরিয়ে আনা যাবে না।',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child:
                  const Text('বাতিল'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child:
                  const Text('মুছে ফেলুন'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      await db.deleteCustomer(
        customer.id!,
      );

      if (!mounted) return;

      await loadCustomers();

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'ইউজার মুছে ফেলা হয়েছে',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'ইউজার মুছতে সমস্যা হয়েছে: $e',
          ),
        ),
      );
    }
  }

  Future<void> selectBillDate(
    int date,
  ) async {
    if (selectedBillDate == date) return;

    setState(() {
      selectedBillDate = date;
      searchText = '';
    });

    await loadCustomers();
  }

  Future<void> showAllUsers() async {
    if (selectedBillDate == 0) return;

    setState(() {
      selectedBillDate = 0;
      searchText = '';
    });

    await loadCustomers();
  }
    Future<void> showCustomerDetails(
    Customer customer,
  ) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'ইউজারের বিস্তারিত তথ্য',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
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
                  '${banglaNumber(customer.billDate)} তারিখ',
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
      padding:
          const EdgeInsets.symmetric(
        vertical: 5,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
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
  
  Future<void> showPaymentHistory(
    Customer customer,
  ) async {
    if (customer.id == null) return;

    try {
      final payments =
          await db.getPaymentHistory(
        customer.id!,
      );

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(
              'পেমেন্ট হিস্ট্রি\n'
              '${customer.userId} - ${customer.name}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 420,
              child: payments.isEmpty
                  ? const Center(
                      child: Text(
                        'এখনও কোনো পেমেন্ট হিস্ট্রি নেই',
                      ),
                    )
                  : ListView.separated(
                      itemCount:
                          payments.length,
                      separatorBuilder:
                          (context, index) =>
                              const Divider(
                        height: 1,
                      ),
                      itemBuilder:
                          (context, index) {
                        final payment =
                            payments[index];

                        final amount =
                            (payment['amount']
                                        as num?)
                                    ?.toDouble() ??
                                0;

                        final date =
                            payment['payment_date']
                                    ?.toString() ??
                                '';

                        final note =
                            payment['note']
                                    ?.toString() ??
                                '';

                        return ListTile(
                          contentPadding:
                              EdgeInsets.zero,
                          leading:
                              const CircleAvatar(
                            child: Icon(
                              Icons.payments,
                            ),
                          ),
                          title: Text(
                            '${money(amount)} ৳',
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            'তারিখ: $date'
                            '${note.isNotEmpty ? '\n$note' : ''}',
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                  );
                },
                child:
                    const Text('বন্ধ করুন'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
                    content: Text(
            'পেমেন্ট হিস্ট্রি দেখাতে সমস্যা হয়েছে: $e',
          ),
        ),
      );
    }
  }

  Future<void> showDashboardDetails() async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'হিসাবের সারসংক্ষেপ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dashboardRow(
                  'মোট ইউজার',
                  '${banglaNumber(totalUsers)} জন',
                  Icons.people,
                ),
                _dashboardRow(
                  'Active ইউজার',
                  '${banglaNumber(activeUsers)} জন',
                  Icons.wifi,
                ),
                _dashboardRow(
                  'Closed ইউজার',
                  '${banglaNumber(closedUsers)} জন',
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
                Navigator.pop(
                  dialogContext,
                );
              },
              child:
                  const Text('বন্ধ করুন'),
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
      padding:
          const EdgeInsets.symmetric(
        vertical: 7,
      ),
      child: Row(
        children: [
          Icon(icon, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> showTodayPayments() async {
    final today = todayDate();

    try {
      final payments =
          await db.getPaymentsByDate(
        today,
      );

      final summary =
          await db.getPaymentSummary(
        today,
      );

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(
              'আজকের পেমেন্ট\n$today',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 430,
              child: payments.isEmpty
                  ? const Center(
                      child: Text(
                        'আজ কোনো পেমেন্ট গ্রহণ করা হয়নি',
                        textAlign:
                            TextAlign.center,
                      ),
                    )
                  : Column(
                      children: [
                        Container(
                          width:
                              double.infinity,
                          padding:
                              const EdgeInsets.all(
                            14,
                          ),
                          decoration:
                              BoxDecoration(
                            borderRadius:
                                BorderRadius
                                    .circular(
                              12,
                            ),
                            color: Theme.of(
                              context,
                            )
                                .colorScheme
                                .primaryContainer,
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'আজ মোট কালেকশন',
                                style:
                                    TextStyle(
                                  fontWeight:
                                      FontWeight
                                          .w500,
                                ),
                              ),
                              const SizedBox(
                                height: 5,
                              ),
                              Text(
                                '${money(summary['total'] ?? 0)} ৳',
                                style:
                                    const TextStyle(
                                  fontSize: 24,
                                  fontWeight:
                                      FontWeight
                                          .bold,
                                ),
                              ),
                              const SizedBox(
                                height: 3,
                              ),
                              Text(
                                '${(summary['payment_count'] ?? 0).toInt()} টি পেমেন্ট',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(
                          height: 10,
                        ),
                        Expanded(
                          child:
                              ListView.separated(
                            itemCount:
                                payments.length,
                            separatorBuilder:
                                (context,
                                        index) =>
                                    const Divider(
                              height: 1,
                            ),
                            itemBuilder:
                                (context,
                                    index) {
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
                                contentPadding:
                                    EdgeInsets.zero,
                                leading:
                                    const CircleAvatar(
                                  child: Icon(
                                    Icons.payments,
                                  ),
                                ),
                                title: Text(
                                  userId,
                                  style:
                                      const TextStyle(
                                    fontWeight:
                                        FontWeight
                                            .bold,
                                  ),
                                ),
                                trailing: Text(
                                  '${money(amount)} ৳',
                                  style:
                                      const TextStyle(
                                    fontWeight:
                                        FontWeight
                                            .bold,
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
                  Navigator.pop(
                    dialogContext,
                  );
                },
                child:
                    const Text('বন্ধ করুন'),
              ),
            ],
          );
        },
      );
        } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'আজকের পেমেন্ট দেখাতে সমস্যা হয়েছে: $e',
          ),
        ),
      );
    }
  }
    Future<void> backupData() async {
    try {
      final path = await db.backupDatabase();

      if (!mounted) return;

      if (path == null || path.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backup বাতিল করা হয়েছে'),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Backup সফলভাবে সংরক্ষণ হয়েছে\n$path',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
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

  Future<void> restoreData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Backup Restore করবেন?',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'Restore করলে বর্তমানে অ্যাপে থাকা '
            'ইউজার, বিল এবং পেমেন্টের তথ্য '
            'Backup ফাইলের তথ্য দিয়ে প্রতিস্থাপিত হবে।\n\n'
            'Restore করার আগে বর্তমান ডেটার একটি Backup '
            'রাখা ভালো।\n\n'
            'আপনি কি নিশ্চিত?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text('বাতিল'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
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

  Future<void> showBackupMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(
              bottom: 15,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  leading: Icon(
                    Icons.storage,
                  ),
                  title: Text(
                    'ডেটা Backup ও Restore',
                    style: TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    'অ্যাপের গুরুত্বপূর্ণ তথ্য নিরাপদে সংরক্ষণ করুন',
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.backup,
                  ),
                  title: const Text(
                    'Backup তৈরি করুন',
                  ),
                  subtitle: const Text(
                    'ইউজার, পেমেন্ট ও বিলের তথ্য সংরক্ষণ',
                  ),
                  onTap: () async {
                    Navigator.pop(
                      sheetContext,
                    );
                    await backupData();
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.restore,
                  ),
                  title: const Text(
                    'Backup Restore করুন',
                  ),
                  subtitle: const Text(
                    'আগের Backup থেকে তথ্য ফিরিয়ে আনুন',
                  ),
                  onTap: () async {
                    Navigator.pop(
                      sheetContext,
                    );
                    await restoreData();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> showSearchDialog() async {
    final controller = TextEditingController(
      text: searchText,
    );

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'ইউজার খুঁজুন',
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText:
                  'আইডি, নাম বা মোবাইল লিখুন',
              prefixIcon:
                  Icon(Icons.search),
              border:
                  OutlineInputBorder(),
            ),
            onChanged: (value) {
              setState(() {
                searchText = value;
              });
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  searchText = '';
                });

                Navigator.pop(
                  dialogContext,
                                  );
              },
              child:
                  const Text('পরিষ্কার'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  searchText =
                      controller.text.trim();
                });

                Navigator.pop(
                  dialogContext,
                );
              },
              child:
                  const Text('খুঁজুন'),
            ),
          ],
        );
      },
    );

    controller.dispose();
  }

  Future<void> takePayment(
    int index,
  ) async {
    final customer = customers[index];

    if (customer.id == null) return;

    if (customer.due <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
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

    final noteController =
        TextEditingController();

    bool saving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'পেমেন্ট গ্রহণ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              content:
                  SingleChildScrollView(
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    Text(
                      '${customer.userId} - ${customer.name}',
                      textAlign:
                          TextAlign.center,
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(
                      height: 15,
                    ),
                    Container(
                      width:
                          double.infinity,
                      padding:
                          const EdgeInsets.all(
                        12,
                      ),
                      decoration:
                          BoxDecoration(
                        borderRadius:
                            BorderRadius
                                .circular(
                          10,
                        ),
                        color: Theme.of(
                          context,
                        )
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                                            child: Column(
                        children: [
                          Text(
                            'মোট বিল: '
                            '${money(customer.bill)} টাকা',
                          ),
                          const SizedBox(
                            height: 4,
                          ),
                          Text(
                            'ইতোমধ্যে পরিশোধ: '
                            '${money(customer.paid)} টাকা',
                          ),
                          const SizedBox(
                            height: 4,
                          ),
                          Text(
                            'বর্তমান বকেয়া: '
                            '${money(customer.due)} টাকা',
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(
                      height: 15,
                    ),
                    TextField(
                      controller:
                          paymentController,
                      enabled: !saving,
                      autofocus: true,
                      keyboardType:
                          const TextInputType
                              .numberWithOptions(
                        decimal: true,
                      ),
                      decoration:
                          const InputDecoration(
                        labelText:
                            'আজ কত টাকা পরিশোধ করেছে? *',
                        prefixIcon:
                            Icon(
                          Icons.payments,
                        ),
                        suffixText: '৳',
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    TextField(
                      controller:
                          noteController,
                      enabled: !saving,
                      maxLines: 2,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'নোট (ঐচ্ছিক)',
                        prefixIcon:
                            Icon(
                          Icons.note,
                        ),
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () {
                          Navigator.pop(
                            dialogContext,
                          );
                        },
                  child:
                      const Text('বাতিল'),
                ),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final payment =
                              double.tryParse(
                                    paymentController
                                        .text
                                        .trim(),
                                  ) ??
                                  0;

                          if (payment <= 0) {
                            ScaffoldMessenger
                                .of(context)
                                .showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'সঠিক পরিমাণ টাকা লিখুন',
                                ),
                              ),
                            );
                            return;
                          }

                          if (payment >
                              customer.due) {
                            ScaffoldMessenger
                                                              .of(context)
                                .showSnackBar(
                              SnackBar(
                                content: Text(
                                  'সর্বোচ্চ '
                                  '${money(customer.due)} '
                                  'টাকা নেওয়া যাবে',
                                ),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            saving = true;
                          });

                          try {
                            final newPaid =
                                customer.paid +
                                    payment;

                            final newDue =
                                customer.bill -
                                    newPaid;

                            final today =
                                todayDate();

                            await db.updateCustomer(
                              customer.id!,
                              {
                                'paid_amount':
                                    newPaid,
                                'due_amount':
                                    newDue,
                                'payment_date':
                                    today,
                              },
                            );

                            await db.addPayment(
                              {
                                'customer_id':
                                    customer.id!,
                                'user_id':
                                    customer
                                        .userId,
                                'amount':
                                    payment,
                                'payment_date':
                                    today,
                                'note':
                                    noteController
                                        .text
                                        .trim()
                                        .isEmpty
                                    ? 'Customer Payment'
                                    : noteController
                                        .text
                                        .trim(),
                                'created_at':
                                    DateTime
                                        .now()
                                        .toIso8601String(),
                              },
                            );

                            if (!dialogContext
                                .mounted) {
                              return;
                            }

                            Navigator.pop(
                              dialogContext,
                            );

                            await loadCustomers();

                            if (!mounted) return;

                            ScaffoldMessenger
                                .of(context)
                                .showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${money(payment)} টাকা '
                                  'পেমেন্ট গ্রহণ করা হয়েছে',
                                ),
                              ),
                            );
                          } catch (e) {
                            if (dialogContext
                                                                .mounted) {
                              setDialogState(() {
                                saving =
                                    false;
                              });
                            }

                            if (!context.mounted) {
                              return;
                            }

                            ScaffoldMessenger
                                .of(context)
                                .showSnackBar(
                              SnackBar(
                                content: Text(
                                  'পেমেন্ট সংরক্ষণে সমস্যা হয়েছে: $e',
                                ),
                              ),
                            );
                          }
                        },
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.save,
                        ),
                  label: const Text(
                    'পেমেন্ট সংরক্ষণ',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    paymentController.dispose();
    noteController.dispose();
  }
    Widget customerCard(
    Customer customer,
    int index,
  ) {
    final isDue = customer.due > 0;

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showCustomerDetails(customer),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    child: Text(
                      customer.userId.isEmpty
                          ? '?'
                          : customer.userId
                              .substring(
                                0,
                                customer.userId.length > 1
                                    ? 1
                                    : customer.userId.length,
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
                          customer.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ID: ${customer.userId}',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .primary,
                            fontWeight:
                                FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                                    PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'details') {
                        await showCustomerDetails(
                          customer,
                        );
                      } else if (value == 'edit') {
                        await editCustomer(index);
                      } else if (value == 'history') {
                        await showPaymentHistory(
                          customer,
                        );
                      } else if (value == 'status') {
                        await toggleCustomer(index);
                      } else if (value == 'delete') {
                        await deleteCustomer(index);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'details',
                        child: ListTile(
                          contentPadding:
                              EdgeInsets.zero,
                          leading:
                              Icon(Icons.info_outline),
                          title:
                              Text('বিস্তারিত'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          contentPadding:
                              EdgeInsets.zero,
                          leading:
                              Icon(Icons.edit),
                          title:
                              Text('তথ্য পরিবর্তন'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'history',
                        child: ListTile(
                          contentPadding:
                              EdgeInsets.zero,
                          leading:
                              Icon(Icons.history),
                          title:
                              Text('পেমেন্ট হিস্ট্রি'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'status',
                        child: ListTile(
                          contentPadding:
                              EdgeInsets.zero,
                          leading: Icon(
                            customer.active
                                ? Icons.wifi_off
                                : Icons.wifi,
                          ),
                          title: Text(
                            customer.active
                                ? 'Closed করুন'
                                : 'Active করুন',
                          ),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          contentPadding:
                              EdgeInsets.zero,
                          leading: Icon(
                            Icons.delete_outline,
                          ),
                          title:
                              Text('ইউজার মুছে ফেলুন'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _infoChip(
                    Icons.phone,
                    customer.mobile.isEmpty
                        ? 'মোবাইল নেই'
                        : customer.mobile,
                  ),
                  _infoChip(
                    Icons.speed,
                    customer.packageName.isEmpty
                        ? 'প্যাকেজ নেই'
                        : customer.packageName,
                  ),
                  _infoChip(
                    Icons.calendar_month,
                    'বিল ডেট: '
                    '${banglaNumber(customer.billDate)}',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                                children: [
                  Expanded(
                    child: _amountBox(
                      'বিল',
                      customer.bill,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: _amountBox(
                      'পরিশোধ',
                      customer.paid,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: _amountBox(
                      'বকেয়া',
                      customer.due,
                      isDue: isDue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      customer.active
                          ? '● Active'
                          : '● Closed',
                      style: TextStyle(
                        fontWeight:
                            FontWeight.bold,
                        color: customer.active
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                  ),
                  if (isDue)
                    FilledButton.icon(
                      onPressed: () =>
                          takePayment(index),
                      icon: const Icon(
                        Icons.payments,
                        size: 18,
                      ),
                      label: const Text(
                        'পেমেন্ট',
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () =>
                          showPaymentHistory(
                        customer,
                      ),
                      icon: const Icon(
                        Icons.history,
                        size: 18,
                      ),
                      label: const Text(
                        'হিস্ট্রি',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip(
    IconData icon,
    String text,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
          ),
                    const SizedBox(width: 5),
          Text(text),
        ],
      ),
    );
  }

  Widget _amountBox(
    String title,
    double amount, {
    bool isDue = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(10),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${money(amount)} ৳',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: isDue
                  ? Colors.red
                  : null,
            ),
          ),
        ],
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
      margin: const EdgeInsets.symmetric(
        horizontal: 5,
      ),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            child: Icon(icon, size: 20),
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
                  style: const TextStyle(
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight:
                        FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
    Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Digital 24 Online Billing',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'ইউজার খুঁজুন',
            onPressed: showSearchDialog,
            icon: const Icon(
              Icons.search,
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'dashboard') {
                await showDashboardDetails();
              } else if (value == 'today') {
                await showTodayPayments();
              } else if (value == 'backup') {
                await showBackupMenu();
              } else if (value == 'refresh') {
                await loadCustomers();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'dashboard',
                child: ListTile(
                  contentPadding:
                      EdgeInsets.zero,
                  leading: Icon(
                    Icons.dashboard,
                  ),
                  title:
                      Text('সারসংক্ষেপ'),
                ),
              ),
              PopupMenuItem(
                value: 'today',
                child: ListTile(
                  contentPadding:
                      EdgeInsets.zero,
                  leading: Icon(
                    Icons.today,
                  ),
                  title:
                      Text('আজকের পেমেন্ট'),
                ),
              ),
              PopupMenuItem(
                value: 'backup',
                child: ListTile(
                  contentPadding:
                      EdgeInsets.zero,
                  leading: Icon(
                    Icons.backup,
                  ),
                  title:
                      Text('Backup / Restore'),
                ),
              ),
              PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  contentPadding:
                      EdgeInsets.zero,
                  leading: Icon(
                    Icons.refresh,
                  ),
                  title:
                      Text('Refresh'),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton:
          FloatingActionButton.extended(
        onPressed: addCustomer,
        icon: const Icon(
          Icons.person_add,
        ),
        label: const Text(
          'ইউজার যোগ',
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),
            const Text(
              'Digital 24 Online',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            const Padding(
              padding:
                  EdgeInsets.symmetric(
                horizontal: 12,
              ),
              child: Text(
                'Seroil Colony, 4 No. Road, '
                'Ghoramara, Chandrima '
                'Rajshahi-6100',
                textAlign:
                    TextAlign.center,
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 10,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text(
                        'সকল',
                      ),
                      selected:
                          selectedBillDate ==
                              0,
                      onSelected: (_) {
                        showAllUsers();
                      },
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text(
                        '৭ তারিখ',
                      ),
                      selected:
                          selectedBillDate ==
                              7,
                      onSelected: (_) {
                        selectBillDate(7);
                      },
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text(
                        '১৪ তারিখ',
                      ),
                      selected:
                          selectedBillDate ==
                              14,
                      onSelected: (_) {
                        selectBillDate(14);
                      },
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text(
                        '২১ তারিখ',
                      ),
                      selected:
                          selectedBillDate ==
                              21,
                      onSelected: (_) {
                        selectBillDate(21);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Text(
              reportTitle,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (searchText.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.only(
                  top: 4,
                ),
                child: Text(
                  'খোঁজা হচ্ছে: "$searchText"'
                  '  •  ${banglaNumber(filteredCustomers.length)} জন',
                  style: const TextStyle(
                    fontSize: 13,
                  ),
                ),
              ),
            const SizedBox(height: 7),
            SizedBox(
              height: 100,
              child:
                  SingleChildScrollView(
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
            const SizedBox(height: 5),
            Expanded(
              child: loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(),
                    )
                  : filteredCustomers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize:
                                MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons
                                    .person_search,
                                size: 55,
                              ),
                              const SizedBox(
                                height: 10,
                              ),
                              Text(
                                searchText
                                        .isEmpty
                                    ? 'কোনো ইউজার পাওয়া যায়নি'
                                    : 'কোনো ইউজার পাওয়া যায়নি',
                              ),
                              if (searchText
                                  .isNotEmpty)
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      searchText =
                                          '';
                                    });
                                  },
                                  child:
                                      const Text(
                                    'সার্চ পরিষ্কার করুন',
                                  ),
                                ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh:
                              loadCustomers,
                          child:
                              ListView.builder(
                            padding:
                                const EdgeInsets
                                    .only(
                              bottom: 100,
                            ),
                            itemCount:
                                filteredCustomers
                                    .length,
                            itemBuilder:
                                (context,
                                    index) {
                              return customerCard(
                                filteredCustomers[
                                    index],
                                customers.indexOf(
                                  filteredCustomers[
                                      index],
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
}
