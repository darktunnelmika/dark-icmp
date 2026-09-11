# Changelog — DARK VPN · ICMP Pro

## [2.8.0] — DARK NOC Integration

### ✨ جدید
- **DARK NOC Pair Code (N1)** — فرمت جدید `DICMP-N1-<BASE64URL>` برای یکپارچگی با DARK NOC Hub
- **گزینه DARK NOC در منوی KHAREJ** — `[2] DARK NOC` برای paste کردن NOC Pair Code از Hub
- **`parse_noc_pair_code`** — parser امن با اعتبارسنجی کامل field-by-field؛ هرگز `eval`/`source` نمی‌کند
- **`screen_noc_kharej`** — صفحه deploy خودکار KHAREJ بدون سوال اضافه؛ فقط Summary + تأیید Deploy
- **rollback خودکار** — اگر سرویس fail شد، tunnel، firewall و service پاک می‌شوند
- **امنیت کامل** — Pair Code یا ENC_KEY هرگز در journal چاپ نمی‌شود
- **Backward compatible** — Pair Code قدیمی `DICMP-...` بدون تغییر باقی ماند

### 🔒 امنیت N1
- Base64URL (RFC 4648 §5) — بدون padding، URL-safe
- هر فیلد جداگانه validate می‌شود: نام، IP، کلید، رمزگذاری، پروفایل، پورت‌ها
- ports_csv فقط کاراکترهای مجاز دارد — injection غیرممکن
- pairing_id باید دقیقاً 16 hex char باشد

---

## [2.7.1] — رفع باگ

### 🐛 رفع شده
- **رفع کرش در speed_active** — تابع `regen_config` تعریف نشده بود
- **رفع toggle debug log** — toggle بین `warn/debug` تغییر کرد
- **رفع `tunnel_count`** — روی سیستم بدون تانل عدد اشتباه برمی‌گرداند
- **رفع `grep -P`** — جایگزینی با `awk` برای سازگاری با Alpine/BusyBox
- **رفع cleanup پورت temp** — trap برای پاکسازی هنگام Ctrl+C
- **رفع `LOCAL_BIND` در port remap**
- **رفع `LOGLEVEL` در ایجاد تانل KHAREJ**

---

## [2.7.0]

### ✨ جدید
- پروفایل‌های پرفورمنس: Stable، Balanced، Low Ping، Turbo، Custom
- تست سرعت فعال با speed responder
- بهبود تشخیص IP و NAT
- پشتیبانی از چندین تانل همزمان

---

## [2.6.x]
- رمزگذاری AES-256 و ChaCha20
- سیستم Pair Code v2
- داشبورد زنده
- تایمر ری‌استارت
