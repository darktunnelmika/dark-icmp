# راهنمای نصب کامل — DARK VPN · ICMP Pro

## پیش‌نیازها

- دو سرور Linux با دسترسی root
- سرور KHAREJ: IP عمومی، ICMP باز (ping)
- سرور IRAN: ارتباط با KHAREJ از طریق ICMP

---

## مرحله ۱ — دانلود اسکریپت (هر دو سرور)

```bash
wget https://raw.githubusercontent.com/mikakhadm/dark-icmp/main/dark-icmppro.sh
chmod +x dark-icmppro.sh
sudo ./dark-icmppro.sh
```

یا نصب به عنوان دستور سیستمی:
```bash
sudo install -m 0755 dark-icmppro.sh /usr/local/bin/icmppro
```

---

## مرحله ۲ — نصب هسته pingtunnel (هر دو سرور)

پس از اجرای اسکریپت:
```
[1] Core → [1] From GitHub
```
اسکریپت آخرین نسخه را دانلود و نصب می‌کند.

---

## مرحله ۳ — تنظیم KHAREJ (سرور خارج)

```
[2] New tunnel - KHAREJ
```

| سوال | توضیح | مثال |
|------|-------|-------|
| tunnel name | نام دلخواه | `mypanel` |
| public ip | IP عمومی سرور KHAREJ | `1.2.3.4` |
| service ports | پورت پنل روی KHAREJ | `8000,443` |
| tunnel key | کلید عددی منحصربه‌فرد | `10010` |
| encryption | نوع رمزگذاری | AES-128 |
| profile | پروفایل پرفورمنس | Balanced |

پس از ایجاد، **Pair Code** نمایش داده می‌شود — آن را کپی کنید.

---

## مرحله ۴ — تنظیم IRAN (سرور داخل)

```
[3] New tunnel - IRAN
```

| سوال | توضیح |
|------|-------|
| tunnel name | نام دلخواه (می‌تواند همان KHAREJ باشد) |
| pair code | کدی که از KHAREJ کپی کردید |
| local bind | `0.0.0.0` (پیشنهادی) |

---

## مرحله ۵ — تأیید اتصال

```
[6] Diagnostics → [3] Health Check
```

یا:
```
[6] Diagnostics → [4] ICMP Quality
```

---

## تنظیم فایروال سرور KHAREJ

اگر از فایروال ابری (AWS/GCP/Hetzner/...) استفاده می‌کنید:

- پروتکل **ICMP** را در Security Group / Firewall Rule فعال کنید
- نیازی به باز کردن پورت TCP/UDP خاصی نیست

```bash
# بررسی ICMP از سرور IRAN
ping -c 4 <KHAREJ-IP>
```

---

## غیرفعال کردن ping سیستمی (اختیاری)

روی سرور KHAREJ برای بهبود عملکرد:

```bash
echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_all
```

برای دائمی شدن:
```bash
echo "net.ipv4.icmp_echo_ignore_all = 1" >> /etc/sysctl.conf
sysctl -p
```

> ⚠️ بعد از این دستور ping به KHAREJ پاسخ نمی‌دهد ولی تانل ICMP کار می‌کند.

---

## آپدیت

```
[7] Update → [2] Update script
```

ابتدا آدرس منبع را تنظیم کنید:
```
[7] Update → [3] Set source url
```
آدرس: `https://raw.githubusercontent.com/mikakhadm/dark-icmp/main/dark-icmppro.sh`

---

## حذف کامل

```
[8] Uninstall
```

تمام تانل‌ها، سرویس‌ها، قوانین فایروال و فایل‌های باینری حذف می‌شوند.
