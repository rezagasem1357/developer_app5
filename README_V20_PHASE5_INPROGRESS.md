# v20 (phase 5) — در حال انجام (ناتمام)

## ✅ انجام‌شده
1. **علت حذف رویداد مالی**: `_promptFinancialDeleteReason` + `kDefaultDeleteReason` در main.dart.
   حذف فاکتور فروش (`_deleteInvoiceGroup`)، هزینه روزانه (`_deleteExpense`) و بارنامه (`_deleteManifest`)
   حالا قبل از حذف علت را می‌پرسند (خالی = متن پیش‌فرض) و با اکشن‌های
   `invoice_deleted` / `expense_deleted` / `manifest_deleted` به فید مشترک ارسال می‌شود.
   نمایش در «گزارش عملکرد ← صندوق‌داران» (main.dart، `PerformanceReportScreen`).
2. **تب «حذف‌ها» در پنل حسابداری** (accounting_panel.dart): `AccFeed.deletions`،
   `deletionEventTile`، تب چهارم در `ReceivablesScreen`.
3. **نام توسعه‌دهنده در صفحه اصلی**: فاصله از دکمه‌های اندروید بیشتر شد (خط ~7291 main.dart).
4. **دکمه ارسال دستی + ارسال خودکار بعد از ۳ ساعت** برای فاکتور فروش و هزینه روزانه:
   - فیلد `sent` (bool) به `SalesInvoice` و `DailyExpense` اضافه شد؛ `DailyExpense` فیلد
     `createdAtMs` هم دارد (SalesInvoice از فیلد قدیمی `createdAt` که رشته‌ی epoch-ms است استفاده می‌کند).
   - دیگر در لحظه ثبت، `_publishPerformanceEvent` صدا زده نمی‌شود.
   - دکمه سبز «ارسال» در لیست فاکتورها (`_sendInvoiceGroup`) و هزینه‌ها (`_sendExpense`).
   - `_autoSendDueFinancialEvents()` (نزدیک `_publishPerformanceEvent` در main.dart):
     از `initState` صدا زده می‌شود، با `Timer.periodic(Duration(minutes:15))` تکرار می‌شود،
     و در `didChangeAppLifecycleState` (resumed) هم صدا زده می‌شود.

## ⏳ هنوز باقی‌مانده
1. **ابزار حسابداری برای گزارش تغییر قیمت/کالای جدید به مدیر** — چیزی شبیه
   `_publishManagerPriceChange` (که فقط برای نقش مدیر است) باید در accounting_panel.dart
   برای نقش حسابداری ساخته شود؛ نوع رویداد پیشنهادی: `accounting_price_report`.
2. **حذف دائمی گزارش‌های عملکردی با سطل زباله ۳روزه**: `TrashScreen`/`TrashItem` فعلی
   فقط فاکتور/کالا/بارنامه را با انقضای ۷روزه پوشش می‌دهد (`_cleanupExpired` در
   `_TrashScreenState`، main.dart). باید یک سطل زباله جدا برای «گزارش‌های عملکردی»
   (رویدادهای فید `cashier_performance` / `accounting_report` / `manager_*`) با
   انقضای ۳روزه اضافه شود؛ چون این رویدادها روی سرور/فید مشترک هستند نه فقط
   SharedPreferences محلی، این کار به یک مکانیزم soft-delete در NetworkService نیاز دارد.
3. **حذف پیام‌های ارسالی** (ابزار «ارسال پیام به کاربران»): نیاز به دکمه حذف دائمی برای
   مدیر روی پیام‌های قبلی + تایمر خودکار ۴۸ساعته با سوییچ روشن/خاموش دستی. محل شروع:
   جستجوی `_openBroadcastMessagesScreen` و `broadcast_message` / `story_message` در main.dart.
4. **زیرساخت بروزرسانی اپ در تنظیمات** (در همه پنل‌ها: صندوق‌دار/مدیر/حسابداری).
5. **بازطراحی چیدمان** صفحه هزینه روزانه (`DailyExpensesScreen`) و صفحه ارسال پیام —
   فعلاً به‌خاطر خطوط اضافه‌شده وضعیت ارسال، ممکن است سطرهای متن کمی فشرده به‌نظر برسند؛
   این هم باید در فاز بازطراحی جمع‌وجور شود.

## نکات فنی برای ادامه
- کامپایل/تست در این محیط ممکن نبود (بدون Flutter SDK)؛ همه ویرایش‌ها با بازخوانی دقیق
  کد انجام شده و balance پرانتز/آکولاد چک شده، ولی حتماً قبل از انتشار روی دستگاه واقعی
  `flutter analyze` و build بگیرید.
- الگوی فید مشترک: `NetworkService.publishEvent(type: ..., actorName: ..., payload: {...})`
  و خواندن با `fetchRecentEvents`. تایپ‌های فعلی: `cashier_performance`, `manager_price_change`,
  `manager_cheque_action`, `accounting_report`.
