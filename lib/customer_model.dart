class Customer {
  int? id;

  String userId;
  String name;
  String mobile;
  String packageName;

  int billDate;
  double billAmount;
  double paidAmount;

  String paymentDate;
  bool active;

  Customer({
    this.id,
    required this.userId,
    required this.name,
    required this.mobile,
    required this.packageName,
    required this.billDate,
    required this.billAmount,
    required this.paidAmount,
    required this.paymentDate,
    this.active = true,
  });

  double get dueAmount => billAmount - paidAmount;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'mobile': mobile,
      'package_name': packageName,
      'bill_date': billDate,
      'bill_amount': billAmount,
      'paid_amount': paidAmount,
      'payment_date': paymentDate,
      'active': active ? 1 : 0,
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'],
      userId: map['user_id'] ?? '',
      name: map['name'] ?? '',
      mobile: map['mobile'] ?? '',
      packageName: map['package_name'] ?? '',
      billDate: map['bill_date'] ?? 7,
      billAmount: (map['bill_amount'] ?? 0).toDouble(),
      paidAmount: (map['paid_amount'] ?? 0).toDouble(),
      paymentDate: map['payment_date'] ?? '',
      active: (map['active'] ?? 1) == 1,
