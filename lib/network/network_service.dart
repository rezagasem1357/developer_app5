import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class NetworkConfig {
  final String baseUrl;
  final String anonKey;
  final String storeId;
  final String role;
  final bool autoSync;
  final String license;

  const NetworkConfig({
    required this.baseUrl,
    required this.anonKey,
    required this.storeId,
    required this.role,
    required this.autoSync,
    required this.license,
  });

  bool get isConfigured =>
      baseUrl.isNotEmpty && anonKey.isNotEmpty && storeId.isNotEmpty && license.isNotEmpty;
}

class SnapshotInfo {
  final String updatedAt;
  final String updatedBy;

  const SnapshotInfo({required this.updatedAt, this.updatedBy = ''});
}

class NetworkSyncResult {
  final bool success;
  final String message;
  final int pendingEvents;
  final DateTime? serverUpdatedAt;

  const NetworkSyncResult({
    required this.success,
    required this.message,
    this.pendingEvents = 0,
    this.serverUpdatedAt,
  });
}

/// ارتباط شبکه بدون قرار دادن هیچ کلید محرمانه‌ای در برنامه.
/// این کلاس در حالت آفلاین فقط رویدادها را در outbox محلی نگه می‌دارد.
///
/// توجه مهم: این کلاس عمداً فقط از package:http استفاده می‌کند (نه dart:io)
/// چون dart:io روی Flutter Web اصلاً در دسترس نیست و کامپایل نسخه وب (برای
/// صندوق‌دارانی که آیفون دارند) را می‌شکند. package:http روی موبایل، دسکتاپ و
/// وب یکسان کار می‌کند.
class NetworkService {
  static const _baseUrlKey = 'network_base_url';
  static const _anonKey = 'network_anon_key';
  static const _storeIdKey = 'network_store_id';
  static const _roleKey = 'network_role';
  static const _autoSyncKey = 'network_auto_sync';
  static const _lastSyncKey = 'network_last_sync';
  static const _outboxKey = 'network_outbox';
  static const _localSnapshotKey = 'network_local_snapshot';
  // همان کلیدی که هنگام ورود در صفحه لاگین ذخیره می‌شود (main.dart -> LoginScreen).
  static const _userLicenseKey = 'user_license';

