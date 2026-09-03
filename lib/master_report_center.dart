import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
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
  int? staffId;
  String period = 'monthly';
  int? billDate;
  bool busy = false;
  List<Map<String, dynamic>> staff = [];
  List<Map<String, dynamic>> collected = [];
  List<Map<String, dynamic>> due = [];
  List<Map<String, dynamic>> closed = [];
  Map<String, dynamic> totals = {};

  String t(String b, String e) => widget.english ? e : b;
  String money(num v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);
  String dateText(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  @override
  void initState() {
    super.initState();
    loadStaff();
  }

  Future<void> loadStaff() async {
    try {
      final r = await widget.db.getStaff();
      if (!mounted) return;
      setState(() => staff = r);
    } catch (e) {
      if (mounted) _error('$e');
    }
  }

  void _error(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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

  Future<void> pickDate(bool isFrom) async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: isFrom ? from : to,
    );
    if (d == null) return;
    setState(() {
      if (isFrom) {
        from = d;
        if (to.isBefore(from)) to = from;
      } else {
        to = d;
        if (to.isBefore(from)) from = to;
      }
    });
  }

  Future<void> runStaffReport() async {
    if (staffId == null) {
      _error(t('আগে একজন স্টাফ নির্বাচন করুন', 'Select a staff first'));
      return;
    }
    setState(() => busy = true);
    try {
      final database = await widget.db.database;
      late String start;
      late String end;
      if (period == 'monthly' || period == '7' || period == '14' || period == '21') {
        final first = DateTime.parse('$month-01');
        final last = DateTime(first.year, first.month + 1, 0);
        start = dateText(first);
        end = dateText(last);
        if (period != 'monthly') billDate = int.parse(period);
      } else {
        start = dateText(from);
        end = dateText(to);
      }

      // A collection belongs to a staff through payments.staff_id.
      // Grouping is by customer, so multiple payments from the same customer
      // never inflate the customer count.
      final billDateCondition = billDate == null ? '' : ' AND c.bill_date=?';
      final rows = await database.rawQuery('''
        SELECT
          c.id AS customer_id,
          c.user_id,
          c.name,
          c.mobile,
          c.package_name,
          c.bill_date,
          c.active,
          b.billing_month,
          COALESCE(b.amount, c.amount, 0) AS bill_amount,
          COALESCE((SELECT SUM(p2.amount) FROM payments p2 WHERE p2.bill_id=b.id), 0) AS bill_paid,
          COALESCE((SELECT SUM(p3.amount) FROM payments p3
            WHERE p3.billing_id=? AND p3.customer_id=c.id AND p3.staff_id=?
              AND date(p3.payment_date) BETWEEN date(?) AND date(?)), 0) AS staff_collection,
          MAX(CASE WHEN p.billing_id=? AND p.staff_id=? THEN p.payment_date ELSE NULL END) AS last_staff_payment_date
        FROM customers c
        LEFT JOIN bills b ON b.customer_id=c.id AND b.billing_id=? AND b.billing_month=?
        LEFT JOIN payments p ON p.customer_id=c.id
        WHERE c.billing_id=? AND EXISTS (
          SELECT 1 FROM payments ps
          WHERE ps.billing_id=? AND ps.customer_id=c.id AND ps.staff_id=?
            AND date(ps.payment_date) BETWEEN date(?) AND date(?)
        )
        $billDateCondition
        GROUP BY c.id, c.user_id, c.name, c.mobile, c.package_name, c.bill_date, c.active,
                 b.billing_month, b.amount, c.amount
        ORDER BY c.user_id COLLATE NOCASE
      ''', [staffId, start, end, widget.db.activeBillingId, staffId, widget.db.activeBillingId, month, widget.db.activeBillingId, staffId, start, end, if (billDate != null) billDate]);

      final collectedRows = <Map<String, dynamic>>[];
      final dueRows = <Map<String, dynamic>>[];
      final closedRows = <Map<String, dynamic>>[];

      for (final raw in rows) {
        final r = Map<String, dynamic>.from(raw);
        final bill = ((r['bill_amount'] ?? 0) as num).toDouble();
        final paid = ((r['bill_paid'] ?? 0) as num).toDouble();
        final staffAmount = ((r['staff_collection'] ?? 0) as num).toDouble();
        r['bill_amount'] = bill;
        r['bill_paid'] = paid;
        r['due_amount'] = (bill - paid).clamp(0, double.infinity).toDouble();
        r['staff_collection'] = staffAmount;
        if ((r['active'] ?? 1) == 0) closedRows.add(r);
        if (staffAmount > 0) collectedRows.add(r);
        if (r['due_amount'] > 0) dueRows.add(r);
      }

      final billTotal = rows.fold<double>(0, (s, r) => s + ((r['bill_amount'] ?? 0) as num).toDouble());
      final collectionTotal = rows.fold<double>(0, (s, r) => s + ((r['staff_collection'] ?? 0) as num).toDouble());
      final dueTotal = dueRows.fold<double>(0, (s, r) => s + ((r['due_amount'] ?? 0) as num).toDouble());
      totals = {
        'users': rows.length,
        'bill': billTotal,
        'collection': collectionTotal,
        'due': dueTotal,
        'collected_users': collectedRows.length,
        'due_users': dueRows.length,
        'closed_users': closedRows.length,
      };
      if (!mounted) return;
      setState(() {
        collected = collectedRows;
        due = dueRows;
        closed = closedRows;
        busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        _error('${t('স্টাফ রিপোর্ট তৈরি করতে সমস্যা: ', 'Staff report error: ')}$e');
      }
    }
  }

  String get selectedBillingName {
    return '';
  }

  Future<String> currentBillingName() async {
    final rows = await widget.db.getBillings();
    for (final r in rows) {
      if ((r['id'] as num?)?.toInt() == widget.db.activeBillingId) return '${r['name'] ?? ''}';
    }
    return 'Billing';
  }

  String get selectedStaffName {
    for (final s in staff) {
      if ((s['id'] as num?)?.toInt() == staffId) return '${s['name'] ?? ''}';
    }
    return '';
  }

  String get periodLabel {
    if (period == 'monthly') return '${t('মাসিক', 'Monthly')} $month';
    if (period == '7' || period == '14' || period == '21') {
      return '${period}${t(' তারিখের বিল', 'th Bill Date')} — $month';
    }
    return '${dateText(from)} → ${dateText(to)}';
  }

  Future<Uint8List> buildPdf() async {
    final billingName = await currentBillingName();
    final logoData = await rootBundle.load('assets/logo.png');
    final logo = pw.MemoryImage(logoData.buffer.asUint8List());
    final doc = pw.Document();
    final watermark = pw.Opacity(
      opacity: 0.07,
      child: pw.Center(child: pw.Image(logo, width: 260, height: 260)),
    );

    pw.Widget summaryBox() => pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
      child: pw.Wrap(
        spacing: 18,
        runSpacing: 6,
        children: [
          pw.Text('Total Users: ${totals['users'] ?? 0}'),
          pw.Text('Total Bill: BDT ${money((totals['bill'] ?? 0) as num)}'),
          pw.Text('Staff Collection: BDT ${money((totals['collection'] ?? 0) as num)}'),
          pw.Text('Total Due: BDT ${money((totals['due'] ?? 0) as num)}'),
          pw.Text('Collected Users: ${totals['collected_users'] ?? 0}'),
          pw.Text('Due Users: ${totals['due_users'] ?? 0}'),
          pw.Text('Closed Users: ${totals['closed_users'] ?? 0}'),
        ],
      ),
    );

    pw.Widget table(String title, List<Map<String, dynamic>> data, {required bool collection}) {
      return pw.Stack(children: [
        watermark,
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 5),
          if (data.isEmpty) pw.Text('No records') else pw.Table.fromTextArray(
            headers: ['User ID', 'Name', 'Mobile', 'Bill Date', 'Package', collection ? 'Collection' : 'Due', 'Status'],
            data: data.map((r) => [
              '${r['user_id'] ?? ''}', '${r['name'] ?? ''}', '${r['mobile'] ?? ''}', '${r['bill_date'] ?? ''}',
              '${r['package_name'] ?? ''}', money((collection ? r['staff_collection'] : r['due_amount']) as num),
              (r['active'] ?? 1) == 1 ? 'Active' : 'Closed',
            ]).toList(),
            cellStyle: const pw.TextStyle(fontSize: 6.5),
            headerStyle: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
        ]),
      ]);
    }

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => [
        pw.Stack(children: [
          watermark,
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Row(children: [pw.Image(logo, width: 34, height: 34), pw.SizedBox(width: 8), pw.Text('Digital 24 Online', style: pw.TextStyle(fontSize: 21, fontWeight: pw.FontWeight.bold))]),
            pw.Text('Seroil Colony, 4 No. Road, Ghoramara, Chandrima Rajshahi-6100'),
            pw.SizedBox(height: 8),
            pw.Text('BILLING: $billingName', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.Text('STAFF COLLECTION REPORT — $selectedStaffName', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
            pw.Text('Period: $periodLabel'),
            pw.SizedBox(height: 10),
            summaryBox(),
            pw.SizedBox(height: 12),
            table('Collected Users (${collected.length})', collected, collection: true),
            table('Due Users (${due.length})', due, collection: false),
            table('Closed Users (${closed.length})', closed, collection: false),
            pw.Text('Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 7)),
          ]),
        ]),
      ],
    ));
    return Uint8List.fromList(await doc.save());
  }

  Future<void> exportPdf({required bool print}) async {
    if (staffId == null) {
      _error(t('স্টাফ নির্বাচন করুন', 'Select a staff'));
      return;
    }
    if (collected.isEmpty && due.isEmpty && closed.isEmpty) await runStaffReport();
    if (collected.isEmpty && due.isEmpty && closed.isEmpty) return;
    final bytes = await buildPdf();
    final safeName = selectedStaffName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
    final filename = 'Digital24Online_Staff_${safeName}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
    if (print) {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: filename);
      return;
    }
    await FilePicker.platform.saveFile(
      dialogTitle: t('Staff Report সংরক্ষণ', 'Save Staff Report'),
      fileName: filename,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      bytes: bytes,
    );
  }

  Widget section(String title, List<Map<String, dynamic>> rows, {required bool collection}) {
    return ExpansionTile(
      initiallyExpanded: true,
      title: Text('$title (${rows.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
      children: rows.isEmpty
          ? [Padding(padding: const EdgeInsets.all(12), child: Text(t('কোনো তথ্য নেই', 'No records')))]
          : rows.map((r) => ListTile(
              dense: true,
              title: Text('${r['user_id'] ?? ''} — ${r['name'] ?? ''}'),
              subtitle: Text('${r['mobile'] ?? ''} • ${r['package_name'] ?? ''} • Bill Date: ${r['bill_date'] ?? ''} • ${(r['active'] ?? 1) == 1 ? 'Active' : 'Closed'}'),
              trailing: Text('${money((collection ? r['staff_collection'] : r['due_amount']) as num)} ৳'),
            )).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('স্টাফ Collection Report', 'Staff Collection Report')),
      content: SizedBox(
        width: 900,
        height: 650,
        child: Column(children: [
          Row(children: [
            Expanded(child: DropdownButtonFormField<int>(
              value: staffId,
              decoration: InputDecoration(labelText: t('স্টাফ নির্বাচন', 'Select Staff')),
              items: staff.map((s) => DropdownMenuItem<int>(value: (s['id'] as num).toInt(), child: Text('${s['name'] ?? ''}'))).toList(),
              onChanged: (v) => setState(() => staffId = v),
            )),
            const SizedBox(width: 8),
            Expanded(child: DropdownButtonFormField<String>(
              value: period,
              decoration: InputDecoration(labelText: t('রিপোর্ট সময়', 'Report Period')),
              items: [
                DropdownMenuItem(value: '7', child: Text(t('৭ তারিখের বিল', '7th Bill Date'))),
                DropdownMenuItem(value: '14', child: Text(t('১৪ তারিখের বিল', '14th Bill Date'))),
                DropdownMenuItem(value: '21', child: Text(t('২১ তারিখের বিল', '21st Bill Date'))),
                DropdownMenuItem(value: 'monthly', child: Text(t('মাসিক ৩০/৩১ দিন', 'Full Month'))),
                DropdownMenuItem(value: 'custom', child: Text(t('নির্দিষ্ট তারিখ', 'Custom Date Range'))),
              ],
              onChanged: (v) => setState(() { period = v ?? period; billDate = (period == '7' || period == '14' || period == '21') ? int.parse(period) : null; }),
            )),
          ]),
          const SizedBox(height: 8),
          if (period == 'monthly' || period == '7' || period == '14' || period == '21')
            SizedBox(width: double.infinity, child: OutlinedButton(onPressed: pickMonth, child: Text('${t('মাস', 'Month')}: $month')))
          else
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => pickDate(true), child: Text(dateText(from)))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: () => pickDate(false), child: Text(dateText(to)))),
            ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: busy ? null : runStaffReport, icon: const Icon(Icons.assessment), label: Text(t('রিপোর্ট তৈরি', 'Generate Report')))),
            const SizedBox(width: 6),
            Expanded(child: OutlinedButton.icon(onPressed: busy ? null : () => exportPdf(print: false), icon: const Icon(Icons.picture_as_pdf), label: Text(t('PDF / Download', 'PDF / Download')))),
            const SizedBox(width: 6),
            Expanded(child: OutlinedButton.icon(onPressed: busy ? null : () => exportPdf(print: true), icon: const Icon(Icons.print), label: Text(t('Print', 'Print')))),
          ]),
          if (busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
          if (totals.isNotEmpty) Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Wrap(spacing: 12, runSpacing: 6, children: [
              Text('${t('মোট ইউজার', 'Users')}: ${totals['users'] ?? 0}'),
              Text('${t('বিল', 'Bill')}: ${money((totals['bill'] ?? 0) as num)} ৳'),
              Text('${t('কালেকশন', 'Collection')}: ${money((totals['collection'] ?? 0) as num)} ৳'),
              Text('${t('বকেয়া', 'Due')}: ${money((totals['due'] ?? 0) as num)} ৳'),
              Text('${t('কালেকশন হয়েছে', 'Collected')}: ${totals['collected_users'] ?? 0}'),
              Text('${t('বকেয়া', 'Due Users')}: ${totals['due_users'] ?? 0}'),
              Text('${t('বন্ধ', 'Closed')}: ${totals['closed_users'] ?? 0}'),
            ]),
          ),
          Expanded(child: ListView(children: [
            section(t('কালেকশন হয়েছে', 'Collected Users'), collected, collection: true),
            section(t('বকেয়া আছে', 'Due Users'), due, collection: false),
            section(t('বন্ধ ইউজার', 'Closed Users'), closed, collection: false),
          ])),
        ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(t('বন্ধ', 'Close')))],
    );
  }
}
