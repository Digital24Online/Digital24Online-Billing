import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'database_helper.dart';

class MasterReportCenter extends StatefulWidget {
  final DatabaseHelper db;
  final bool english;
  const MasterReportCenter({super.key, required this.db, required this.english});

  @override
  State<MasterReportCenter> createState() => _MasterReportCenterState();
}

class _MasterReportCenterState extends State<MasterReportCenter> {
  DateTime from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime to = DateTime.now();
  String month = DateFormat('yyyy-MM').format(DateTime.now());
  int? billDate;
  int? staffId;
  String type = 'total_bill';
  bool busy = false;
  List<Map<String, dynamic>> rows = [];
  List<Map<String, dynamic>> staff = [];
  Map<String, dynamic> totals = {};

  String t(String b, String e) => widget.english ? e : b;
  String money(num v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);

  final types = const [
    'total_bill', 'total_collection', 'total_due', 'daily_collection',
    'monthly_collection', 'staff_collection', 'due', 'customer',
    'billing_7', 'billing_14', 'billing_21', 'active', 'closed',
  ];

  String label(String k) => switch (k) {
    'total_bill' => t('Total Bill', 'Total Bill'),
    'total_collection' => t('Total Collection', 'Total Collection'),
    'total_due' => t('Total Due', 'Total Due'),
    'daily_collection' => t('Daily Collection', 'Daily Collection'),
    'monthly_collection' => t('Monthly Collection', 'Monthly Collection'),
    'staff_collection' => t('Staff Collection', 'Staff Collection'),
    'due' => t('Due Report', 'Due Report'),
    'customer' => t('Customer Report', 'Customer Report'),
    'billing_7' => t('৭ তারিখের Billing Report', '7th Billing Report'),
    'billing_14' => t('১৪ তারিখের Billing Report', '14th Billing Report'),
    'billing_21' => t('২১ তারিখের Billing Report', '21st Billing Report'),
    'active' => t('Active Customer Report', 'Active Customer Report'),
    'closed' => t('Closed Customer Report', 'Closed Customer Report'),
    _ => k,
  };

  @override
  void initState() {
    super.initState();
    loadStaff();
  }

  Future<void> loadStaff() async {
    staff = await widget.db.getStaff();
    if (mounted) setState(() {});
  }

