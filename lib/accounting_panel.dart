part of 'main.dart';

// ============================================================================
// پنل حسابداری (نقش سوم): حقوق و دستمزد، فاکتورهای فروش ویژه، مطالبات/گزارش‌ها
// همه‌ی ارتباط‌ها از همان فید مشترک (NetworkService.publishEvent / fetchRecentEvents).
// گزارش‌های ارسالی به مدیریت: type = accounting_report
// ============================================================================

int _accKeyOf(DateTime d) {
  final j = _gregorianToJalali(d.year, d.month, d.day);
  return j[0] * 10000 + j[1] * 100 + j[2];
}

int? _accParseMoney(String text) => int.tryParse(
    _expDigits(text).replaceAll(',', '').replaceAll('٬', '').trim());

Color _accAmber(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? Colors.amber.shade300
        : Colors.amber.shade900;

Future<bool> _accPublish(String type, Map<String, dynamic> payload) async {
  try {
    final network = NetworkService();
    final config = await network.loadConfig();
    if (!config.isConfigured) return false;
    await network.publishEvent(type: type, actorName: 'حسابدار', payload: payload);
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _accSharePdf({
  required String fileName,
  required String text,
  required List<pw.Widget> Function(pw.Font font) build,
}) async {
  final font = await _loadFont();
  final pdf = pw.Document();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 30, 28, 30),
      textDirection: pw.TextDirection.rtl,
      maxPages: 200,
      footer: (context) => pw.Align(
        alignment: pw.Alignment.center,
        child: _pdfShareTextWidget(
            'صفحه ${context.pageNumber} از ${context.pagesCount}', font,
            fontSize: 8, color: PdfColors.grey600),
      ),
      build: (context) => build(font),
    ),
  );
  final bytes = await pdf.save();
  await Share.shareXFiles(
    [XFile.fromData(bytes, name: fileName, mimeType: 'application/pdf')],
    text: text,
  );
}

// ---------------------------------------------------------------- فیلتر تاریخ

class AccDateFilter {
  String preset; // all / today / week / month / custom
  String from;
  String to;
  AccDateFilter({this.preset = 'month', this.from = '', this.to = ''});

  bool matches(String date) {
    if (preset == 'all') return true;
    final k = _expDateKey(date);
    if (k == 0) return false;
    final now = DateTime.now();
    final today = _accKeyOf(now);
    switch (preset) {
      case 'today':
        return k == today;
      case 'week':
        return k >= _accKeyOf(now.subtract(const Duration(days: 6))) && k <= today;
      case 'month':
        return k ~/ 100 == today ~/ 100;
      case 'custom':
        final f = _expDateKey(from);
        final t = _expDateKey(to);
        return (f == 0 || k >= f) && (t == 0 || k <= t);
    }
    return true;
  }

  String get label {
    switch (preset) {
      case 'today':
        return 'امروز';
      case 'week':
        return '۷ روز اخیر';
      case 'month':
        return 'ماه جاری';
      case 'custom':
        return 'از ${from.isEmpty ? '…' : from} تا ${to.isEmpty ? '…' : to}';
    }
    return 'همه‌ی تاریخ‌ها';
  }
}

class AccDateFilterBar extends StatefulWidget {
  final AccDateFilter filter;
  final VoidCallback onChanged;
  const AccDateFilterBar({super.key, required this.filter, required this.onChanged});

  @override
  State<AccDateFilterBar> createState() => _AccDateFilterBarState();
}

