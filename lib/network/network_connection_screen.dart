import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'network_service.dart';

class NetworkConnectionScreen extends StatefulWidget {
  final VoidCallback? onManageImportantEvents;

  const NetworkConnectionScreen({super.key, this.onManageImportantEvents});

  @override
  State<NetworkConnectionScreen> createState() => _NetworkConnectionScreenState();
}

class _NetworkConnectionScreenState extends State<NetworkConnectionScreen> {
  static const _defaultUrl = 'https://vgxuktkybwhkfalmvere.supabase.co';
  static const _defaultPublishableKey = 'sb_publishable_y99r6TzKy8OZ8eZgHRMZog_V1pixHFQ';
  final _service = NetworkService();
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _storeCtrl = TextEditingController(text: 'store-1');
  bool _autoSync = true;
  String _role = 'cashier';
  bool _loading = false;
  bool _online = false;
  int _pending = 0;
  DateTime? _lastSync;
  String _status = 'برای شروع، تنظیمات سرور را وارد کنید.';
  String _license = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await _service.loadConfig();
    final p = await _service.pendingCount();
    final last = await _service.lastSync();
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('app_role') == 'manager' ? 'manager' : 'cashier';
    if (!mounted) return;
    setState(() {
      _role = role;
      _urlCtrl.text = c.baseUrl.isEmpty ? _defaultUrl : c.baseUrl;
      _keyCtrl.text = c.anonKey.isEmpty ? _defaultPublishableKey : c.anonKey;
      _storeCtrl.text = c.storeId;
      _autoSync = c.autoSync;
      _pending = p;
      _lastSync = last;
      _license = c.license;
    });
    await _refreshStatus();
    if (_autoSync) _startAutoSync();
  }

  void _startAutoSync() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted) return;
      await _sync();
    });
  }

  Future<void> _refreshStatus() async {
    final online = await _service.isOnline();
    if (mounted) setState(() => _online = online);
  }

  Future<void> _saveSettings() async {
    await _service.saveConfig(
      baseUrl: _urlCtrl.text,
      anonKey: _keyCtrl.text,
      storeId: _storeCtrl.text,
      role: _role,
      autoSync: _autoSync,
    );
    if (_autoSync) {
      _startAutoSync();
    } else {
      _timer?.cancel();
    }
  }

  bool _checkLicense() {
    if (_license.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لایسنس این دستگاه یافت نشد. ابتدا باید از صفحه ورود با لایسنس معتبر وارد شوید.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _test() async {
    if (!_checkLicense()) return;
    setState(() {
      _loading = true;
      _status = 'در حال آزمایش اتصال...';
    });
    await _saveSettings();
    final result = await _service.testConnection();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _status = result.message;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _sync() async {
    if (_loading) return;
    if (!_checkLicense()) return;
    await _saveSettings();
    final result = await _service.syncOutbox();
    final p = await _service.pendingCount();
    final last = await _service.lastSync();
    if (!mounted) return;
    setState(() {
      _pending = p;
      _lastSync = last;
      _status = result.message;
    });
  }

  Future<void> _downloadProductDatabase() async {
    if (!_checkLicense()) return;
    setState(() {
      _loading = true;
      _status = 'در حال دریافت بانک اطلاعاتی...';
    });
    await _saveSettings();
    final snapshot = await _service.downloadSnapshot();
    if (!mounted) return;
    setState(() => _loading = false);
    if (snapshot == null) {
      setState(() => _status = 'بانک اطلاعاتی مرکزی پیدا نشد یا اتصال برقرار نشد.');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final products = snapshot['product_database'];
    if (products is List) {
      await prefs.setString('product_database', jsonEncode(products));
    }
    final expenses = snapshot['daily_expenses'];
    if (expenses is List && _role == 'manager') {
      await prefs.setString('daily_expenses', jsonEncode(expenses));
    }
    final customEvents = snapshot['custom_events'];
    if (customEvents is List) {
      await prefs.setString('custom_events', jsonEncode(customEvents));
    }
    final inventoryDate = snapshot['fixed_inventory_last_date_v2']?.toString();
    final cleaningDate = snapshot['fixed_cleaning_last_date_v1']?.toString();
    if (inventoryDate != null && inventoryDate.isNotEmpty) await prefs.setString('fixed_inventory_last_date_v2', inventoryDate);
    if (cleaningDate != null && cleaningDate.isNotEmpty) await prefs.setString('fixed_cleaning_last_date_v1', cleaningDate);
    final info = await _service.fetchSnapshotInfo();
    if (info != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('database_update_seen_at', info.updatedAt);
      await prefs.setString('manager_message_read_id', 'database_update:${info.updatedAt}');
    }
    final last = await _service.lastSync();
    setState(() {
      _lastSync = last;
      _status = 'بانک اطلاعاتی از سرور دریافت و روی دستگاه ذخیره شد.';
    });
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('توجه'),
        content: const Text('نرم‌افزار برای بروزرسانی اطلاعات باید ریستارت شود.'),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              SystemNavigator.pop();
            },
            child: const Text('باشه'),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadProductDatabase() async {
    if (_role != 'manager') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ارسال بانک اطلاعاتی فقط برای مدیریت مجاز است.')));
      return;
    }
    if (!_checkLicense()) return;
    setState(() {
      _loading = true;
      _status = 'در حال ارسال بانک اطلاعاتی...';
    });
    await _saveSettings();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('product_database') ?? '[]';

    // انتخاب «کالای جدید» کاملاً دستی است؛ ارسال بانک نباید ستاره کالاها را تغییر دهد.
    List<dynamic> products = [];
    try {
      products = jsonDecode(raw) as List<dynamic>;
    } catch (_) {}
    for (final rawItem in products) {
      if (rawItem is Map) {
        rawItem['newProductBankAppearances'] = 0;
        rawItem['isNewProduct'] = rawItem['isNewProduct'] == true;
      }
    }
    await prefs.setString('product_database', jsonEncode(products));

    final dailyExpensesRaw = prefs.getString('daily_expenses') ?? '[]';
    final customEventsRaw = prefs.getString('custom_events') ?? '[]';
    List<dynamic> dailyExpenses = [];
    List<dynamic> customEvents = [];
    try { dailyExpenses = jsonDecode(dailyExpensesRaw) as List<dynamic>; } catch (_) {}
    try { customEvents = jsonDecode(customEventsRaw) as List<dynamic>; } catch (_) {}
    final result = await _service.uploadSnapshot({
      'product_database': products,
      'daily_expenses': dailyExpenses,
      'custom_events': customEvents,
      'fixed_inventory_last_date_v2': prefs.getString('fixed_inventory_last_date_v2'),
      'fixed_cleaning_last_date_v1': prefs.getString('fixed_cleaning_last_date_v1'),
    }, actorName: _storeCtrl.text);
    final last = await _service.lastSync();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _lastSync = last;
      _status = result.message;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _storeCtrl.dispose();
    super.dispose();
  }

  Widget _card({required Widget child}) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.06),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ارتباط با شبکه'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: _online ? Colors.green.shade100 : Colors.red.shade100,
                  child: Icon(
                    _online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                    color: _online ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_online ? 'اینترنت متصل است' : 'اینترنت در دسترس نیست', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(_status, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('بانک اطلاعاتی', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('مدیر می‌تواند نسخه مرکزی بانک کالا را منتشر کند و صندوق‌داران آن را دریافت کنند.'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _downloadProductDatabase,
                    icon: const Icon(Icons.cloud_download_outlined, size: 28, color: Colors.amber),
                    label: const Text('دریافت بروزرسانی بانک', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade700,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                if (_role == 'manager') ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _uploadProductDatabase,
                      icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: const Text('ارسال بانک اطلاعاتی'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(150, 40)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _card(
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: _license.isEmpty ? Colors.orange.shade100 : Colors.blue.shade100,
                  child: Icon(
                    Icons.verified_user_outlined,
                    color: _license.isEmpty ? Colors.orange : Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('لایسنس این دستگاه', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        _license.isEmpty ? 'یافت نشد — از صفحه ورود وارد شوید.' : _license,
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'فقط دستگاه‌هایی با همین لایسنس با هم همگام‌سازی می‌شوند.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('تنظیمات اتصال', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(controller: _urlCtrl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'آدرس Supabase', hintText: 'https://xxxx.supabase.co', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: _keyCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Publishable / Anon Key', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: _storeCtrl, decoration: const InputDecoration(labelText: 'شناسه فروشگاه', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.admin_panel_settings_outlined, color: Colors.green),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_role == 'manager' ? 'این نسخه در حالت مدیریت است و دسترسی ارسال بانک اطلاعاتی دارد.' : 'این نسخه در حالت صندوق‌دار است؛ دریافت بانک مجاز است اما ارسال بانک فقط برای مدیریت فعال است.')),
                    ],
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('همگام‌سازی خودکار'),
                  subtitle: const Text('هر ۳۰ ثانیه هنگام باز بودن برنامه بررسی می‌شود.'),
                  value: _autoSync,
                  onChanged: (v) => setState(() => _autoSync = v),
                ),
                Row(
                  children: [
                    Expanded(child: OutlinedButton.icon(onPressed: _loading ? null : _test, icon: const Icon(Icons.wifi_find), label: const Text('تست اتصال'))),
                    const SizedBox(width: 10),
                    Expanded(child: ElevatedButton.icon(onPressed: _loading ? null : _sync, icon: const Icon(Icons.sync), label: const Text('همگام‌سازی'))),
                  ],
                ),
              ],
            ),
          ),
          if (_role == 'manager' && widget.onManageImportantEvents != null)
            _card(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_note_outlined, color: Colors.deepOrange),
                title: const Text('مدیریت رویدادهای مهم روزشمار', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('ویرایش انبارگردانی، نظافت و رویدادهای روزشمار مشترک'),
                trailing: const Icon(Icons.arrow_back_ios_new, size: 18),
                onTap: widget.onManageImportantEvents,
              ),
            ),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('صف ارسال: $_pending مورد', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(_lastSync == null ? 'آخرین همگام‌سازی: هنوز انجام نشده' : 'آخرین همگام‌سازی: ${_lastSync!.toLocal()}'),
                const SizedBox(height: 10),
                const Text('این معماری برای حالت آفلاین هم طراحی شده است؛ اطلاعات ابتدا روی دستگاه ذخیره می‌شوند و بعد از اتصال ارسال خواهند شد.', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
          if (_loading) const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}