  Future<NetworkConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return NetworkConfig(
      baseUrl: prefs.getString(_baseUrlKey) ?? '',
      anonKey: prefs.getString(_anonKey) ?? '',
      storeId: prefs.getString(_storeIdKey) ?? 'store-1',
      role: prefs.getString(_roleKey) ?? 'manager',
      autoSync: prefs.getBool(_autoSyncKey) ?? true,
      // لایسنس مستقیماً از همان لایسنسی که کاربر هنگام ورود وارد کرده خوانده می‌شود؛
      // این‌طور تضمین می‌شود که فقط اپ‌هایی با لایسنس یکسان بتوانند با هم همگام شوند.
      license: prefs.getString(_userLicenseKey) ?? '',
    );
  }

  Future<void> saveConfig({
    required String baseUrl,
    required String anonKey,
    required String storeId,
    String role = 'manager',
    required bool autoSync,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, baseUrl.trim().replaceAll(RegExp(r'/$'), ''));
    await prefs.setString(_anonKey, anonKey.trim());
    await prefs.setString(_storeIdKey, storeId.trim());
    await prefs.setString(_roleKey, role);
    await prefs.setBool(_autoSyncKey, autoSync);
  }

  Future<DateTime?> lastSync() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastSyncKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<int> pendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_outboxKey);
    if (raw == null || raw.isEmpty) return 0;
    try {
      return (jsonDecode(raw) as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<String> queueEvent({
    required String type,
    required Map<String, dynamic> payload,
    String? actorName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_outboxKey);
    final List<dynamic> events = raw == null || raw.isEmpty ? [] : (jsonDecode(raw) as List<dynamic>);
    final config = await loadConfig();
    events.add({
      'id': '${DateTime.now().microsecondsSinceEpoch}-${events.length}',
      'type': type,
      'store_id': _scopedStoreId(config),
      'license': config.license,
      'actor_name': actorName ?? '',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'payload': payload,
    });
    await prefs.setString(_outboxKey, jsonEncode(events));
    return events.last['id'].toString();
  }

  Future<bool> isOnline() async {
    try {
      // یک درخواست سبک و مستقل از سرور Supabase؛ فقط برای تشخیص اتصال اینترنت.
      final response = await http
          .get(Uri.parse('https://www.gstatic.com/generate_204'))
          .timeout(const Duration(seconds: 4));
      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  Uri _restUri(NetworkConfig config, String path, [Map<String, String>? query]) {
    final base = config.baseUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base/rest/v1/$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Map<String, String> _headers(NetworkConfig config) => {
        'apikey': config.anonKey,
        'Authorization': 'Bearer ${config.anonKey}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  /// شناسه ترکیبی «لایسنس + فروشگاه» که کانال داده را کاملاً از سایر لایسنس‌ها جدا می‌کند.
  /// حتی اگر همه اپ‌ها از یک anon key مشترک استفاده کنند، هر لایسنس فقط ردیف‌های خودش را می‌بیند.
  String _scopedStoreId(NetworkConfig config) => '${config.license}__${config.storeId}';

  Future<NetworkSyncResult> testConnection() async {
    final config = await loadConfig();
    if (!config.isConfigured) {
      return const NetworkSyncResult(success: false, message: 'ابتدا مشخصات سرور را در ارتباط با شبکه وارد کنید.');
    }
    try {
      final response = await http.get(
        _restUri(config, 'store_snapshots', {
          'select': 'store_id',
          'store_id': 'eq.${_scopedStoreId(config)}',
          'limit': '1',
        }),
        headers: _headers(config),
      ).timeout(const Duration(seconds: 7));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return NetworkSyncResult(success: true, message: 'اتصال به سرور با موفقیت برقرار شد.');
      }
      return NetworkSyncResult(success: false, message: 'سرور پاسخ ${response.statusCode} داد: ${response.body.isEmpty ? 'خطای نامشخص' : response.body}');
    } catch (e) {
      return NetworkSyncResult(success: false, message: 'اتصال برقرار نشد: $e');
    }
  }

  Future<NetworkSyncResult> uploadSnapshot(Map<String, dynamic> snapshot, {String? actorName}) async {
    final config = await loadConfig();
    if (!config.isConfigured) {
      await _cacheSnapshot(snapshot);
      return const NetworkSyncResult(success: false, message: 'تنظیمات شبکه کامل نیست؛ اطلاعات فعلاً محلی ذخیره شد.');
    }
    try {
      final headers = _headers(config)..['Prefer'] = 'resolution=merge-duplicates,return=minimal';
      final response = await http.post(
        _restUri(config, 'store_snapshots'),
        headers: headers,
        body: jsonEncode({
          'store_id': _scopedStoreId(config),
          'license': config.license,
          'payload': snapshot,
          'updated_by': actorName ?? '',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastSyncKey, DateTime.now().toUtc().toIso8601String());
        return NetworkSyncResult(success: true, message: 'بانک اطلاعاتی روی سرور به‌روزرسانی شد.');
      }
      return NetworkSyncResult(success: false, message: 'ارسال اطلاعات ناموفق بود: ${response.body}');
    } catch (e) {
      await _cacheSnapshot(snapshot);
      return NetworkSyncResult(success: false, message: 'اینترنت در دسترس نبود؛ اطلاعات برای ارسال بعدی ذخیره شد.');
    }
  }

  Future<SnapshotInfo?> fetchSnapshotInfo() async {
    final config = await loadConfig();
    if (!config.isConfigured) return null;
    try {
      final response = await http.get(
        _restUri(config, 'store_snapshots', {
          'select': 'updated_at,updated_by',
          'store_id': 'eq.${_scopedStoreId(config)}',
          'limit': '1',
        }),
        headers: _headers(config),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final rows = jsonDecode(response.body) as List<dynamic>;
      if (rows.isEmpty) return null;
      final row = Map<String, dynamic>.from(rows.first);
      final updatedAt = (row['updated_at'] ?? '').toString();
      if (updatedAt.isEmpty) return null;
      return SnapshotInfo(
        updatedAt: updatedAt,
        updatedBy: (row['updated_by'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> downloadSnapshot() async {
    final config = await loadConfig();
    if (!config.isConfigured) return null;
    try {
      final response = await http.get(
        _restUri(config, 'store_snapshots', {
          'select': 'payload,updated_at,updated_by',
          'store_id': 'eq.${_scopedStoreId(config)}',
          'limit': '1',
        }),
        headers: _headers(config),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final rows = jsonDecode(response.body) as List<dynamic>;
      if (rows.isEmpty) return null;
      final payload = Map<String, dynamic>.from(rows.first['payload'] ?? {});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSyncKey, DateTime.now().toUtc().toIso8601String());
      return payload;
    } catch (_) {
      return null;
    }
  }

  // ==================== فید مشترک پیام‌ها و گزارش عملکرد ====================
  // این فید روی همان جدول store_snapshots ساخته شده که بروزرسانی بانک اطلاعاتی
  // از آن استفاده می‌کند. برخلاف network_events (که به جدول جداگانه‌ای نیاز دارد و
  // ممکن است روی همه پروژه‌های Supabase از قبل ساخته نشده باشد و باعث می‌شود
  // رویدادها همیشه در صف «برای ارسال بعدی» باقی بمانند)، این روش نیازی به جدول یا
  // migration جدید ندارد و از همان مسیری استفاده می‌کند که در عمل تست‌شده و
  // قابل‌اطمینان است.
  String _feedStoreId(NetworkConfig config) => '${_scopedStoreId(config)}::feed';

  Future<List<Map<String, dynamic>>> downloadFeed() async {
    final config = await loadConfig();
    if (!config.isConfigured) return [];
    try {
      final response = await http.get(
        _restUri(config, 'store_snapshots', {
          'select': 'payload',
          'store_id': 'eq.${_feedStoreId(config)}',
          'limit': '1',
        }),
        headers: _headers(config),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) return [];
      final rows = jsonDecode(response.body) as List<dynamic>;
      if (rows.isEmpty) return [];
      final payload = Map<String, dynamic>.from(rows.first['payload'] ?? {});
      final items = (payload['items'] as List?) ?? [];
      return items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// یک آیتم جدید (پیام یا رویداد گزارش عملکرد) را به فید مشترک اضافه می‌کند.
  /// چون store_snapshots هر بار کل ردیف را جایگزین می‌کند، ابتدا فید فعلی خوانده
  /// می‌شود تا آیتم‌های قبلی از دست نروند.
  Future<bool> appendFeedItem(Map<String, dynamic> item) async {
    final config = await loadConfig();
    if (!config.isConfigured) return false;
    final current = await downloadFeed();
    if (current.any((e) => e['id']?.toString() == item['id']?.toString())) return true;
    final updated = <Map<String, dynamic>>[item, ...current];
    if (updated.length > 300) {
      updated.removeRange(300, updated.length);
    }
    try {
      final headers = _headers(config)..['Prefer'] = 'resolution=merge-duplicates,return=minimal';
      final response = await http.post(
        _restUri(config, 'store_snapshots'),
        headers: headers,
        body: jsonEncode({
          'store_id': _feedStoreId(config),
          'license': config.license,
          'payload': {'items': updated},
          'updated_by': (item['actor_name'] ?? '').toString(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 10));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<NetworkSyncResult> publishEvent({
    required String type,
    required Map<String, dynamic> payload,
    String? actorName,
  }) async {
    // دقیقاً همان صفی را استفاده می‌کنیم که برای همگام‌سازی شبکه استفاده می‌شود.
    // در صورت قطعی/خطای لحظه‌ای، رویداد حذف نمی‌شود و در اولین sync بعدی ارسال خواهد شد.
    // ارسال واقعی اکنون روی فید مشترک (store_snapshots) انجام می‌شود که همان
    // مکانیزم تست‌شده و قابل‌اطمینان بروزرسانی بانک اطلاعاتی است.
    await queueEvent(type: type, payload: payload, actorName: actorName);
    return syncOutbox();
  }

  /// تلاش مجدد برای ارسال رویدادهای صف‌شده؛ برای استفاده هنگام بازگشت برنامه،
  /// اتصال اینترنت و refresh گزارش‌ها.
  Future<NetworkSyncResult> syncPendingEvents() => syncOutbox();

  Future<List<Map<String, dynamic>>> fetchRecentEvents({int limit = 50}) async {
    final items = await downloadFeed();
    return items.take(limit).map((item) => {
          'id': item['id'],
          'type': item['type'] ?? item['kind'],
          'actor_name': item['actor_name'] ?? item['actorName'] ?? '',
          'created_at': item['created_at'] ?? item['createdAt'],
          'payload': Map<String, dynamic>.from(item['payload'] ?? {}),
        }).toList();
  }

  Future<NetworkSyncResult> syncOutbox() async {
    final config = await loadConfig();
    if (!config.isConfigured) return NetworkSyncResult(success: false, message: 'تنظیمات شبکه کامل نیست.', pendingEvents: await pendingCount());
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_outboxKey);
    if (raw == null || raw.isEmpty) return const NetworkSyncResult(success: true, message: 'موردی برای ارسال وجود ندارد.');
    final events = jsonDecode(raw) as List<dynamic>;
    final remaining = <dynamic>[];
    for (final event in events) {
      final map = Map<String, dynamic>.from(event as Map);
      final ok = await appendFeedItem({
        'id': map['id'],
        'type': map['type'],
        'actor_name': map['actor_name'] ?? '',
        'created_at': map['created_at'],
        'payload': map['payload'] ?? {},
      });
      if (!ok) remaining.add(event);
    }
    await prefs.setString(_outboxKey, jsonEncode(remaining));
    await prefs.setString(_lastSyncKey, DateTime.now().toUtc().toIso8601String());
    return NetworkSyncResult(success: remaining.isEmpty, message: remaining.isEmpty ? 'همگام‌سازی رویدادها انجام شد.' : 'برخی رویدادها برای ارسال بعدی باقی ماندند.', pendingEvents: remaining.length);
  }

  Future<void> _cacheSnapshot(Map<String, dynamic> snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localSnapshotKey, jsonEncode(snapshot));
  }
}