class _AccDateFilterBarState extends State<AccDateFilterBar> {
  late final TextEditingController _from = TextEditingController(text: widget.filter.from);
  late final TextEditingController _to = TextEditingController(text: widget.filter.to);

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.filter;
    Widget chip(String id, String label) => appChoiceChip(
          context: context,
          label: label,
          selected: filter.preset == id,
          onTap: () {
            setState(() => filter.preset = id);
            widget.onChanged();
          },
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            chip('today', 'امروز'),
            chip('week', '۷ روز اخیر'),
            chip('month', 'ماه جاری'),
            chip('all', 'همه'),
            chip('custom', 'بازه دلخواه'),
          ],
        ),
        if (filter.preset == 'custom') ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _from,
                  onChanged: (v) {
                    filter.from = v.trim();
                    widget.onChanged();
                  },
                  decoration: const InputDecoration(labelText: 'از تاریخ', hintText: '۱۴۰۵/۰۶/۰۱', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _to,
                  onChanged: (v) {
                    filter.to = v.trim();
                    widget.onChanged();
                  },
                  decoration: const InputDecoration(labelText: 'تا تاریخ', hintText: '۱۴۰۵/۰۶/۳۱', isDense: true, border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------------ داده‌ها

class AccExpense {
  final String id, user, name, category, paymentType, date;
  final int amount;
  const AccExpense({
    required this.id,
    required this.user,
    required this.name,
    required this.category,
    required this.paymentType,
    required this.date,
    required this.amount,
  });
}

class AccSale {
  final String user, invoice, date;
  final int total;
  const AccSale({required this.user, required this.invoice, required this.date, required this.total});
}

class AccFeed {
  final List<AccExpense> expenses;
  final List<AccSale> sales;
  final List<Map<String, dynamic>> managerEvents;
  final List<Map<String, dynamic>> reports;
  final List<Map<String, dynamic>> deletions;
  const AccFeed(this.expenses, this.sales, this.managerEvents, this.reports, this.deletions);

  List<String> get cashiers {
    final set = <String>{
      ...expenses.map((e) => e.user),
      ...sales.map((e) => e.user),
    }..removeWhere((e) => e.trim().isEmpty);
    final list = set.toList()..sort();
    return list;
  }

  static int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  static Future<AccFeed> load() async {
    final network = NetworkService();
    try {
      await network.syncPendingEvents();
    } catch (_) {}
    final events = await network.fetchRecentEvents(limit: 3000);
    final expenses = <AccExpense>[];
    final sales = <AccSale>[];
    final manager = <Map<String, dynamic>>[];
    final reports = <Map<String, dynamic>>[];
    final deletions = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final e in events) {
      final type = e['type']?.toString() ?? '';
      final p = Map<String, dynamic>.from(e['payload'] ?? {});
      final user = (p['user_name']?.toString().trim().isNotEmpty == true)
          ? p['user_name'].toString().trim()
          : (e['actor_name']?.toString() ?? '');
      if (type == 'cashier_performance') {
        final action = p['action']?.toString() ?? '';
        if (action == 'daily_expense') {
          final id = p['id']?.toString() ?? e['id'].toString();
          if (!seen.add('x|$user|$id')) continue;
          expenses.add(AccExpense(
            id: '$user|$id',
            user: user,
            name: p['name']?.toString() ?? '',
            category: ExpenseCategorizer.categorize(p['name']?.toString() ?? ''),
            paymentType: p['paymentType']?.toString() ?? 'نقدی',
            date: p['date']?.toString() ?? '',
            amount: _int(p['amount']),
          ));
        } else if (action == 'sales_invoice') {
          final no = p['invoice_number']?.toString() ?? e['id'].toString();
          if (!seen.add('s|$user|$no')) continue;
          sales.add(AccSale(
            user: user,
            invoice: no,
            date: p['date']?.toString() ?? '',
            total: _int(p['total']),
          ));
        } else if (action == 'invoice_deleted' || action == 'expense_deleted' || action == 'manifest_deleted') {
          deletions.add(e);
        }
      } else if (type == 'manager_price_change' || type == 'manager_cheque_action') {
        manager.add(e);
      } else if (type == 'accounting_report') {
        reports.add(e);
      }
    }
    deletions.sort((a, b) => (b['created_at']?.toString() ?? '').compareTo(a['created_at']?.toString() ?? ''));
    return AccFeed(expenses, sales, manager, reports, deletions);
  }
}

// -------------------------------------------------------------- صفحه اصلی

class AccountingHomeScreen extends StatelessWidget {
  const AccountingHomeScreen({super.key});

  Widget _tool(BuildContext context, IconData icon, String title, String sub, Color color, Widget Function() page) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page())),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(radius: 26, backgroundColor: color.withOpacity(0.15), child: Icon(icon, color: color, size: 28)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                    const SizedBox(height: 3),
                    Text(sub, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('📒 پنل حسابداری'),
          backgroundColor: const Color(0xFF185C3A),
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'خروج',
              icon: const Icon(Icons.logout),
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.of(context).padding.bottom),
          children: [
            _tool(context, Icons.payments_outlined, 'حقوق و دستمزد',
                'محاسبه‌ی حقوق صندوق‌داران با هزینه‌های روزانه‌ی ثبت‌شده', Colors.green.shade700, () => const PayrollScreen()),
            const SizedBox(height: 12),
            _tool(context, Icons.workspace_premium_outlined, 'فاکتورهای فروش ویژه',
                'فاکتور ادارات؛ ویرایش قیمت و افزودن مخارج فروش', Colors.deepPurple, () => const SpecialInvoicesScreen()),
            const SizedBox(height: 12),
            _tool(context, Icons.account_balance_wallet_outlined, 'مطالبات و گزارش‌ها',
                'فروش و هزینه‌ی صندوق‌داران به تفکیک نام + گزارش‌های مدیریت', Colors.orange.shade800, () => const ReceivablesScreen()),
            const SizedBox(height: 12),
            _tool(context, Icons.wifi_tethering, 'ارتباط با شبکه',
                'تنظیم اتصال برای دریافت اطلاعات و ارسال گزارش', Colors.blue.shade700, () => const NetworkConnectionScreen()),
            const SizedBox(height: 26),
            Center(
              child: Text('توسعه‌دهنده: رضا قاسمی',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------- حقوق و دستمزد

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});
  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  AccFeed? _feed;
  bool _loading = true;
  String? _cashier;
  final _filter = AccDateFilter(preset: 'month');
  final _baseCtrl = TextEditingController();
  final _addCtrl = TextEditingController();
  final _dedCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _mode = 'reimburse'; // reimburse = اضافه به حقوق | deduct = کسر از حقوق
  final Set<String> _excluded = {};
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    _addCtrl.dispose();
    _dedCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final feed = await AccFeed.load();
    if (!mounted) return;
    setState(() {
      _feed = feed;
      _loading = false;
      if (_cashier == null || !feed.cashiers.contains(_cashier)) {
        _cashier = feed.cashiers.isEmpty ? null : feed.cashiers.first;
      }
    });
  }

  List<AccExpense> get _expenses {
    final feed = _feed;
    if (feed == null || _cashier == null) return [];
    return feed.expenses
        .where((e) => e.user == _cashier && _filter.matches(e.date))
        .toList()
      ..sort((a, b) => _expDateKey(b.date).compareTo(_expDateKey(a.date)));
  }

  int get _expTotal => _expenses.where((e) => !_excluded.contains(e.id)).fold(0, (s, e) => s + e.amount);
  int get _base => _accParseMoney(_baseCtrl.text) ?? 0;
  int get _add => _accParseMoney(_addCtrl.text) ?? 0;
  int get _ded => _accParseMoney(_dedCtrl.text) ?? 0;
  int get _net => _base + _add - _ded + (_mode == 'reimburse' ? _expTotal : -_expTotal);

  Map<String, dynamic> _payload() {
    final included = _expenses.where((e) => !_excluded.contains(e.id)).toList();
    return {
      'report_type': 'payroll',
      'title': 'حقوق و دستمزد',
      'cashier': _cashier,
      'period': _filter.label,
      'base_salary': _base,
      'additions': _add,
      'deductions': _ded,
      'expense_mode': _mode,
      'expenses_total': _expTotal,
      'expenses_count': included.length,
      'net': _net,
      'total': _net,
      'note': _noteCtrl.text.trim(),
      'date': _todayJalali(),
      'expenses': included
          .take(80)
          .map((e) => {'name': e.name, 'amount': e.amount, 'date': e.date, 'payment': e.paymentType, 'category': e.category})
          .toList(),
    };
  }

  Future<void> _send() async {
    if (_cashier == null || _sending) return;
    setState(() => _sending = true);
    final ok = await _accPublish('accounting_report', _payload());
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? '✅ گزارش حقوق برای مدیریت ارسال شد'
            : 'ارسال انجام نشد؛ ابتدا از «ارتباط با شبکه» اتصال را تنظیم کنید.')));
  }

  Future<void> _pdf() async {
    if (_cashier == null) return;
    final p = _payload();
    final included = _expenses.where((e) => !_excluded.contains(e.id)).toList();
    try {
      await _accSharePdf(
        fileName: 'payroll_${_cashier}.pdf',
        text: 'حقوق و دستمزد $_cashier',
        build: (font) => [
          pw.Center(child: _pdfShareTextWidget('فیش حقوق و دستمزد', font, fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.green)),
          pw.SizedBox(height: 10),
          _pdfShareTextWidget('نام صندوق‌دار: $_cashier', font, fontWeight: pw.FontWeight.bold),
          _pdfShareTextWidget('دوره: ${_filter.label}   |   تاریخ تهیه: ${_todayJalali()}', font, fontSize: 10),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey500),
            children: [
              for (final row in [
                ['حقوق پایه', '${_expMoney(p['base_salary'] as int)} ریال'],
                ['اضافات (پاداش/اضافه‌کار)', '${_expMoney(p['additions'] as int)} ریال'],
                ['کسورات', '${_expMoney(p['deductions'] as int)} ریال'],
                [_mode == 'reimburse' ? 'هزینه‌های روزانه (بازپرداخت +)' : 'هزینه‌های روزانه (کسر −)', '${_expMoney(p['expenses_total'] as int)} ریال'],
                ['خالص قابل پرداخت', '${_expMoney(p['net'] as int)} ریال'],
              ])
                pw.TableRow(children: [_pdfShareCell(row[0], font, bold: true), _pdfShareCell(row[1], font)]),
            ],
          ),
          pw.SizedBox(height: 14),
          _pdfShareTextWidget('جزئیات هزینه‌های روزانه', font, fontSize: 14, fontWeight: pw.FontWeight.bold),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey500),
            columnWidths: const {0: pw.FlexColumnWidth(1.4), 1: pw.FlexColumnWidth(3), 2: pw.FlexColumnWidth(1.4), 3: pw.FlexColumnWidth(1.6)},
            children: [
              pw.TableRow(
                repeat: true,
                decoration: const pw.BoxDecoration(color: PdfColors.green100),
                children: [
                  _pdfShareCell('تاریخ', font, bold: true),
                  _pdfShareCell('عنوان', font, bold: true),
                  _pdfShareCell('پرداخت', font, bold: true),
                  _pdfShareCell('مبلغ', font, bold: true),
                ],
              ),
              ...included.map((e) => pw.TableRow(children: [
                    _pdfShareCell(e.date, font),
                    _pdfShareCell(e.name, font, align: pw.TextAlign.right),
                    _pdfShareCell(e.paymentType, font),
                    _pdfShareCell('${_expMoney(e.amount)}', font),
                  ])),
            ],
          ),
          if (_noteCtrl.text.trim().isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _pdfShareTextWidget('توضیحات: ${_noteCtrl.text.trim()}', font, fontSize: 10),
          ],
        ],
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در PDF: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    final expenses = _expenses;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('💵 حقوق و دستمزد'),
          backgroundColor: const Color(0xFF185C3A),
          foregroundColor: Colors.white,
          actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'به‌روزرسانی از سرور')],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : (feed == null || feed.cashiers.isEmpty)
                ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('هنوز اطلاعاتی از صندوق‌داران روی سرور نیست.\nابتدا اتصال شبکه را تنظیم و دکمه‌ی به‌روزرسانی را بزنید.', textAlign: TextAlign.center)))
                : ListView(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 30 + MediaQuery.of(context).padding.bottom),
                    children: [
                      DropdownButtonFormField<String>(
                        value: _cashier,
                        decoration: const InputDecoration(labelText: 'صندوق‌دار', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder()),
                        items: feed.cashiers.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                        onChanged: (v) => setState(() {
                          _cashier = v;
                          _excluded.clear();
                        }),
                      ),
                      const SizedBox(height: 10),
                      AccDateFilterBar(filter: _filter, onChanged: () => setState(() => _excluded.clear())),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _baseCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [ThousandsSeparatorInputFormatter()],
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: 'حقوق پایه', suffixText: 'ریال', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _addCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [ThousandsSeparatorInputFormatter()],
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(labelText: 'اضافات', helperText: 'پاداش/اضافه‌کار', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _dedCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [ThousandsSeparatorInputFormatter()],
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(labelText: 'کسورات', helperText: 'مساعده/غیبت', border: OutlineInputBorder()),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      const Text('نحوه‌ی محاسبه‌ی هزینه‌های روزانه‌ی این صندوق‌دار', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 'reimburse', label: Text('اضافه به حقوق')),
                          ButtonSegment(value: 'deduct', label: Text('کسر از حقوق')),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (v) => setState(() => _mode = v.first),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        color: _softGreen(context),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('جمع هزینه‌های انتخاب‌شده: ${_expMoney(_expTotal)} ریال', style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              Text('خالص قابل پرداخت: ${_expMoney(_net)} ریال',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Theme.of(context).brightness == Brightness.dark ? Colors.greenAccent : Colors.green.shade800)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _noteCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: 'توضیحات (اختیاری)', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _sending ? null : _send,
                            icon: const Icon(Icons.send),
                            label: const Text('ارسال به مدیریت'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(onPressed: _pdf, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('PDF')),
                      ]),
                      const SizedBox(height: 16),
                      Text('جزئیات هزینه‌های روزانه (${_toPersianDigits(expenses.length.toString())} مورد)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 6),
                      if (expenses.isEmpty)
                        const Padding(padding: EdgeInsets.all(18), child: Center(child: Text('در این بازه هزینه‌ای ثبت نشده است.')))
                      else
                        ...expenses.map((e) => CheckboxListTile(
                              value: !_excluded.contains(e.id),
                              onChanged: (v) => setState(() => v == true ? _excluded.remove(e.id) : _excluded.add(e.id)),
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                              title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('${e.date} • ${e.paymentType} • ✨ ${e.category}'),
                              secondary: Text('${_expMoney(e.amount)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            )),
                    ],
                  ),
      ),
    );
  }
}

