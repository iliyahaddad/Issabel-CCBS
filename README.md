# Issabel CCBS — Call Completion on Busy Subscriber

**Version 1.2.0**

افزونه‌ای سبک برای **Issabel / Asterisk** که قابلیت **CCBS (Call Completion on Busy Subscriber)** را برای تماس‌های **داخلی** فعال می‌کند: وقتی داخلی مقصد مشغول است، به تماس‌گیرنده پیشنهاد می‌شود با فشردن عدد `1` درخواست «تماس پس از آزاد شدن» ثبت کند.

> **رفتار دقیق:** فقط با فشردن `1` درخواست ثبت می‌شود. در غیر این صورت هیچ CCBS ای ثبت نمی‌شود و Issabel مثل قبل رفتار می‌کند (بوق مشغول / Voicemail).

## ⚠️ پیش‌نیاز مهم: chan_sip

CCSS در Asterisk فقط برای **chan_sip** (و ISDN/DAHDI) پیاده‌سازی شده و **برای PJSIP وجود ندارد**. اگر داخلی‌های شما PJSIP هستند این افزونه کار نخواهد کرد و نصاب آن را نصب نمی‌کند. (جزئیات: `docs/COMPATIBILITY.md`)

## سناریو

```text
101 ---> 102 (Busy)
          └─ پیام فارسی + «برای تماس پس از آزاد شدن، عدد 1 را فشار دهید»
               ├─ غیر از 1  → پیام «ثبت نشد» → رفتار عادی Issabel (بوق/Voicemail)
               └─ 1         → CallCompletionRequest()
                                └─ 102 آزاد می‌شود → Asterisk به 101 زنگ می‌زند
                                      └─ 101 جواب می‌دهد → 102 زنگ می‌خورد → تماس برقرار
```

CCBS استاندارد Asterisk به معنی Bridge خودکار بدون پاسخ هیچ‌کدام از گوشی‌ها نیست؛ ابتدا caller recall می‌شود و پس از پاسخ او، مقصد. اگر Bridge کاملاً خودکار لازم دارید باید سرویس جداگانهٔ AMI/ARI نوشت (در `docs/ARCHITECTURE.md` توضیح داده شده).

## تغییرات مهم نسبت به 1.1

- تنظیمات CCSS اکنون در **`sip_general_custom.conf`** نوشته می‌شود؛ در نسخه‌های قبل در `ccss.conf` بود که Asterisk آن گزینه‌ها را آنجا نادیده می‌گیرد.
- Hook فقط **priority 1** از `s-BUSY` را می‌گیرد؛ Voicemail-on-busy و بوق مشغول سالم می‌مانند.
- فقط وقتی caller **داخلی ثبت‌شدهٔ Issabel** باشد پیشنهاد داده می‌شود (تماس‌های Trunk دیگر Answer نمی‌شوند).
- `issabel-ccbs.conf` واقعاً اعمال می‌شود.
- حالت `--check`، ابزار `issabel-ccbs-ctl`، kill-switch، rollback، تست نصاب. فهرست کامل در `CHANGELOG.md`.

## ساختار

```text
issabel-ccbs/
├── install.sh  uninstall.sh  VERSION  CHANGELOG.md  RELEASE.md  LICENSE
├── lib/ccbs-common.sh                 توابع مشترک (بدون Python)
├── etc/asterisk/
│   ├── ccbs-dialplan.conf.in          قالب Dialplan
│   ├── ccbs-sip.conf.in               قالب سیاست‌های CC برای chan_sip
│   ├── ccbs-custom.conf.in            قالب کد لغو دستی (اختیاری)
│   ├── issabel-ccbs.conf.example      تنظیمات محلی
│   └── ccss.conf.example              فقط توضیح (نصاب به ccss.conf دست نمی‌زند)
├── sounds/ccbs-*.wav   prompts/fa-IR/
├── scripts/normalize-prompts.sh  scripts/rollback.sh
├── usr/local/sbin/issabel-ccbs-check  issabel-ccbs-ctl
├── tests/static_test.sh  tests/install_test.sh  tests/fakebin/asterisk
└── docs/ARCHITECTURE.md COMPATIBILITY.md TEST-PLAN.md TROUBLESHOOTING.md
```

## پیش‌نیازها

- Issabel با دسترسی root و Asterisk 11 به بالا
- ماژول‌های `chan_sip` و `res_ccss`
- `sip.conf` شامل `#include sip_general_custom.conf` (استاندارد در Issabel)
- `callcounter=yes` (استاندارد؛ نصاب در صورت نبود هشدار می‌دهد)
- فقط bash/awk/coreutils — **Python لازم نیست**. SoX فقط برای تبدیل Promptهای خودتان.

## نصب

```bash
unzip issabel-ccbs-1_2_0.zip && cd issabel-ccbs
sudo bash install.sh --check     # فقط بررسی؛ هیچ تغییری نمی‌دهد
sudo bash install.sh
```

