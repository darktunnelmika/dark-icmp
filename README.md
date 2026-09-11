<div align="center">

```
██████╗  █████╗ ██████╗ ██╗  ██╗
██╔══██╗██╔══██╗██╔══██╗██║ ██╔╝
██║  ██║███████║██████╔╝█████╔╝ 
██║  ██║██╔══██║██╔══██╗██╔═██╗ 
██████╔╝██║  ██║██║  ██║██║  ██╗
╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝
```

# DARK VPN · ICMP Pro

**TCP/UDP over ICMP Tunnel Manager**

[![Version](https://img.shields.io/badge/version-2.7.1-blue.svg)](https://github.com/darktunnelmika/dark-icmp)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-5.0%2B-orange.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux-lightgrey.svg)](https://www.linux.org/)

> اسکریپت مدیریت تانل ICMP بر پایه [pingtunnel](https://github.com/esrrhs/pingtunnel)  
> پشتیبانی: [@mikakhadm](https://t.me/mikakhadm)

</div>

---

## ✨ ویژگی‌ها

- 🔒 **رمزگذاری** — پشتیبانی از AES-128، AES-256 و ChaCha20
- 🔑 **Pair Code** — راه‌اندازی آسان با کد یکتا بین KHAREJ و IRAN
- 📊 **داشبورد زنده** — نمایش وضعیت، ترافیک و آپتایم تانل‌ها
- 🚀 **پروفایل پرفورمنس** — Stable، Balanced، Low Ping، Turbo
- 🔧 **دیاگنوستیک کامل** — تست کیفیت ICMP، لتنسی، throughput
- 🔄 **ری‌استارت خودکار** — تایمر زمان‌بندی شده برای پایداری
- 🛡️ **مدیریت فایروال** — قوانین iptables خودکار
- 🏗️ **چندتانل** — اجرای همزمان چندین تانل با کلیدهای مجزا

---

## 📋 پیش‌نیازها

| نرم‌افزار | توضیح |
|-----------|-------|
| Linux | Ubuntu، Debian، CentOS، AlmaLinux، Alpine |
| Bash 5.0+ | اکثر توزیع‌های مدرن |
| root | دسترسی root لازم است |
| curl / unzip | برای نصب هسته pingtunnel |
| iptables | مدیریت فایروال |
| systemd | مدیریت سرویس |

---

## ⚡ نصب سریع

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/darktunnelmika/dark-icmp/main/dark-icmppro.sh)
```

یا دانلود مستقیم:

```bash
wget https://raw.githubusercontent.com/darktunnelmika/dark-icmp/main/dark-icmppro.sh
chmod +x dark-icmppro.sh
sudo ./dark-icmppro.sh
```

نصب به عنوان دستور سیستمی:
```bash
sudo install -m 0755 dark-icmppro.sh /usr/local/bin/icmppro
icmppro
```

---

## 🗺️ معماری

```
  [ کاربر ]
      │
      ▼ TCP/UDP
  [ IRAN Server ]  ══════ ICMP ══════▶  [ KHAREJ Server ]
  (pingtunnel client)                   (pingtunnel server)
  پورت لوکال باز می‌کنه                  پنل / سرویس اینجاست
```

**KHAREJ** = سرور خارج از کشور — هسته pingtunnel به عنوان server اجرا می‌شود  
**IRAN** = سرور داخل کشور — هسته pingtunnel به عنوان client اجرا می‌شود

---

## 🚀 راه‌اندازی

### مرحله ۱ — نصب هسته (هر دو سرور)

از منوی اصلی گزینه `[1] Core` را انتخاب کنید تا آخرین نسخه pingtunnel از GitHub دانلود و نصب شود.

### مرحله ۲ — ایجاد تانل روی KHAREJ

```
منوی اصلی ← [2] New tunnel - KHAREJ
```

1. نام تانل را وارد کنید
2. IP عمومی سرور KHAREJ تأیید کنید
3. پورت‌های سرویس (مثلاً پنل) را وارد کنید
4. کلید احراز هویت را انتخاب کنید
5. رمزگذاری را انتخاب کنید
6. **Pair Code** را کپی کنید

### مرحله ۳ — ایجاد تانل روی IRAN

```
منوی اصلی ← [3] New tunnel - IRAN
```

1. نام تانل را وارد کنید
2. **Pair Code** از KHAREJ را paste کنید
3. Local Bind را انتخاب کنید (`0.0.0.0` پیشنهادی)
4. تانل به صورت خودکار شروع می‌شود

---

## 📁 ساختار فایل‌ها

```
/etc/dark-icmppro/
├── tunnels/
│   └── <tunnel-name>/
│       ├── meta.conf       ← تنظیمات تانل (chmod 600)
│       ├── ports.list      ← لیست پورت‌های forward
│       └── pair.code       ← Pair Code (فقط KHAREJ)
└── core.version            ← نسخه pingtunnel نصب شده

/usr/local/bin/
├── pingtunnel              ← باینری اصلی
├── darkicmp-runner         ← اسکریپت اجرای تانل
└── darkicmp-fw             ← مدیریت فایروال

/etc/systemd/system/
├── darkicmp@.service       ← سرویس systemd (template)
├── darkicmp-restart@.service
└── darkicmp-restart@.timer
```

---

## 🔐 پروفایل‌های پرفورمنس

| پروفایل | TCP Buffer | Max Window | Resend | کاربرد |
|---------|-----------|------------|--------|---------|
| **Stable** | 512K | 10000 | 600ms | مسیرهای پر-loss |
| **Balanced** | 1M | 20000 | 400ms | پیشنهادی |
| **Low Ping** | 512K | 12000 | 200ms | گیمینگ / تعاملی |
| **Turbo** | 2M | 40000 | 300ms | throughput بالا |
| **Custom** | دستی | دستی | دستی | تنظیم شخصی |

---

## 🛠️ منوی مدیریت

```
MAIN MENU
├── [1] Core                 ← نصب / آپدیت pingtunnel
├── [2] New tunnel - KHAREJ  ← ایجاد سرور ICMP
├── [3] New tunnel - IRAN    ← ایجاد کلاینت ICMP
├── [4] Manage tunnels       ← مدیریت تانل‌های موجود
│   ├── Start / Stop / Restart
│   ├── Forward Ports
│   ├── Security (auth + encryption)
│   ├── Endpoint + Bind
│   ├── Performance Profile
│   └── Speed Test
├── [5] Dashboard            ← نمایش زنده همه تانل‌ها
├── [6] Diagnostics
│   ├── Live Log
│   ├── Health Check
│   ├── ICMP Quality
│   ├── Link Test
│   ├── Speed + Latency
│   └── Config Fingerprint
└── [7] Update
```

---

## 🔒 امنیت

- تمام فایل‌های تنظیمات با `chmod 600` محافظت می‌شوند
- کلید رمزگذاری در Pair Code رمزنگاری می‌شود (Base64)
- هر تانل کلید احراز هویت مجزا دارد (integer 0–2147483647)
- رمزگذاری end-to-end: AES-128 / AES-256 / ChaCha20

---

## 📊 تست سرعت

### تست لتنسی (IRAN)
```
Manage → Speed Test → Latency
```
اتصال TCP واقعی از طریق تانل — نیازی به نصب چیزی نیست.

### تست throughput فعال
```
KHAREJ: Diagnostics → Speed responder
IRAN:   Manage → Speed Test → Active throughput
```

---

## ❓ رفع مشکل

**سرویس بالا نمی‌آید:**
```bash
journalctl -u darkicmp@<name> -n 50 --no-pager
```

**بررسی سلامت کلی:**
```
Diagnostics → Health Check
```

**تست مسیر ICMP:**
```
Diagnostics → ICMP Quality
```

**تعمیر سرویس:**
```
Manage → Repair
```

---

## 📝 Changelog

### v2.7.1
- 🐛 رفع باگ `regen_config` تعریف‌نشده در speed_active (کرش)
- 🐛 رفع toggle debug log (بین `warn/debug` نه `info/debug`)
- 🐛 رفع `tunnel_count` روی سیستم بدون تانل
- 🐛 رفع `grep -P` برای سازگاری با Alpine/BusyBox
- 🐛 رفع cleanup پورت temp هنگام Ctrl+C در speed test
- 🐛 رفع `LOCAL_BIND` در port remap
- 🐛 رفع `LOGLEVEL` در ایجاد تانل KHAREJ

### v2.7.0
- افزودن پروفایل‌های پرفورمنس (Stable, Balanced, Low Ping, Turbo)
- افزودن تست سرعت فعال با speed responder
- بهبود تشخیص IP و NAT
- پشتیبانی از چندین تانل همزمان روی یک هاست

---

## 📄 لایسنس

MIT License — آزاد برای استفاده شخصی و تجاری

---

<div align="center">

ساخته شده با ❤️ توسط [@mikakhadm](https://t.me/mikakhadm)

</div>