// ------------------------------------------------- فاکتورهای فروش ویژه

class SpecialInvoiceItem {
  String name;
  int qty;
  int price;
  SpecialInvoiceItem({required this.name, required this.qty, required this.price});
  int get total => qty * price;
  Map<String, dynamic> toJson() => {'name': name, 'qty': qty, 'price': price};
  factory SpecialInvoiceItem.fromJson(Map<String, dynamic> j) => SpecialInvoiceItem(
      name: j['name']?.toString() ?? '', qty: AccFeed._int(j['qty']), price: AccFeed._int(j['price']));
}

class SpecialInvoiceCost {
  String title;
  int amount;
  SpecialInvoiceCost({required this.title, required this.amount});
  Map<String, dynamic> toJson() => {'title': title, 'amount': amount};
  factory SpecialInvoiceCost.fromJson(Map<String, dynamic> j) =>
      SpecialInvoiceCost(title: j['title']?.toString() ?? '', amount: AccFeed._int(j['amount']));
}

class SpecialInvoice {
  String id;
  int number;
  String customer;
  String date;
  String note;
  List<SpecialInvoiceItem> items;
  List<SpecialInvoiceCost> costs;
  bool sent;
  SpecialInvoice({
    required this.id,
    required this.number,
    required this.customer,
    required this.date,
    this.note = '',
    List<SpecialInvoiceItem>? items,
    List<SpecialInvoiceCost>? costs,
    this.sent = false,
  })  : items = items ?? [],
        costs = costs ?? [];