نصاب: preflight (chan_sip، res_ccss، includeها، وجود `s-BUSY`، فرمت Promptها، زمان‌بندی) ← Backup ← پاک‌سازی بلاک‌های قدیمی 1.0/1.1 ← رندر قالب‌ها بر اساس تنظیمات ← نصب Prompt ← `sip reload` و `dialplan reload` ← تأیید ← Health-check. اجرای مجدد بی‌خطر است. تنظیمات نامعتبر یا PJSIP-only باعث توقف بدون تغییر فایل‌ها می‌شود.

## فایل‌های تغییر‌یافته

| فایل | محتوا |
|---|---|
| `/etc/asterisk/sip_general_custom.conf` | بلاک مدیریت‌شده: `cc_agent_policy=generic`، `cc_monitor_policy=generic`، timerها، `cc_callback_sub` |
| `/etc/asterisk/extensions_override_issabelpbx.conf` (یا `..._freepbx.conf`) | Hook روی `s-BUSY`، context `ccbs-offer`، `ccbs-callback` |
| `/etc/asterisk/extensions_custom.conf` | فقط اگر `manual_cancel_enabled=1` |
| `/var/lib/asterisk/sounds/custom/ccbs/fa/` | `busy offer accepted cancelled failed` |
| `/opt/issabel-ccbs/`، `/usr/local/sbin/issabel-ccbs-{check,ctl}` | ابزارها |
| `/var/backups/issabel-ccbs/<timestamp>/` | Backup + `s-BUSY.before.txt` |

بلاک‌ها با `; ===== ISSABEL-CCBS BEGIN/END =====` مشخص شده‌اند؛ داخل آن‌ها دستی ویرایش نکنید.

## تنظیمات

`/etc/asterisk/issabel-ccbs.conf` را ویرایش و سپس `install.sh` را دوباره اجرا کنید.

```ini
[general]
prompt_root=custom/ccbs/fa     ; مسیر Prompt نسبت به /var/lib/asterisk/sounds
accept_digit=1
input_timeout=7
require_local_device=1         ; فقط به داخلی‌های ثبت‌شده پیشنهاد بده
offer_timer=30                 ; باید از (busy+offer+input_timeout) بلندتر باشد
ccbs_available_timer=3600
ccnr_available_timer=3600
cc_recall_timer=20
cc_max_monitors=5
manual_cancel_enabled=0        ; آزمایشی
manual_cancel_code=*31
```

## مدیریت روزمره

```bash
issabel-ccbs-ctl status        # فعال/غیرفعال + درخواست‌های در انتظار
issabel-ccbs-ctl disable       # توقف فوری پیشنهاد CCBS (بدون Reload)
issabel-ccbs-ctl enable
issabel-ccbs-ctl list          # = asterisk -rx 'cc report status'
issabel-ccbs-ctl cancel all    # یا شناسه
issabel-ccbs-check             # Health-check کامل؛ exit code = تعداد FAIL
```

برای مانیتورینگ، با هر درخواست یک رویداد AMI به نام `CCBSRequest` (Caller / Callee / Result / Reason) ارسال می‌شود.

## Promptهای فارسی

پنج Prompt (busy، offer، accepted، cancelled، failed) در `prompts/fa-IR/prompts.txt` متن دارند. برای کیفیت Production توسط گوینده حرفه‌ای ضبط کنید و با `scripts/normalize-prompts.sh` (SoX) به WAV PCM 16-bit / mono / 8 kHz تبدیل کنید؛ جزئیات در `prompts/fa-IR/README.md`.

## تست

```bash
bash tests/static_test.sh      # syntax، قالب‌ها، فرمت WAV، جلوگیری از بازگشت باگ‌های قبلی
bash tests/install_test.sh     # نصب/ارتقا/idempotency/Uninstall در Sandbox با stub
```

این تست‌ها Asterisk و گوشی واقعی را شبیه‌سازی **نمی‌کنند**. تست عملی روی staging: `docs/TEST-PLAN.md`.

## حذف و Rollback

```bash
sudo bash uninstall.sh                          # همهٔ بلاک‌ها، Promptها و ابزارها؛ Backupها و issabel-ccbs.conf می‌مانند
sudo bash scripts/rollback.sh [BACKUP_DIR]      # بازگرداندن فایل‌های پیکربندی از Backup آخر
```

## محدودیت‌ها

- فقط chan_sip، فقط داخلی‌ها (Generic agent/monitor). هر caller فقط یک درخواست فعال دارد.
- درخواست‌ها فقط در حافظهٔ Asterisk نگهداری می‌شوند؛ با Restart از بین می‌روند.
- Recall مستقیم روی دستگاه (`SIP/101`) انجام می‌شود و قابلیت‌های Issabel مثل Follow-Me روی آن مسیر اعمال نمی‌شود.
- ساختار دقیق `macro-dial-one` بین نسخه‌های Issabel فرق می‌کند؛ نصاب وضعیت قبلی را در `s-BUSY.before.txt` ذخیره و در صورت ناهمخوانی هشدار می‌دهد.
- Asterisk 21+ دیگر chan_sip و Macro ندارد؛ این پروژه آنجا کاربرد ندارد.

## License

GPL-3.0 یا بالاتر.
