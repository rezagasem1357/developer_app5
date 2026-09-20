// نسخهٔ جایگزین (stub) برای پلتفرم‌های غیر وب (اندروید/آی‌او‌اس نیتیو).
// چون dart:html فقط روی وب در دسترس است، این فایل همان رابط را بدون
// وابستگی به مرورگر پیاده‌سازی می‌کند تا کامپایل نسخه موبایل خراب نشود.
class PwaInstallHelper {
  static bool get isWeb => false;
  static bool get isIOS => false;
  static bool get isStandalone => false;
  static bool get canPromptInstall => false;

  static Future<bool> promptInstall() async => false;
}
