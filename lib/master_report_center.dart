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
      _error(
        t(
          'আগে একজন স্টাফ নির্বাচন করুন',
          'Select a staff first',
        ),
      );
      return;
    }

    setState(() => busy = true);

    try {
      final database =
          await widget.db.database;

      late String start;
      late String end;

      if (period == 'monthly' ||
          period == '7' ||
          period == '14' ||
          period == '21') {
        final first =
            DateTime.parse('$month-01');

        final last =
            DateTime(
              first.year,
              first.month + 1,
              0,
            );

        start = dateText(first);
        end = dateText(last);

        billDate =
            (period == '7' ||
                    period == '14' ||
                    period == '21')
                ? int.parse(period)
                : null;
      } else {
        start = dateText(from);
        end = dateText(to);
        billDate = null;
      }

      final billDateCondition =
          billDate == null
              ? ''
              : ' AND c.bill_date=?';

      final activeBillingId =
          widget.db.activeBillingId;

      final args = <dynamic>[
        activeBillingId,
        month,
        activeBillingId,
        staffId,
        start,
        end,
      ];

      if (billDate != null) {
        args.add(billDate);
      }

      final rows =
          await database.rawQuery(
        '''
        SELECT
          c.id AS customer_id,
          c.cust_id,
          c.user_id,
          c.name,
          c.mobile,
          c.package_name,
          c.bill_date,
          c.active,
          c.staff_id,
          b.billing_month,

          COALESCE(
            b.amount,
            c.amount,
            0
          ) AS bill_amount,

          COALESCE(
            (
              SELECT SUM(p2.amount)
              FROM payments p2
              WHERE p2.billing_id=?
                AND p2.bill_id=b.id
            ),
            0
          ) AS bill_paid,

          COALESCE(
            (
              SELECT SUM(p3.amount)
              FROM payments p3
              WHERE p3.billing_id=?
                AND p3.customer_id=c.id
                AND p3.staff_id=?
                AND date(p3.payment_date)
                    BETWEEN date(?) AND date(?)
            ),
            0
          ) AS staff_collection,

          MAX(
            CASE
              WHEN p.billing_id=?
               AND p.staff_id=?
              THEN p.payment_date
              ELSE NULL
            END
          ) AS last_staff_payment_date

        FROM customers c

        LEFT JOIN bills b
          ON b.customer_id=c.id
         AND b.billing_id=?
         AND b.billing_month=?

        LEFT JOIN payments p
          ON p.customer_id=c.id

        WHERE c.billing_id=?
          AND c.staff_id=?

          $billDateCondition

        GROUP BY
          c.id,
          c.cust_id,
          c.user_id,
          c.name,
          c.mobile,
          c.package_name,
          c.bill_date,
          c.active,
          c.staff_id,
          b.billing_month,
          b.amount,
          c.amount

        ORDER BY
          c.user_id COLLATE NOCASE
        ''',
        [
          activeBillingId,
          activeBillingId,
          staffId,
          start,
          end,
          activeBillingId,
          staffId,
          activeBillingId,
          month,
          activeBillingId,
          staffId,
          if (billDate != null) billDate,
        ].where((v) => v != null).toList(),
      );

      final collectedRows =
          <Map<String, dynamic>>[];

      final dueRows =
          <Map<String, dynamic>>[];

      final closedRows =
          <Map<String, dynamic>>[];

      for (final raw in rows) {
        final r =
            Map<String, dynamic>.from(raw);

        final bill =
            ((r['bill_amount'] ?? 0)
                    as num)
                .toDouble();

        final paid =
            ((r['bill_paid'] ?? 0)
                    as num)
                .toDouble();

        final staffAmount =
            ((r['staff_collection'] ?? 0)
                    as num)
                .toDouble();

        final dueAmount =
            (bill - paid)
                .clamp(
                  0,
                  double.infinity,
                )
                .toDouble();

        r['bill_amount'] = bill;
        r['bill_paid'] = paid;
        r['staff_collection'] =
            staffAmount;
        r['due_amount'] = dueAmount;

        if ((r['active'] ?? 1) == 0) {
          closedRows.add(r);
        }

        if (staffAmount > 0) {
          collectedRows.add(r);
        }

        if (dueAmount > 0) {
          dueRows.add(r);
        }
      }

      final billTotal =
          rows.fold<double>(
        0,
        (sum, r) =>
            sum +
            ((r['bill_amount'] ?? 0)
                    as num)
                .toDouble(),
      );

      final collectionTotal =
          rows.fold<double>(
        0,
        (sum, r) =>
            sum +
            ((r['staff_collection'] ?? 0)
                    as num)
                .toDouble(),
      );

      final dueTotal =
          dueRows.fold<double>(
        0,
        (sum, r) =>
            sum +
            ((r['due_amount'] ?? 0)
                    as num)
                .toDouble(),
      );

      totals = {
        'users': rows.length,
        'bill': billTotal,
        'collection': collectionTotal,
        'due': dueTotal,
        'collected_users':
            collectedRows.length,
        'due_users':
            dueRows.length,
        'closed_users':
            closedRows.length,
      };

      if (!mounted) return;

      setState(() {
        collected = collectedRows;
        due = dueRows;
        closed = closedRows;
        busy = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => busy = false);

      _error(
        '${t(
          'স্টাফ রিপোর্ট তৈরি করতে সমস্যা: ',
          'Staff report error: ',
        )}$e',
      );
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
    final logo = pw.MemoryImage(
      logoData.buffer.asUint8List(),
    );

    final doc = pw.Document();

    final watermark = pw.Positioned.fill(
      child: pw.Center(
        child: pw.Opacity(
          opacity: 0.06,
          child: pw.Image(
            logo,
            width: 300,
            height: 300,
            fit: pw.BoxFit.contain,
          ),
        ),
      ),
    );

    pw.Widget summaryBox() {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.6),
        ),
        child: pw.Wrap(
          spacing: 18,
          runSpacing: 7,
          children: [
            pw.Text(
              'Total Users: ${totals['users'] ?? 0}',
            ),
            pw.Text(
              'Total Bill: BDT ${money((totals['bill'] ?? 0) as num)}',
            ),
            pw.Text(
              'Staff Collection: BDT ${money((totals['collection'] ?? 0) as num)}',
            ),
            pw.Text(
              'Total Due: BDT ${money((totals['due'] ?? 0) as num)}',
            ),
            pw.Text(
              'Collected Users: ${totals['collected_users'] ?? 0}',
            ),
            pw.Text(
              'Due Users: ${totals['due_users'] ?? 0}',
            ),
            pw.Text(
              'Closed Users: ${totals['closed_users'] ?? 0}',
            ),
          ],
        ),
      );
    }

    pw.Widget reportTable(
      String title,
      List<Map<String, dynamic>> data, {
      required bool collection,
    }) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 10),

          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),

          pw.SizedBox(height: 5),

          if (data.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text('No records'),
            )
          else
            pw.Table.fromTextArray(
              headers: [
                'User ID',
                'Name',
                'Mobile',
                'Bill Date',
                'Package',
                collection ? 'Collection' : 'Due',
                'Status',
              ],
              data: data.map((r) {
                final value = collection
                    ? r['staff_collection']
                    : r['due_amount'];

                return [
                  '${r['user_id'] ?? ''}',
                  '${r['name'] ?? ''}',
                  '${r['mobile'] ?? ''}',
                  '${r['bill_date'] ?? ''}',
                  '${r['package_name'] ?? ''}',
                  money((value ?? 0) as num),
                  (r['active'] ?? 1) == 1
                      ? 'Active'
                      : 'Closed',
                ];
              }).toList(),
              cellStyle: const pw.TextStyle(
                fontSize: 6.5,
              ),
              headerStyle: pw.TextStyle(
                fontSize: 6.5,
                fontWeight: pw.FontWeight.bold,
              ),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignment: pw.Alignment.centerLeft,
              border: pw.TableBorder.all(
                width: 0.4,
              ),
              cellPadding: const pw.EdgeInsets.all(4),
            ),

          pw.SizedBox(height: 8),
        ],
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(
          24,
          24,
          24,
          28,
        ),

        header: (_) {
          return pw.Column(
            crossAxisAlignment:
                pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                crossAxisAlignment:
                    pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(
                    width: 48,
                    height: 48,
                    child: pw.Image(
                      logo,
                      fit: pw.BoxFit.contain,
                    ),
                  ),

                  pw.SizedBox(width: 10),

                  pw.Column(
                    crossAxisAlignment:
                        pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Digital 24 Online Billing',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight:
                              pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'Internet Service Provider',
                        style: const pw.TextStyle(
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 4),

              pw.Text(
                'Seroil Colony, 4 No. Road, Ghoramara, Chandrima Rajshahi-6100',
                style: const pw.TextStyle(
                  fontSize: 8,
                ),
              ),

              pw.SizedBox(height: 5),

              pw.Divider(
                thickness: 0.8,
              ),
            ],
          );
        },

        footer: (context) {
          return pw.Row(
            mainAxisAlignment:
                pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Digital 24 Online Billing',
                style: const pw.TextStyle(
                  fontSize: 7,
                ),
              ),
              pw.Text(
                'Page ${context.pageNumber} / ${context.pagesCount}',
                style: const pw.TextStyle(
                  fontSize: 7,
                ),
              ),
            ],
          );
        },

        build: (_) {
          return [
            pw.Stack(
              children: [
                watermark,

                pw.Column(
                  crossAxisAlignment:
                      pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'BILLING: $billingName',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight:
                            pw.FontWeight.bold,
                      ),
                    ),

                    pw.SizedBox(height: 4),

                    pw.Text(
                      'STAFF COLLECTION REPORT — $selectedStaffName',
                      style: pw.TextStyle(
                        fontSize: 15,
                        fontWeight:
                            pw.FontWeight.bold,
                      ),
                    ),

                    pw.SizedBox(height: 3),

                    pw.Text(
                      'Period: $periodLabel',
                      style: const pw.TextStyle(
                        fontSize: 9,
                      ),
                    ),

                    pw.SizedBox(height: 10),

                    summaryBox(),

                    reportTable(
                      'Collected Users (${collected.length})',
                      collected,
                      collection: true,
                    ),

                    reportTable(
                      'Due Users (${due.length})',
                      due,
                      collection: false,
                    ),

                    reportTable(
                      'Closed Users (${closed.length})',
                      closed,
                      collection: false,
                    ),

                    pw.SizedBox(height: 8),

                    pw.Text(
                      'Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                      style: const pw.TextStyle(
                        fontSize: 7,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    return Uint8List.fromList(
      await doc.save(),
    );
    }

      Future<bool> _preparePdf() async {
    if (staffId == null) {
      _error(
        t(
          'আগে একজন স্টাফ নির্বাচন করুন',
          'Select a staff first',
        ),
      );
      return false;
    }

    if (collected.isEmpty &&
        due.isEmpty &&
        closed.isEmpty) {
      await runStaffReport();
    }

    if (!mounted) return false;

    if (collected.isEmpty &&
        due.isEmpty &&
        closed.isEmpty) {
      _error(
        t(
          'এই রিপোর্টে কোনো তথ্য পাওয়া যায়নি',
          'No data found for this report',
        ),
      );
      return false;
    }

    return true;
  }

  Future<void> previewPdf() async {
    if (!await _preparePdf()) return;

    try {
      if (mounted) {
        setState(() => busy = true);
      }

      final bytes = await buildPdf();

      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Digital24Online_Staff_Report.pdf',
      );
    } catch (e) {
      if (mounted) {
        _error(
          '${t(
            'PDF খুলতে সমস্যা: ',
            'PDF preview error: ',
          )}$e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

    Future<void> downloadPdf() async {
    if (!await _preparePdf()) return;

    try {
      if (mounted) {
        setState(() => busy = true);
      }

      final bytes = await buildPdf();

      final safeName = selectedStaffName.replaceAll(
        RegExp(r'[^a-zA-Z0-9_-]+'),
        '_',
      );

      final filename =
          'Digital24Online_Staff_${safeName}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';

      final savedPath =
          await FilePicker.platform.saveFile(
        dialogTitle: t(
          'Staff Report PDF সংরক্ষণ করুন',
          'Save Staff Report PDF',
        ),
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: bytes,
      );

      if (!mounted) return;

      if (savedPath == null ||
          savedPath.trim().isEmpty) {
        _error(
          t(
            'PDF সংরক্ষণ করা হয়নি',
            'PDF was not saved',
          ),
        );
      } else {
        _error(
          t(
            'PDF সফলভাবে সংরক্ষণ হয়েছে',
            'PDF saved successfully',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _error(
          '${t(
            'PDF Download করতে সমস্যা: ',
            'PDF download error: ',
          )}$e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> printPdf() async {
    if (!await _preparePdf()) return;

    try {
      if (mounted) {
        setState(() => busy = true);
      }

      final bytes = await buildPdf();

      final safeName = selectedStaffName.replaceAll(
        RegExp(r'[^a-zA-Z0-9_-]+'),
        '_',
      );

      final filename =
          'Digital24Online_Staff_${safeName}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';

      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: filename,
      );
    } catch (e) {
      if (mounted) {
        _error(
          '${t(
            'Print করতে সমস্যা: ',
            'Print error: ',
          )}$e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Widget section(
  String title,
  List<Map<String, dynamic>> rows, {
  required bool collection,
}) {
  return Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ExpansionTile(
      initiallyExpanded: true,
      leading: Icon(
        collection
            ? Icons.payments
            : title.contains('বন্ধ') || title.contains('Closed')
                ? Icons.person_off
                : Icons.money_off,
      ),
      title: Text(
        '$title (${rows.length})',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      children: rows.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  t(
                    'কোনো তথ্য পাওয়া যায়নি',
                    'No records found',
                  ),
                ),
              ),
            ]
          : rows.map((r) {
              final value = collection
                  ? r['staff_collection']
                  : r['due_amount'];

              final isClosed = (r['active'] ?? 1) == 0;

              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  child: Text(
                    '${r['bill_date'] ?? ''}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                title: Text(
                  '${r['user_id'] ?? ''} — ${r['name'] ?? ''}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${r['mobile'] ?? ''} • '
                  '${r['package_name'] ?? ''}\n'
                  '${t('বিল ডেট', 'Bill Date')}: ${r['bill_date'] ?? ''} • '
                  '${isClosed ? t('বন্ধ', 'Closed') : t('চালু', 'Active')}',
                ),
                isThreeLine: true,
                trailing: Text(
                  '${money((value ?? 0) as num)} ৳',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: collection
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
              );
            }).toList(),
    ),
  );
  }

  @override
Widget build(BuildContext context) {
  Widget optionCard({
    required IconData icon,
    required String bangla,
    required String english,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return Card(
      elevation: selected ? 4 : 1,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          child: Row(
            children: [
              CircleAvatar(
                child: Icon(icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  t(bangla, english),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle,
                  color: Colors.green,
                )
              else
                const Icon(Icons.arrow_forward_ios, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  return AlertDialog(
    title: Row(
      children: [
        const Icon(Icons.assessment),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            t(
              'স্টাফ রিপোর্ট সেন্টার',
              'Staff Report Center',
            ),
          ),
        ),
      ],
    ),
    content: SizedBox(
      width: 900,
      height: 650,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // STAFF SELECTION
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: DropdownButtonFormField<int>(
                  value: staffId,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.person),
                    labelText: t(
                      'স্টাফ নির্বাচন করুন',
                      'Select Staff',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  items: staff.map((s) {
                    final id = (s['id'] as num).toInt();

                    return DropdownMenuItem<int>(
                      value: id,
                      child: Text(
                        '${s['name'] ?? ''}'
                        '${s['mobile'] != null && s['mobile'].toString().isNotEmpty ? ' — ${s['mobile']}' : ''}',
                      ),
                    );
                  }).toList(),
                  onChanged: busy
                      ? null
                      : (v) {
                          setState(() {
                            staffId = v;
                            collected = [];
                            due = [];
                            closed = [];
                            totals = {};
                          });
                        },
                ),
              ),
            ),

            const SizedBox(height: 10),

            Text(
              t(
                'রিপোর্টের ধরন নির্বাচন করুন',
                'Select Report Type',
              ),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            // 7 DAY
            optionCard(
              icon: Icons.looks_one,
              bangla: '৭ তারিখের বিল রিপোর্ট',
              english: '7th Bill Date Report',
              selected: period == '7',
              onTap: () {
                setState(() {
                  period = '7';
                  billDate = 7;
                });
                runStaffReport();
              },
            ),

            // 14 DAY
            optionCard(
              icon: Icons.looks_two,
              bangla: '১৪ তারিখের বিল রিপোর্ট',
              english: '14th Bill Date Report',
              selected: period == '14',
              onTap: () {
                setState(() {
                  period = '14';
                  billDate = 14;
                });
                runStaffReport();
              },
            ),

            // 21 DAY
            optionCard(
              icon: Icons.looks_3,
              bangla: '২১ তারিখের বিল রিপোর্ট',
              english: '21st Bill Date Report',
              selected: period == '21',
              onTap: () {
                setState(() {
                  period = '21';
                  billDate = 21;
                });
                runStaffReport();
              },
            ),

            // MONTHLY
            optionCard(
              icon: Icons.calendar_month,
              bangla: 'মাসিক রিপোর্ট',
              english: 'Monthly Report',
              selected: period == 'monthly',
              onTap: () {
                setState(() {
                  period = 'monthly';
                  billDate = null;
                });
                runStaffReport();
              },
            ),

            // CUSTOM DATE
            optionCard(
              icon: Icons.date_range,
              bangla: 'নির্দিষ্ট তারিখের রিপোর্ট',
              english: 'Custom Date Range',
              selected: period == 'custom',
              onTap: () async {
                setState(() {
                  period = 'custom';
                  billDate = null;
                });

                await pickDate(true);
                await pickDate(false);

                if (mounted) {
                  runStaffReport();
                }
              },
            ),

            const SizedBox(height: 10),

            // CURRENT PERIOD
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.event),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${t('বর্তমান রিপোর্ট: ', 'Current Report: ')}$periodLabel',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // MONTH PICKER
            if (period == 'monthly' ||
                period == '7' ||
                period == '14' ||
                period == '21')
              OutlinedButton.icon(
                onPressed: busy ? null : pickMonth,
                icon: const Icon(Icons.calendar_month),
                label: Text(
                  '${t('মাস নির্বাচন: ', 'Select Month: ')}$month',
                ),
              ),

            // CUSTOM DATE
            if (period == 'custom')
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => pickDate(true),
                      child: Text(
                        '${t('শুরু: ', 'From: ')}${dateText(from)}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => pickDate(false),
                      child: Text(
                        '${t('শেষ: ', 'To: ')}${dateText(to)}',
                      ),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 10),

                        // GENERATE
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : runStaffReport,
              icon: const Icon(
                Icons.assessment,
              ),
              label: Text(
                t(
                  'রিপোর্ট তৈরি করুন',
                  'Generate Report',
                ),
              ),
            ),

            const SizedBox(height: 8),

            // PDF PREVIEW
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : previewPdf,
              icon: const Icon(
                Icons.picture_as_pdf,
              ),
              label: Text(
                t(
                  'PDF দেখুন',
                  'Preview PDF',
                ),
              ),
            ),

            const SizedBox(height: 8),

            // DOWNLOAD
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : downloadPdf,
              icon: const Icon(
                Icons.download,
              ),
              label: Text(
                t(
                  'PDF Download',
                  'Download PDF',
                ),
              ),
            ),

            const SizedBox(height: 8),

            // PRINT
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : printPdf,
              icon: const Icon(
                Icons.print,
              ),
              label: Text(
                t(
                  'Print',
                  'Print',
                ),
              ),
            ),

            if (busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),

            // SUMMARY
            if (totals.isNotEmpty) ...[
              const SizedBox(height: 12),

              Text(
                t(
                  'রিপোর্ট সারাংশ',
                  'Report Summary',
                ),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(
                      Icons.people,
                      size: 18,
                    ),
                    label: Text(
                      '${t('মোট ইউজার', 'Users')}: ${totals['users'] ?? 0}',
                    ),
                  ),
                  Chip(
                    avatar: const Icon(
                      Icons.receipt_long,
                      size: 18,
                    ),
                    label: Text(
                      '${t('মোট বিল', 'Total Bill')}: ${money((totals['bill'] ?? 0) as num)} ৳',
                    ),
                  ),
                  Chip(
                    avatar: const Icon(
                      Icons.payments,
                      size: 18,
                    ),
                    label: Text(
                      '${t('কালেকশন', 'Collection')}: ${money((totals['collection'] ?? 0) as num)} ৳',
                    ),
                  ),
                  Chip(
                    avatar: const Icon(
                      Icons.money_off,
                      size: 18,
                    ),
                    label: Text(
                      '${t('বকেয়া', 'Due')}: ${money((totals['due'] ?? 0) as num)} ৳',
                    ),
                  ),
                  Chip(
                    label: Text(
                      '${t('Paid Users', 'Paid Users')}: ${totals['collected_users'] ?? 0}',
                    ),
                  ),
                  Chip(
                    label: Text(
                      '${t('Due Users', 'Due Users')}: ${totals['due_users'] ?? 0}',
                    ),
                  ),
                  Chip(
                    label: Text(
                      '${t('Closed Users', 'Closed Users')}: ${totals['closed_users'] ?? 0}',
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),

            // COLLECTION
            section(
              t('কালেকশন হয়েছে', 'Collected Users'),
              collected,
              collection: true,
            ),

            // DUE
            section(
              t('বকেয়া ইউজার', 'Due Users'),
              due,
              collection: false,
            ),

            // CLOSED
            section(
              t('বন্ধ ইউজার', 'Closed Users'),
              closed,
              collection: false,
            ),
          ],
        ),
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: Text(
          t('বন্ধ', 'Close'),
        ),
      ),
    ],
    );
}
}
