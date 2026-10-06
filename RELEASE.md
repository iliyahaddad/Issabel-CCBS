# Issabel CCBS 1.2.0 Release

## هدف
نسخهٔ 1.2 یک نسخهٔ «اصلاح و سخت‌سازی» است: مهم‌ترین باگ‌های نسخه‌های قبل (محل اشتباه تنظیمات CCSS، ادعای پشتیبانی PJSIP، جایگزینی کامل شاخهٔ Busy و Answer شدن تماس‌های Trunk) رفع شده است.

## قبل از ارتقا
1. از `/etc/asterisk` بک‌آپ کامل بگیرید (نصاب هم خودکار بک‌آپ می‌گیرد).
2. `sudo bash install.sh --check` را اجرا کنید؛ هیچ تغییری نمی‌دهد.
3. سیستم باید **chan_sip** داشته باشد. روی PJSIP-only، CCSS در Asterisk پیاده‌سازی نشده است.

## ارتقا از 1.0 / 1.1
نصاب بلاک‌های قدیمی را پاک می‌کند، تنظیمات را در `sip_general_custom.conf` می‌نویسد، Hook را جایگزین می‌کند و Promptهای قدیمی را به Backup می‌برد. اجرای دوباره‌ی `install.sh` بی‌خطر (idempotent) است.

## توصیه قبل از Production
1. با دو داخلی آزمایشی Busy / Accept / Decline / Cancel را تست کنید (docs/TEST-PLAN.md).
2. `issabel-ccbs-check` باید بدون FAIL باشد.
3. در صورت مشکل: `issabel-ccbs-ctl disable` (فوری، بدون Reload) یا `scripts/rollback.sh`.

## محدودیت‌ها
- تست End-to-End واقعی با گوشی SIP در محیط build ممکن نبود. تست‌های static و تست نصاب در Sandbox (با stub برای Asterisk) انجام شده‌اند؛ رفتار واقعی CCSS و ساختار `macro-dial-one` در Issabel شما باید روی staging تأیید شود.
- فقط `chan_sip`، فقط داخلی‌ها (Generic agent/monitor).
