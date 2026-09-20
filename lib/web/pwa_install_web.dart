// نسخهٔ وب: با توابع جاوااسکریپت ساده‌ای که در web/index.html تعریف شده‌اند
// صحبت می‌کند تا میانبر PWA نصب شود.
//
// توجه مهم: از dart:js_interop استفاده می‌شود، نه dart:js_util/dart:html که
// در نسخه‌های جدید Dart SDK (۳.۱۱ به بعد) کاملاً حذف شده‌اند. برای اینکه این
// فایل ساده و کم‌ریسک بماند، تمام منطق پیچیده (خواندن userAgent، property های
// آبجکت رویداد beforeinstallprompt و ...) در همان جاوااسکریپت ساده‌ی
// index.html انجام می‌شود؛ اینجا فقط چند مقدار boolean ساده رد و بدل می‌شود.
//
// توجه: سافاری روی آی‌فون هیچ‌وقت رویداد beforeinstallprompt را نمی‌فرستد،
// بنابراین برای آن فقط می‌توان کاربر را راهنمایی کرد (منوی Share > Add to
// Home Screen)؛ نصب خودکار/برنامه‌ای در آی‌او‌اس ممکن نیست.
import 'dart:js_interop';

@JS('pwaCanPrompt')
external bool _pwaCanPrompt();

@JS('pwaTriggerInstall')
external JSPromise<JSBoolean> _pwaTriggerInstall();

@JS('pwaIsStandalone')
external bool _pwaIsStandalone();

@JS('pwaIsIOS')
external bool _pwaIsIOS();

class PwaInstallHelper {
  static bool get isWeb => true;

  static bool get isIOS {
    try {
      return _pwaIsIOS();
    } catch (_) {
      return false;
    }
  }

  static bool get isStandalone {
    try {
      return _pwaIsStandalone();
    } catch (_) {
      return false;
    }
  }

  static bool get canPromptInstall {
    try {
      return _pwaCanPrompt();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> promptInstall() async {
    try {
      final result = await _pwaTriggerInstall().toDart;
      return result.toDart;
    } catch (_) {
      return false;
    }
  }
}