  int get itemsTotal => items.fold(0, (s, e) => s + e.total);
  int get costsTotal => costs.fold(0, (s, e) => s + e.amount);
  int get grandTotal => itemsTotal + costsTotal;

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'customer': customer,
        'date': date,
        'note': note,
        'sent': sent,
        'items': items.map((e) => e.toJson()).toList(),
        'costs': costs.map((e) => e.toJson()).toList(),
      };

  factory SpecialInvoice.fromJson(Map<String, dynamic> j) => SpecialInvoice(
        id: j['id']?.toString() ?? '',
        number: AccFeed._int(j['number']),
        customer: j['customer']?.toString() ?? '',
        date: j['date']?.toString() ?? '',
        note: j['note']?.toString() ?? '',
        sent: j['sent'] == true,
        items: (j['items'] as List? ?? []).whereType<Map>().map((e) => SpecialInvoiceItem.fromJson(Map<String, dynamic>.from(e))).toList(),
        costs: (j['costs'] as List? ?? []).whereType<Map>().map((e) => SpecialInvoiceCost.fromJson(Map<String, dynamic>.from(e))).toList(),
      );
}

class SpecialInvoicesScreen extends StatefulWidget {
  const SpecialInvoicesScreen({super.key});
  @override
  State<SpecialInvoicesScreen> createState() => _SpecialInvoicesScreenState();
}

