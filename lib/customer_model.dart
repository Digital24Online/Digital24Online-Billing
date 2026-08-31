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