  Future<void> pickDate(bool isFrom) async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: isFrom ? from : to,
    );
    if (d != null) setState(() => isFrom ? from = d : to = d);
  }

  Future<void> pickMonth() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: DateTime.tryParse('$month-01') ?? DateTime.now(),
      helpText: t('মাস নির্বাচন করুন', 'Select month'),
    );
    if (d != null) setState(() => month = DateFormat('yyyy-MM').format(d));
  }

  Future<void> run() async {
    setState(() => busy = true);
    try {
      final db = await widget.db.database;
      final a = DateFormat('yyyy-MM-dd').format(from);
      final b = DateFormat('yyyy-MM-dd').format(to);
      late List<Map<String, dynamic>> r;
      switch (type) {
        case 'total_bill':
          r = await db.rawQuery('''SELECT c.user_id,c.name,c.mobile,c.package_name,c.bill_date,b.billing_month,b.amount,
            COALESCE((SELECT SUM(p.amount) FROM payments p WHERE p.bill_id=b.id),0) paid,
            b.amount-COALESCE((SELECT SUM(p.amount) FROM payments p WHERE p.bill_id=b.id),0) due
            FROM bills b JOIN customers c ON c.id=b.customer_id WHERE b.billing_month=? ORDER BY c.user_id''', [month]);
          break;
        case 'total_collection':
        case 'daily_collection':
        case 'monthly_collection':
        case 'staff_collection':
          final staffWhere = staffId == null ? '' : ' AND p.staff_id=?';
          final args = <dynamic>[];
          String dateWhere;
          if (type == 'monthly_collection' || type == 'staff_collection') {
            final first = DateTime.parse('$month-01');
            final last = DateTime(first.year, first.month + 1, 0);
            dateWhere = "date(p.payment_date) BETWEEN date(?) AND date(?)";
            args.addAll([DateFormat('yyyy-MM-dd').format(first), DateFormat('yyyy-MM-dd').format(last)]);
          } else {
            dateWhere = 'date(p.payment_date) BETWEEN date(?) AND date(?)';
            args.addAll([a, b]);
          }
          if (staffId != null) args.add(staffId);
          r = await db.rawQuery('''SELECT p.payment_date,c.user_id,c.name,p.amount,p.receipt_no,COALESCE(s.name,'') staff_name
            FROM payments p JOIN customers c ON c.id=p.customer_id LEFT JOIN staff s ON s.id=p.staff_id
            WHERE $dateWhere $staffWhere ORDER BY p.payment_date DESC,p.id DESC''', args);
          break;
        case 'total_due':
        case 'due':
          r = await db.rawQuery('''SELECT c.user_id,c.name,c.mobile,c.package_name,b.billing_month,b.amount,
            COALESCE((SELECT SUM(p.amount) FROM payments p WHERE p.bill_id=b.id),0) paid,
            MAX(0,b.amount-COALESCE((SELECT SUM(p.amount) FROM payments p WHERE p.bill_id=b.id),0)) due
            FROM bills b JOIN customers c ON c.id=b.customer_id
            WHERE b.billing_month=? AND (b.amount-COALESCE((SELECT SUM(p.amount) FROM payments p WHERE p.bill_id=b.id),0))>0
            ORDER BY due DESC,c.user_id''', [month]);
          break;
        case 'customer':
        case 'active':
        case 'closed':
          final status = type == 'active' ? 'WHERE c.active=1' : type == 'closed' ? 'WHERE c.active=0' : '';
          r = await db.rawQuery('''SELECT c.user_id,c.name,c.mobile,c.package_name,c.bill_date,c.amount,c.paid_amount,c.due_amount,
            CASE WHEN c.active=1 THEN 'Active' ELSE 'Closed' END status,c.payment_date FROM customers c $status ORDER BY c.user_id''');
          break;
        case 'billing_7':
        case 'billing_14':
        case 'billing_21':
          final d = int.parse(type.split('_').last);
          r = await db.rawQuery('''SELECT c.user_id,c.name,c.mobile,c.package_name,c.bill_date,b.billing_month,b.amount,
            COALESCE((SELECT SUM(p.amount) FROM payments p WHERE p.bill_id=b.id),0) paid,
            MAX(0,b.amount-COALESCE((SELECT SUM(p.amount) FROM payments p WHERE p.bill_id=b.id),0)) due
            FROM bills b JOIN customers c ON c.id=b.customer_id WHERE c.bill_date=? AND b.billing_month=? ORDER BY c.user_id''', [d, month]);
          break;
        default:
          r = [];
      }
      rows = r;
      final bill = rows.fold<double>(0, (s, x) => s + ((x['amount'] ?? 0) as num).toDouble());
      final paid = rows.fold<double>(0, (s, x) => s + ((x['paid'] ?? x['amount'] ?? 0) as num).toDouble());
      final due = rows.fold<double>(0, (s, x) => s + ((x['due'] ?? 0) as num).toDouble());
      final collection = rows.fold<double>(0, (s, x) => s + ((x['amount'] ?? 0) as num).toDouble());
      totals = {'bill': bill, 'paid': paid, 'due': due, 'collection': type.contains('collection') ? collection : paid};
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Uint8List> buildPdf() async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        pw.Text('Digital 24 Online', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Text('Internet Service Provider'),
        pw.Text('Seroil Colony, 4 No. Road, Ghoramara, Chandrima Rajshahi-6100'),
        pw.SizedBox(height: 10),
        pw.Text(label(type), style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.Text('Period: $month'),
        pw.SizedBox(height: 10),
        pw.Table.fromTextArray(
          headers: ['User ID','Name','Package','Bill','Paid/Amount','Due/Staff'],
          data: rows.map((r) => [
            '${r['user_id'] ?? ''}', '${r['name'] ?? ''}', '${r['package_name'] ?? ''}',
            money((r['amount'] ?? 0) as num),
            money((r['paid'] ?? r['amount'] ?? 0) as num),
            '${r['due'] ?? r['staff_name'] ?? ''}',
          ]).toList(),
          cellStyle: const pw.TextStyle(fontSize: 7),
          headerStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.Text('Total Bill: BDT ${money((totals['bill'] ?? 0) as num)}'),
        pw.Text('Total Collection: BDT ${money((totals['collection'] ?? 0) as num)}'),
        pw.Text('Total Due: BDT ${money((totals['due'] ?? 0) as num)}'),
        pw.SizedBox(height: 8),
        pw.Text('Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 8)),
      ],
    ));
    return Uint8List.fromList(await doc.save());
  }

  Future<void> pdf(bool print) async {
    if (rows.isEmpty) {
      await run();
      if (rows.isEmpty) return;
    }
    final bytes = await buildPdf();
    if (print) {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'Digital24Online-${type}_$month.pdf');
      return;
    }
    final name = 'Digital24Online_${type}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
    final saved = await FilePicker.platform.saveFile(dialogTitle: 'Save PDF Report', fileName: name, type: FileType.custom, allowedExtensions: ['pdf'], bytes: bytes);
    if (saved != null && !Platform.isAndroid) {
      final f = File(saved);
      if (!await f.exists() || await f.length() == 0) await f.writeAsBytes(bytes, flush: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('পূর্ণাঙ্গ Reports', 'Master Reports')),
      content: SizedBox(width: 900, height: 600, child: Column(children: [
        DropdownButtonFormField<String>(value: type, decoration: InputDecoration(labelText: t('Report নির্বাচন', 'Report type')), items: types.map((x) => DropdownMenuItem(value: x, child: Text(label(x)))).toList(), onChanged: (v) => setState(() => type = v ?? type)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => pickDate(true), child: Text(DateFormat('yyyy-MM-dd').format(from)))),
          const SizedBox(width: 6),
          Expanded(child: OutlinedButton(onPressed: () => pickDate(false), child: Text(DateFormat('yyyy-MM-dd').format(to)))),
          const SizedBox(width: 6),
          Expanded(child: OutlinedButton(onPressed: pickMonth, child: Text(month))),
          const SizedBox(width: 6),
          Expanded(child: DropdownButtonFormField<int?>(value: staffId, decoration: InputDecoration(labelText: t('স্টাফ','Staff')), items: [DropdownMenuItem<int?>(value: null, child: Text(t('সব স্টাফ','All Staff'))), ...staff.map((s) => DropdownMenuItem<int?>(value: (s['id'] as num).toInt(), child: Text('${s['name']}')))], onChanged: (v) => setState(() => staffId = v))),
        ]),
        const SizedBox(height: 8),
        Row(children: [Expanded(child: FilledButton.icon(onPressed: busy ? null : run, icon: const Icon(Icons.refresh), label: Text(t('Report তৈরি','Generate')))), const SizedBox(width: 6), Expanded(child: OutlinedButton.icon(onPressed: rows.isEmpty ? null : () => pdf(false), icon: const Icon(Icons.picture_as_pdf), label: const Text('PDF'))), const SizedBox(width: 6), Expanded(child: OutlinedButton.icon(onPressed: rows.isEmpty ? null : () => pdf(true), icon: const Icon(Icons.print), label: Text(t('Print','Print'))))]),
        if (busy) const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [Text('Bill: ${money((totals['bill'] ?? 0) as num)} ৳'), Text('Collection: ${money((totals['collection'] ?? 0) as num)} ৳'), Text('Due: ${money((totals['due'] ?? 0) as num)} ৳'), Text('Rows: ${rows.length}')]),
        const SizedBox(height: 8),
        Expanded(child: rows.isEmpty ? Center(child: Text(t('Report তৈরি করুন','Generate a report'))) : ListView.builder(itemCount: rows.length, itemBuilder: (_, i) { final r=rows[i]; return ListTile(dense:true, title: Text('${r['user_id'] ?? ''} - ${r['name'] ?? ''}'), subtitle: Text('${r['package_name'] ?? ''} • ${r['payment_date'] ?? r['billing_month'] ?? ''} • ${r['staff_name'] ?? ''}'), trailing: Text('${money((r['amount'] ?? r['due'] ?? 0) as num)} ৳')); })),
      ])),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(t('বন্ধ','Close')))],
    );
  }
}