class _SpecialInvoicesScreenState extends State<SpecialInvoicesScreen> {
  static const _key = 'special_invoices_v1';
  List<SpecialInvoice> _list = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        _list = (jsonDecode(raw) as List).whereType<Map>().map((e) => SpecialInvoice.fromJson(Map<String, dynamic>.from(e))).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_list.map((e) => e.toJson()).toList()));
  }

  Future<void> _edit([SpecialInvoice? existing]) async {
    final nextNumber = (_list.isEmpty ? 0 : _list.map((e) => e.number).reduce(math.max)) + 1;
    final result = await Navigator.push<SpecialInvoice>(
      context,
      MaterialPageRoute(builder: (_) => SpecialInvoiceEditor(existing: existing, nextNumber: nextNumber)),
    );
    if (result == null) return;
    setState(() {
      final i = _list.indexWhere((e) => e.id == result.id);
      if (i == -1) {
        _list.insert(0, result);
      } else {
        _list[i] = result;
      }
    });
    await _save();
  }

  Map<String, dynamic> _payload(SpecialInvoice inv) => {
        'report_type': 'special_invoice',
        'title': 'فاکتور فروش ویژه شماره ${inv.number}',
        'customer': inv.customer,
        'invoice_number': inv.number,
        'date': inv.date,
        'items_total': inv.itemsTotal,
        'costs_total': inv.costsTotal,
        'total': inv.grandTotal,
        'note': inv.note,
        'items': inv.items.map((e) => e.toJson()).toList(),
        'costs': inv.costs.map((e) => e.toJson()).toList(),
      };

  Future<void> _send(SpecialInvoice inv) async {
    final ok = await _accPublish('accounting_report', _payload(inv));
    if (!mounted) return;
    if (ok) {
      setState(() => inv.sent = true);
      await _save();
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? '✅ فاکتور ویژه برای مدیریت ارسال شد' : 'ارسال انجام نشد؛ اتصال شبکه را تنظیم کنید.')));
  }

  Future<void> _pdf(SpecialInvoice inv) async {
    try {
      await _accSharePdf(
        fileName: 'special_invoice_${inv.number}.pdf',
        text: 'فاکتور فروش ویژه ${inv.number}',
        build: (font) => [
          pw.Center(child: _pdfShareTextWidget('فاکتور فروش ویژه شماره ${inv.number}', font, fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.deepPurple)),
          pw.SizedBox(height: 10),
          _pdfShareTextWidget('خریدار: ${inv.customer}', font, fontWeight: pw.FontWeight.bold),
          _pdfShareTextWidget('تاریخ: ${inv.date}', font, fontSize: 10),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey500),
            columnWidths: const {0: pw.FlexColumnWidth(0.7), 1: pw.FlexColumnWidth(3), 2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1.8), 4: pw.FlexColumnWidth(2)},
            children: [
              pw.TableRow(
                repeat: true,
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _pdfShareCell('ردیف', font, bold: true),
                  _pdfShareCell('شرح کالا', font, bold: true),
                  _pdfShareCell('تعداد', font, bold: true),
                  _pdfShareCell('قیمت واحد', font, bold: true),
                  _pdfShareCell('مبلغ', font, bold: true),
                ],
              ),
              ...inv.items.asMap().entries.map((e) => pw.TableRow(children: [
                    _pdfShareCell(_toPersianDigits('${e.key + 1}'), font),
                    _pdfShareCell(e.value.name, font, align: pw.TextAlign.right),
                    _pdfShareCell(_toPersianDigits('${e.value.qty}'), font),
                    _pdfShareCell(_expMoney(e.value.price), font),
                    _pdfShareCell(_expMoney(e.value.total), font),
                  ])),
            ],
          ),
          pw.SizedBox(height: 10),
          if (inv.costs.isNotEmpty) ...[
            _pdfShareTextWidget('مخارج فروش', font, fontSize: 13, fontWeight: pw.FontWeight.bold),
            pw.SizedBox(height: 4),
            ...inv.costs.map((c) => _pdfShareTextWidget('${c.title}: ${_expMoney(c.amount)} ریال', font, fontSize: 10)),
            pw.SizedBox(height: 8),
          ],
          _pdfShareTextWidget('جمع اقلام: ${_expMoney(inv.itemsTotal)} ریال', font, fontWeight: pw.FontWeight.bold),
          _pdfShareTextWidget('جمع مخارج: ${_expMoney(inv.costsTotal)} ریال', font, fontWeight: pw.FontWeight.bold),
          pw.SizedBox(height: 4),
          _pdfShareTextWidget('مبلغ نهایی: ${_expMoney(inv.grandTotal)} ریال', font, fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.green),
          if (inv.note.isNotEmpty) ...[pw.SizedBox(height: 8), _pdfShareTextWidget('توضیحات: ${inv.note}', font, fontSize: 10)],
        ],
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در PDF: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('⭐ فاکتورهای فروش ویژه'), backgroundColor: const Color(0xFF185C3A), foregroundColor: Colors.white),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFF185C3A),
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('فاکتور ویژه جدید'),
          onPressed: () => _edit(),
        ),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : _list.isEmpty
                ? const Center(child: Text('هنوز فاکتور ویژه‌ای ثبت نشده است.'))
                : ListView(
                    padding: EdgeInsets.fromLTRB(14, 14, 14, 100 + MediaQuery.of(context).padding.bottom),
                    children: _list
                        .map((inv) => Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Expanded(child: Text('فاکتور ${_toPersianDigits('${inv.number}')} • ${inv.customer}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                                      if (inv.sent) const Icon(Icons.check_circle, color: Colors.green, size: 20),
                                    ]),
                                    const SizedBox(height: 3),
                                    Text('${inv.date} • ${_toPersianDigits('${inv.items.length}')} قلم • مخارج ${_expMoney(inv.costsTotal)}'),
                                    const SizedBox(height: 3),
                                    Text('مبلغ نهایی: ${_expMoney(inv.grandTotal)} ریال',
                                        style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.greenAccent : Colors.green.shade800)),
                                    Row(children: [
                                      TextButton.icon(onPressed: () => _edit(inv), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('ویرایش')),
                                      TextButton.icon(onPressed: () => _send(inv), icon: const Icon(Icons.send, size: 18), label: const Text('ارسال')),
                                      TextButton.icon(onPressed: () => _pdf(inv), icon: const Icon(Icons.picture_as_pdf_outlined, size: 18), label: const Text('PDF')),
                                      const Spacer(),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                                        onPressed: () async {
                                          setState(() => _list.removeWhere((e) => e.id == inv.id));
                                          await _save();
                                        },
                                      ),
                                    ]),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                  ),
      ),
    );
  }
}

class SpecialInvoiceEditor extends StatefulWidget {
  final SpecialInvoice? existing;
  final int nextNumber;
  const SpecialInvoiceEditor({super.key, this.existing, required this.nextNumber});
  @override
  State<SpecialInvoiceEditor> createState() => _SpecialInvoiceEditorState();
}

