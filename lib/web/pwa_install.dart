// dart.library.js_interop فقط وقتی true است که کامپایل برای وب (js یا wasm)
// انجام می‌شود؛ این پایدارتر از dart.library.html است چون dart:html در حال
// حذف شدن از Dart SDK است، ولی dart:js_interop کتابخانه‌ی رسمی و پایدار وب است.
export 'pwa_install_stub.dart' if (dart.library.js_interop) 'pwa_install_web.dart';
