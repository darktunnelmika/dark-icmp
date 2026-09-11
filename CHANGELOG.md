# Changelog — DARK VPN · ICMP Pro

## [2.7.1] — رفع باگ

### 🐛 رفع شده
- **رفع کرش در speed_active** — تابع `regen_config` تعریف نشده بود و باعث کرش تست سرعت فعال می‌شد
- **رفع toggle debug log** — toggle بین `warn/debug` تغییر کرد تا `load_meta` آن را override نکند
- **رفع `tunnel_count`** — روی سیستم بدون تانل عدد `1` به جای `0` برمی‌گرداند
- **رفع `grep -P`** — جایگزینی با `awk` برای سازگاری با Alpine/BusyBox
- **رفع cleanup پورت temp** — اضافه شدن trap برای پاکسازی پورت موقت هنگام Ctrl+C در speed test
- **رفع `LOCAL_BIND` در port remap** — capture مقدار قبل از `resolve_port_clashes`
- **رفع `LOGLEVEL` در ایجاد تانل KHAREJ** — مقدار اولیه از `info` به `warn` تغییر کرد

---

## [2.7.0]

### ✨ جدید
- افزودن پروفایل‌های پرفورمنس: Stable، Balanced، Low Ping، Turbo، Custom
- افزودن تست سرعت فعال با speed responder روی KHAREJ
- افزودن نمایش fingerprint تنظیمات برای مقایسه دو طرف
- افزودن Link Test — تست پایداری در بازه زمانی دلخواه
- پشتیبانی از چندین تانل همزمان روی یک هاست با کلیدهای مجزا

### 🔧 بهبود
- بهبود تشخیص IP عمومی و تشخیص NAT
- بهبود مدیریت پورت‌های تداخل‌دار با رفع خودکار
- بهبود پیام‌های خطا با نمایش دلیل عدم اجرای سرویس
- بهبود sweep_partials برای پاکسازی تانل‌های ناقص

### 🐛 رفع شده
- رفع مشکل partial tunnel هنگام Ctrl+C در حین setup

---

## [2.6.x]

- پشتیبانی از رمزگذاری AES-256 و ChaCha20
- سیستم Pair Code v2 با پروفایل پرفورمنس
- داشبورد زنده با refresh خودکار
- تایمر ری‌استارت زمان‌بندی شده