class _SpecialInvoiceEditorState extends State<SpecialInvoiceEditor> {
  late final TextEditingController _customer;
  late final TextEditingController _date;
  late final TextEditingController _note;
  late List<SpecialInvoiceItem> _items;
  late List<SpecialInvoiceCost> _costs;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _customer = TextEditingController(text: e?.customer ?? '');
    _date = TextEditingController(text: e?.date ?? _todayJalali());
    _note = TextEditingController(text: e?.note ?? '');
    _items = (e?.items ?? []).map((x) => SpecialInvoiceItem(name: x.name, qty: x.qty, price: x.price)).toList();
    _costs = (e?.costs ?? []).map((x) => SpecialInvoiceCost(title: x.title, amount: x.amount)).toList();
  }

  @override
  void dispose() {
    _customer.dispose();
    _date.dispose();
    _note.dispose();
    super.dispose();
  }

  int get _itemsTotal => _items.fold(0, (s, e) => s + e.total);
  int get _costsTotal => _costs.fold(0, (s, e) => s + e.amount);

  Future<void> _editItem([int? index]) async {
    final cur = index == null ? null : _items[index];
    final name = TextEditingController(text: cur?.name ?? '');
    final qty = TextEditingController(text: cur == null ? '1' : '${cur.qty}');
    final price = TextEditingController(text: cur == null ? '' : _expMoney(cur.price));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(cur == null ? 'افزودن قلم' : 'ویرایش قلم'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'شرح کالا')),
          TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'تعداد')),
          TextField(controller: price, keyboardType: TextInputType.number, inputFormatters: [ThousandsSeparatorInputFormatter()], decoration: const InputDecoration(labelText: 'قیمت فروش واحد', suffixText: 'ریال')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأیید')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      final item = SpecialInvoiceItem(
        name: name.text.trim(),
        qty: math.max(1, int.tryParse(_expDigits(qty.text)) ?? 1),
        price: _accParseMoney(price.text) ?? 0,
      );
      setState(() => index == null ? _items.add(item) : _items[index] = item);
    }
    name.dispose();
    qty.dispose();
    price.dispose();
  }

  Future<void> _editCost([int? index]) async {
    final cur = index == null ? null : _costs[index];
    final title = TextEditingController(text: cur?.title ?? '');
    final amount = TextEditingController(text: cur == null ? '' : _expMoney(cur.amount));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(cur == null ? 'افزودن مخارج فروش' : 'ویرایش مخارج'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'عنوان هزینه (دستی)', hintText: 'مثلاً کادوپیچی')),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: ['کادوپیچی', 'هزینه ارسال', 'ملزومات', 'بسته‌بندی']
                  .map((t) => ActionChip(label: Text(t), onPressed: () => setD(() => title.text = t)))
                  .toList(),
            ),
            TextField(controller: amount, keyboardType: TextInputType.number, inputFormatters: [ThousandsSeparatorInputFormatter()], decoration: const InputDecoration(labelText: 'مبلغ', suffixText: 'ریال')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأیید')),
          ],
        ),
      ),
    );
    if (ok == true && title.text.trim().isNotEmpty) {
      final c = SpecialInvoiceCost(title: title.text.trim(), amount: _accParseMoney(amount.text) ?? 0);
      setState(() => index == null ? _costs.add(c) : _costs[index] = c);
    }
    title.dispose();
    amount.dispose();
  }

  void _save() {
    if (_customer.text.trim().isEmpty || _items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نام خریدار و حداقل یک قلم لازم است.')));
      return;
    }
    final e = widget.existing;
    Navigator.pop(
      context,
      SpecialInvoice(
        id: e?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        number: e?.number ?? widget.nextNumber,
        customer: _customer.text.trim(),
        date: _date.text.trim(),
        note: _note.text.trim(),
        items: _items,
        costs: _costs,
        sent: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _itemsTotal + _costsTotal;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.existing == null ? 'فاکتور ویژه جدید' : 'ویرایش فاکتور ویژه'),
          backgroundColor: const Color(0xFF185C3A),
          foregroundColor: Colors.white,
          actions: [IconButton(onPressed: _save, icon: const Icon(Icons.check), tooltip: 'ذخیره')],
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 30 + MediaQuery.of(context).padding.bottom),
          children: [
            TextField(controller: _customer, decoration: const InputDecoration(labelText: 'نام اداره / خریدار', prefixIcon: Icon(Icons.apartment), border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: _date, decoration: const InputDecoration(labelText: 'تاریخ', prefixIcon: Icon(Icons.calendar_today_outlined), border: OutlineInputBorder())),
            const SizedBox(height: 14),
            Row(children: [
              const Expanded(child: Text('اقلام فاکتور', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              TextButton.icon(onPressed: () => _editItem(), icon: const Icon(Icons.add), label: const Text('افزودن قلم')),
            ]),
            if (_items.isEmpty) const Padding(padding: EdgeInsets.all(10), child: Text('هنوز قلمی اضافه نشده است.')),
            ..._items.asMap().entries.map((e) => Card(
                  child: ListTile(
                    onTap: () => _editItem(e.key),
                    title: Text(e.value.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${_toPersianDigits('${e.value.qty}')} × ${_expMoney(e.value.price)} = ${_expMoney(e.value.total)} ریال'),
                    trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => setState(() => _items.removeAt(e.key))),
                  ),
                )),
            const SizedBox(height: 10),
            Row(children: [
              const Expanded(child: Text('مخارج فروش', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              TextButton.icon(onPressed: () => _editCost(), icon: const Icon(Icons.add), label: const Text('افزودن هزینه')),
            ]),
            ..._costs.asMap().entries.map((e) => Card(
                  child: ListTile(
                    onTap: () => _editCost(e.key),
                    title: Text(e.value.title),
                    subtitle: Text('${_expMoney(e.value.amount)} ریال'),
                    trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => setState(() => _costs.removeAt(e.key))),
                  ),
                )),
            const SizedBox(height: 10),
            TextField(controller: _note, maxLines: 2, decoration: const InputDecoration(labelText: 'توضیحات', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Card(
              color: _softGreen(context),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('جمع اقلام: ${_expMoney(_itemsTotal)} ریال'),
                  Text('جمع مخارج فروش: ${_expMoney(_costsTotal)} ریال'),
                  const SizedBox(height: 4),
                  Text('مبلغ نهایی: ${_expMoney(total)} ریال', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('ذخیره فاکتور')),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------ مطالبات و گزارش‌ها

class ReceivablesScreen extends StatefulWidget {
  const ReceivablesScreen({super.key});
  @override
  State<ReceivablesScreen> createState() => _ReceivablesScreenState();
}

class _ReceivablesScreenState extends State<ReceivablesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  AccFeed? _feed;
  bool _loading = true;
  final _filter = AccDateFilter(preset: 'month');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final feed = await AccFeed.load();
    if (mounted) setState(() {
      _feed = feed;
      _loading = false;
    });
  }

  Widget _grandTotal(String label, int total) => Card(
        color: _softGreen(context),
        child: ListTile(
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          trailing: Text('${_expMoney(total)} ریال', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
      );

  Widget _salesTab(AccFeed feed) {
    final list = feed.sales.where((s) => _filter.matches(s.date)).toList();
    final byUser = <String, List<AccSale>>{};
    for (final s in list) {
      byUser.putIfAbsent(s.user, () => []).add(s);
    }
    final total = list.fold<int>(0, (s, e) => s + e.total);
    final users = byUser.keys.toList()..sort((a, b) => byUser[b]!.fold<int>(0, (s, e) => s + e.total).compareTo(byUser[a]!.fold<int>(0, (s, e) => s + e.total)));
    return ListView(
      padding: EdgeInsets.fromLTRB(14, 12, 14, 24 + MediaQuery.of(context).padding.bottom),
      children: [
        _grandTotal('جمع کل فروش (${_toPersianDigits('${list.length}')} فاکتور)', total),
        ...users.map((u) {
          final items = byUser[u]!..sort((a, b) => _expDateKey(b.date).compareTo(_expDateKey(a.date)));
          final sum = items.fold<int>(0, (s, e) => s + e.total);
          return Card(
            child: ExpansionTile(
              title: Text(u.isEmpty ? 'بدون نام' : u, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${_toPersianDigits('${items.length}')} فاکتور • ${_expMoney(sum)} ریال'),
              children: items
                  .map((s) => ListTile(dense: true, title: Text('فاکتور ${_toPersianDigits(s.invoice)}'), subtitle: Text(s.date), trailing: Text(_expMoney(s.total))))
                  .toList(),
            ),
          );
        }),
        if (list.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('فروشی در این بازه ثبت نشده است.'))),
      ],
    );
  }

  Widget _expensesTab(AccFeed feed) {
    final list = feed.expenses.where((s) => _filter.matches(s.date)).toList();
    final byUser = <String, List<AccExpense>>{};
    final byCat = <String, int>{};
    for (final e in list) {
      byUser.putIfAbsent(e.user, () => []).add(e);
      byCat[e.category] = (byCat[e.category] ?? 0) + e.amount;
    }
    final total = list.fold<int>(0, (s, e) => s + e.amount);
    final users = byUser.keys.toList()..sort();
    return ListView(
      padding: EdgeInsets.fromLTRB(14, 12, 14, 24 + MediaQuery.of(context).padding.bottom),
      children: [
        _grandTotal('جمع کل هزینه‌ها', total),
        if (byCat.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: byCat.entries
                  .map((e) => Chip(
                        label: Text('✨ ${e.key}: ${_expMoney(e.value)}', style: TextStyle(fontWeight: FontWeight.bold, color: _accAmber(context))),
                        side: BorderSide(color: Colors.amber.shade700),
                      ))
                  .toList(),
            ),
          ),
        ...users.map((u) {
          final items = byUser[u]!..sort((a, b) => _expDateKey(b.date).compareTo(_expDateKey(a.date)));
          final sum = items.fold<int>(0, (s, e) => s + e.amount);
          return Card(
            child: ExpansionTile(
              title: Text(u.isEmpty ? 'بدون نام' : u, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${_toPersianDigits('${items.length}')} مورد • ${_expMoney(sum)} ریال'),
              children: items
                  .map((e) => ListTile(dense: true, title: Text(e.name), subtitle: Text('${e.date} • ${e.paymentType} • ${e.category}'), trailing: Text(_expMoney(e.amount))))
                  .toList(),
            ),
          );
        }),
        if (list.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('هزینه‌ای در این بازه ثبت نشده است.'))),
      ],
    );
  }

  Widget _managerTab(AccFeed feed) {
    if (feed.managerEvents.isEmpty) return const Center(child: Text('گزارشی از مدیریت وجود ندارد.'));
    return ListView(
      padding: EdgeInsets.fromLTRB(14, 12, 14, 24 + MediaQuery.of(context).padding.bottom),
      children: feed.managerEvents.map((e) => Card(child: managerActivityTile(e))).toList(),
    );
  }

  Widget _deletionsTab(AccFeed feed) {
    if (feed.deletions.isEmpty) return const Center(child: Text('هیچ رویداد مالی حذف‌شده‌ای ثبت نشده است.'));
    return ListView(
      padding: EdgeInsets.fromLTRB(14, 12, 14, 24 + MediaQuery.of(context).padding.bottom),
      children: feed.deletions.map((e) => Card(child: deletionEventTile(e))).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('🧮 مطالبات و گزارش‌ها'),
          backgroundColor: const Color(0xFF185C3A),
          foregroundColor: Colors.white,
          actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
          bottom: TabBar(
            controller: _tabs,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.amberAccent,
            tabs: const [Tab(text: 'فروش صندوق‌داران'), Tab(text: 'هزینه‌ها'), Tab(text: 'مدیریت'), Tab(text: 'حذف‌ها')],
          ),
        ),
        body: _loading || feed == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 0), child: AccDateFilterBar(filter: _filter, onChanged: () => setState(() {}))),
                  Expanded(child: TabBarView(controller: _tabs, children: [_salesTab(feed), _expensesTab(feed), _managerTab(feed), _deletionsTab(feed)])),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------- نمایش در پنل مدیریت (گزارش عملکرد)

/// یک ردیف فعالیت مدیر (تغییر قیمت / عملیات چک).
Widget managerActivityTile(Map<String, dynamic> e) {
  final p = Map<String, dynamic>.from(e['payload'] ?? {});
  final user = p['user_name']?.toString().isNotEmpty == true ? p['user_name'].toString() : (e['actor_name']?.toString() ?? '');
  String money(dynamic v) => _expMoney(AccFeed._int(v));
  if (e['type']?.toString() == 'manager_cheque_action') {
    const acts = {'added': 'چک ثبت کرد', 'edited': 'چک را ویرایش کرد', 'deleted': 'چک را حذف کرد', 'status_changed': 'وضعیت چک را تغییر داد'};
    const st = {'pending': 'در انتظار', 'cleared': 'وصول‌شده', 'bounced': 'برگشت‌خورده'};
    return ListTile(
      leading: const Icon(Icons.request_quote_outlined, color: Colors.brown),
      title: Text('مدیر $user: ${acts[p['action']] ?? 'عملیات چک'}'),
      subtitle: Text('چک ${p['cheque_type'] == 'paid' ? 'پرداختی' : 'دریافتی'} • ${p['party'] ?? ''}\nمبلغ ${money(p['amount'])} ریال • سررسید ${p['due_date'] ?? ''}\nوضعیت: ${p['old_status'] != null ? '${st[p['old_status']] ?? ''} ← ' : ''}${st[p['status']] ?? p['status']}'),
      isThreeLine: true,
    );
  }
  return ListTile(
    leading: const Icon(Icons.price_change_outlined, color: Colors.orange),
    title: Text(p['product_name']?.toString() ?? 'کالا'),
    subtitle: Text('کاربر: $user\nقیمت: ${money(p['old_price'])} ← ${money(p['new_price'])} ریال'),
    isThreeLine: true,
  );
}

/// یک ردیف «حذف رویداد مالی» (فاکتور فروش/هزینه روزانه/بارنامه) با علت حذف.
Widget deletionEventTile(Map<String, dynamic> e) {
  final p = Map<String, dynamic>.from(e['payload'] ?? {});
  final user = p['user_name']?.toString().isNotEmpty == true ? p['user_name'].toString() : (e['actor_name']?.toString() ?? 'بدون نام');
  final role = p['user_role']?.toString() == 'manager' ? 'مدیر' : 'صندوق‌دار';
  const labels = {'invoice_deleted': 'حذف فاکتور فروش', 'expense_deleted': 'حذف هزینه روزانه', 'manifest_deleted': 'حذف بارنامه'};
  final action = p['action']?.toString() ?? '';
  final reason = (p['reason']?.toString().isNotEmpty ?? false) ? p['reason'].toString() : 'رویداد مالی حذف شد و در حسابداری ارسال نشد';
  final ref = p['reference']?.toString() ?? '';
  return ListTile(
    leading: const Icon(Icons.delete_forever, color: Colors.red),
    title: Text('$role $user: ${labels[action] ?? action}${ref.isNotEmpty ? ' ($ref)' : ''}'),
    subtitle: Text('علت: $reason${p['date'] != null ? '\n${p['date']}' : ''}'),
    isThreeLine: true,
  );
}

/// تب «حسابداری» در گزارش عملکرد پنل مدیریت.
class AccountingReportsTab extends StatefulWidget {
  final List<Map<String, dynamic>> reports;
  final List<Map<String, dynamic>> managerEvents;
  final Future<void> Function() onRefresh;
  const AccountingReportsTab({super.key, required this.reports, required this.managerEvents, required this.onRefresh});
  @override
  State<AccountingReportsTab> createState() => _AccountingReportsTabState();
}

class _AccountingReportsTabState extends State<AccountingReportsTab> {
  String _view = 'reports';

  void _showDetails(Map<String, dynamic> e) {
    final p = Map<String, dynamic>.from(e['payload'] ?? {});
    final type = p['report_type']?.toString();
    final lines = <Widget>[];
    if (type == 'payroll') {
      lines.addAll([
        Text('صندوق‌دار: ${p['cashier']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text('دوره: ${p['period']}'),
        const Divider(),
        Text('حقوق پایه: ${_expMoney(AccFeed._int(p['base_salary']))}'),
        Text('اضافات: ${_expMoney(AccFeed._int(p['additions']))}'),
        Text('کسورات: ${_expMoney(AccFeed._int(p['deductions']))}'),
        Text('هزینه‌های روزانه (${p['expense_mode'] == 'deduct' ? 'کسر' : 'اضافه'}): ${_expMoney(AccFeed._int(p['expenses_total']))}'),
        Text('خالص قابل پرداخت: ${_expMoney(AccFeed._int(p['net']))} ریال', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        if ((p['note'] ?? '').toString().isNotEmpty) Text('توضیحات: ${p['note']}'),
        const Divider(),
        const Text('جزئیات هزینه‌ها', style: TextStyle(fontWeight: FontWeight.bold)),
        ...((p['expenses'] as List?) ?? []).whereType<Map>().map((x) => ListTile(dense: true, title: Text('${x['name']}'), subtitle: Text('${x['date']} • ${x['payment']}'), trailing: Text(_expMoney(AccFeed._int(x['amount']))))),
      ]);
    } else {
      lines.addAll([
        Text('خریدار: ${p['customer']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text('تاریخ: ${p['date']}'),
        const Divider(),
        ...((p['items'] as List?) ?? []).whereType<Map>().map((x) => ListTile(dense: true, title: Text('${x['name']}'), subtitle: Text('${x['qty']} × ${_expMoney(AccFeed._int(x['price']))}'), trailing: Text(_expMoney(AccFeed._int(x['qty']) * AccFeed._int(x['price']))))),
        if (((p['costs'] as List?) ?? []).isNotEmpty) const Text('مخارج فروش', style: TextStyle(fontWeight: FontWeight.bold)),
        ...((p['costs'] as List?) ?? []).whereType<Map>().map((x) => ListTile(dense: true, title: Text('${x['title']}'), trailing: Text(_expMoney(AccFeed._int(x['amount']))))),
        const Divider(),
        Text('مبلغ نهایی: ${_expMoney(AccFeed._int(p['total']))} ریال', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        if ((p['note'] ?? '').toString().isNotEmpty) Text('توضیحات: ${p['note']}'),
      ]);
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (ctx, sc) => ListView(
          controller: sc,
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.of(ctx).padding.bottom),
          children: [Text(p['title']?.toString() ?? 'گزارش حسابداری', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), const SizedBox(height: 8), ...lines],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'reports', label: Text('گزارش‌های حسابداری')),
              ButtonSegment(value: 'managers', label: Text('فعالیت مدیران')),
            ],
            selected: {_view},
            onSelectionChanged: (v) => setState(() => _view = v.first),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: _view == 'managers'
                ? (widget.managerEvents.isEmpty
                    ? ListView(children: const [SizedBox(height: 120), Center(child: Text('فعالیتی ثبت نشده است.'))])
                    : ListView(padding: const EdgeInsets.all(12), children: widget.managerEvents.map((e) => Card(child: managerActivityTile(e))).toList()))
                : (widget.reports.isEmpty
                    ? ListView(children: const [SizedBox(height: 120), Center(child: Text('هنوز گزارشی از حسابداری دریافت نشده است.'))])
                    : ListView(
                        padding: const EdgeInsets.all(12),
                        children: widget.reports.map((e) {
                          final p = Map<String, dynamic>.from(e['payload'] ?? {});
                          final payroll = p['report_type'] == 'payroll';
                          return Card(
                            child: ListTile(
                              onTap: () => _showDetails(e),
                              leading: Icon(payroll ? Icons.payments_outlined : Icons.workspace_premium_outlined, color: payroll ? Colors.green : Colors.deepPurple),
                              title: Text(payroll ? 'حقوق و دستمزد: ${p['cashier']}' : (p['title']?.toString() ?? 'فاکتور ویژه')),
                              subtitle: Text(payroll ? '${p['period']} • خالص ${_expMoney(AccFeed._int(p['net']))} ریال' : '${p['customer']} • ${_expMoney(AccFeed._int(p['total']))} ریال'),
                              trailing: const Icon(Icons.chevron_left),
                            ),
                          );
                        }).toList(),
                      )),
          ),
        ),
      ],
    );
  }
}
