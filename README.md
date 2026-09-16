<div dir="rtl">

# 🌊 GoldWaterTunnel

> **تانل ضد فیلتر چندلایه بر پایه‌ی [WaterWall](https://github.com/radkesvat/WaterWall)** — WireGuard + Reality v2 + Connection Fisher + Fake-DNS + VLESS داخلی، با واتچ‌داگ خودترمیم، دستور تست یک‌ضربه‌ای و نصب یک‌خطی روی سرور داخل ایران و سرور خارج.

[![WaterWall](https://img.shields.io/badge/Engine-WaterWall%20v1.46.9-blue)](https://github.com/radkesvat/WaterWall)
[![Release](https://img.shields.io/badge/Release-v1.0.0-green)](https://github.com/DashSaman/GoldWaterTunnel/releases)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## فهرست

1. [این پروژه چیست؟](#این-پروژه-چیست)
2. [معماری تانل — توضیح کامل لایه‌به‌لایه](#معماری-تانل--توضیح-کامل-لایهبه-لایه)
3. [چرا ضد فیلتر است؟ (واکنش به حمله‌های DPI)](#چرا-ضد-فیلتر-است)
4. [پیش‌نیازها](#پیش‌نیازها)
5. [نصب دقیق — قدم‌به‌قدم](#نصب-دقیق--قدمبه-قدم)
6. [اتصال به پنل x-ui / 3x-ui](#اتصال-به-پنل-x-ui--3x-ui)
7. [تست و پایش پایداری](#تست-و-پایش-پایداری)
8. [واتچ‌داگ (نگهبان خودترمیم)](#واتچ‌داگ-نگهبان-خودترمیم)
9. [مدیریت روزمره و تغییر تنظیمات](#مدیریت-روزمره-و-تغییر-تنظیمات)
10. [مسیریابی خروجی ایران (اختیاری)](#مسیریابی-خروجی-ایران-اختیاری)
11. [عملکرد و ظرفیت (اندازه‌گیری‌شده)](#عملکرد-و-ظرفیت-اندازهگیری‌شده)
12. [عیب‌یابی](#عیب‌یابی)
13. [سوالات متداول](#سوالات-متداول)
14. [امنیت](#امنیت)
15. [اعتبارها و مجوز](#اعتبارها-و-مجوز)

---

## این پروژه چیست؟

GoldWaterTunnel بین دو سرور شما یک **کانال رمزنگاری‌شده‌ی مقاوم در برابر تشخیص عمیق بسته (DPI)** می‌سازد:

- **سرور ایران** (نقش client): پنل Xray/x-ui شما اینجاست. یک نقطه‌ی WireGuard لوکال (`127.0.0.1:51820`) باز می‌شود که خروجی وایرگارد پنل به آن وصل می‌شود.
- **سرور خارج** (نقش server): روی یک پورت TCP (پیشنهاد 443) گوش می‌دهد و ترافیک را با IP خودش به اینترنت آزاد می‌رساند.

هر اینباند پنل که به outbound تگ‌شده‌ی `waterwall-wg` هدایت شود از این کانال عبور می‌کند. نتایج استقرار مرجع (ایران↔هتزنر):

| متریک | مقدار |
|---|---|
| پهنای‌باند داخل تانل | ~۴۶ Mbit/s (دانلود Cloudflare) |
| پهنای‌باند مستقیم سرور خارج | ~۴۰۹ Mbit/s |
| اتصال‌های همزمان | ۲۰/۲۰ موفق |
| بازیابی خودکار بعد از قطعی کامل | ~۸۰ ثانیه |
| مصرف WaterWall | ~۳۰–۵۰MB رم، <۱٪ CPU |

---

## معماری تانل — توضیح کامل لایه‌به‌لایه

```
┌──────────────────────────── سرور ایران (نقش client) ────────────────────────────┐
│                                                                                  │
│   کاربران ──▶ اینباند پنل (VMess/VLESS/Trojan/...) ──▶ Routing پنل              │
│                         │                                                        │
│                         ▼                                                        │
│        ┌─ خروجی wireguard پنل Xray (tag: waterwall-wg) ─────────────┐           │
│        │   پروتکل WireGuard استاندارد روی 127.0.0.1:51820 (UDP)     │           │
│        └──────────────────────┬────────────────────────────────────┘           │
│                               ▼                                                  │
│   ① UdpStatelessSocket — سوکت UDP بی‌حالت؛ هر peer یک خط (line) مستقل            │
│                               ▼                                                  │
│   ② WireGuardDevice — پیاده‌سازی کامل WireGuard (هندشیک Noise، rekey، roaming)  │
│      بسته‌های IP رمزگشایی‌شده را به لایه بعد می‌دهد                               │
│                               ▼                                                  │
│   ③ PacketsToConnection — پشته TCP/IP سبک lwIP داخل پروسه:                      │
│      بسته‌های IP را به جریان‌های TCP/UDP واقعی بازسازی می‌کند                      │
│      + ④ Fake-DNS: سرور DNS داخل حافظه (198.18.0.2) — پاسخ فوری بدون            │
│        رفت‌وبرگشت؛ نگاشت دامنه‌ها به IPهای موقت 100.64.0.0/10                     │
│                               ▼                                                  │
│   ⑤ VlessClient — مقصدِ هر جریان (دامنه/IP/پورت) را داخل هدر رمز‌شده              │
│      تانل حمل می‌کند (بدون این لایه سرور خارج مقصد را نمی‌داند)                   │
│                               ▼                                                  │
│   ⑥ ConnectionFisherClient — برای هر اتصال، ۲ اتصال TCP موازی می‌سازد؛           │
│      اولین که «گواه سلامت» برگرداند نگه داشته و بقیه بسته می‌شوند                 │
│                               ▼                                                  │
│   ⑦ RealityClient — هندشیک TLS 1.3 *واقعی* با دامنه‌ی پوششی                      │
│      (مثل www.microsoft.com)؛ سپس کلیدهای نشست مشتق و داده‌ها در                  │
│      رکوردهای کاملاً شبیه TLS با AEAD رمز می‌شوند                                 │
│                               ▼                                                  │
│   ⑧ TcpConnector → اینترنت ایران (ترجیحاً از WAN تمیز)                           │
└───────────────────────────────────┼──────────────────────────────────────────────┘
                                    │  TCP:443 — از بیرون: HTTPS عادی
┌───────────────────────────────────┼──────────────────────────────────────────────┐
│  سرور خارج (نقش server)           ▼                                              │
│   ⑨ TcpListener روی 0.0.0.0:443                                                  │
│                               ▼                                                  │
│   ⑩ RealityServer — هندشیک بریج‌شده به سایتِ واقعیِ پوشش؛ فقط بعد از              │
│      احراز هویت رمزی، اتصال به مسیر محافظت‌شده می‌رود؛ ناشناس‌ها به سایت          │
│      پوشش پروکسی می‌شوند (کاموفلاژ کامل برای اسکنرها)                             │
│                               ▼                                                  │
│   ⑪ ConnectionFisherServer — پاسخ‌دهی مسابقه‌ی اتصال‌ها                           │
│                               ▼                                                  │
│   ⑫ VlessServer — هدر مقصد را باز می‌کند                                         │
│                               ▼                                                  │
│   ⑬ TcpUdpConnector — اتصال مستقیم به مقصد نهایی (resolve سالم در خارج)         │
│                               ▼                                                  │
│                        اینترنت آزاد 🌍 (خروج با IP سرور خارج)                    │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### سفر یک درخواست (مثال واقعی)

1. کاربر `youtube.com` را می‌خواهد → اینباند پنل → قانون Routing → `waterwall-wg`
2. Xray پنل DNS را از `198.18.0.2` می‌پرسد؛ این پرسش از خود تانل عبور می‌کند و **Fake-DNS داخل همان پروسه** فوراً یک IP موقت (100.64.x.x) می‌دهد و دامنه را در حافظه نگه می‌دارد
3. Xray به آن IP وصل می‌شود؛ بسته‌های IP وارد WireGuard می‌شوند (رمزنگاری Noise)
4. lwIP بسته‌ها را به جریان TCP واقعی تبدیل می‌کند؛ مقصد جریان از نگاشت Fake-DNS به «youtube.com» برمی‌گردد
5. VlessClient مقصد را داخل تانل رمز می‌کند؛ Fisher دو اتصال موازی می‌سازد؛ RealityClient روی هر دو TLSِ واقعی با سایت پوشش انجام می‌دهد و بعد داده‌ها را AEAD می‌کند
6. سرور خارج: احراز Reality → مسابقه Fisher → بازکردن هدر VLESS → اتصال به youtube.com با DNS سالم → پاسخ از همان مسیر برمی‌گردد

نام دامنه و محتوا هیچ‌جا به‌صورت آشکار روی سیم نیست و کل مسیر ایران↔خارج از بیرون یک TLS معمولی به یک IP است.

---

## چرا ضد فیلتر است؟

| حمله‌ی DPI | واکنش این تانل |
|---|---|
| **بازرسی منفعل** (تحلیل الگوی بسته) | ترافیک TCP:443 با SNI دامنه‌ی پوششی؛ رکوردها از نظر اندازه/نوع/رفتار بستن، پروفایل TLS واقعی همان سایت را بازتولید می‌کنند (Reality v2) |
| **اسکن فعال** (وصل‌شدن خود DPI به سرور) | اتصال ناشناس به سایتِ پوششیِ واقعی پروکسی می‌شود و گواهی معتبر همان سایت را می‌گیرد؛ هیچ سرویس bare یا امضای نامعتبر دیده نمی‌شود |
| **تزریق RST** (کشتن بعضی اتصال‌ها) | ConnectionFisher همزمان ۲ اتصال می‌سازد و اولین سالم را نگه می‌دارد — کشته‌شدن یکی، درخواست کاربر را نمی‌کشد |
| **فیلتر IP مقصد** | رفتار پورت، وب‌سرور عادی است؛ با `--port` و `--cover` به‌سرعت تغییر شکل می‌دهد |
| **DNS Leak / DNS دستکاری‌شده** | DNS کاملاً داخل تانل و حافظه پاسخ داده می‌شود؛ resolve نهایی با DNS سالم سرور خارج |
| **قطعی/کرش** | systemd با `Restart=always` + واتچ‌داگ سه‌مرحله‌ای با تأیید قطعی واقعی و ری‌استارت ریموت |

---

## پیش‌نیازها

| مورد | سرور خارج | سرور ایران |
|---|---|---|
| سیستم‌عامل | Ubuntu 20.04+ / Debian 11+ (x86_64) | همان |
| دسترسی | root | root |
| پورت | یک TCP آزاد (پیشنهاد: 443) | — |
| پنل | — | x-ui یا 3x-ui (اختیاری ولی هدف اصلی) |

> سرور ایران به GitHub وصل نمی‌شود؟ [نصب آفلاین](#نصب-آفلاین) را ببینید.

---

## نصب دقیق — قدم‌به‌قدم

### مرحله ۱ — سرور خارج

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/DashSaman/GoldWaterTunnel/main/install.sh) \
     server --port 443 --cover www.microsoft.com
```

در پایان، دو مقدار را یادداشت کنید:

```
============================================================
 GoldWaterTunnel SERVER installed successfully
============================================================
 Listen port : TCP 443
 Reality pass: Xk7...        ← رمز Reality (برای کلاینت لازم)
     VLESS id: a1b2c3d4-...  ← UUID (برای کلاینت لازم)
 Cover domain: www.microsoft.com
```

- رمز/UUID دلخواه: `--password 'My$tr0ngPass' --uuid $(cat /proc/sys/kernel/random/uuid)`
- پورت اشغال است؟ `--port 8443` (در مرحله ۲ هم همان را بدهید)
- فایروال: `ufw allow 443/tcp`

### مرحله ۲ — سرور ایران

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/DashSaman/GoldWaterTunnel/main/install.sh) \
     client \
     --server <IP-سرور-خارج> \
     --port 443 \
     --password <رمز-Reality-از-مرحله-۱> \
     --uuid <UUID-از-مرحله-۱> \
     --cover www.microsoft.com
```

نصاب خودش: باینری WaterWall را نصب می‌کند ← کلیدهای WireGuard می‌سازد ← زنجیره را در `/etc/goldwater/` می‌نویسد ← سرویس‌های `waterwall` و `goldwater-watchdog` را فعال می‌کند ← sysctl را بهینه می‌کند ← **تست end-to-end** اجرا می‌کند:

```
[✓] End-to-end OK — exit IP: <IP-سرور-خارج>
```

و در پایان `/etc/goldwater/xray-outbound.json` (خروجی وایرگارد پنل) و کلید عمومی واتچ‌داگ را چاپ می‌کند.

اگر `End-to-end probe returned nothing` گرفتید → [عیب‌یابی](#عیب‌یابی).

### مرحله ۳ — ری‌استارت ریموت برای واتچ‌داگ (توصیه‌شده)

کلید عمومی واتچ‌داگ (که نصاب ایران چاپ کرد) را روی **سرور خارج** اضافه کنید:

```bash
mkdir -p /root/.ssh && chmod 700 /root/.ssh
echo 'command="/usr/local/bin/goldwater-remote-restart",no-pty,no-X11-forwarding <کلید-عمومی>' >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
```

این کلید به‌دلیل forced-command فقط می‌تواند `restart` بزند — نه شل، نه چیز دیگر.

### مرحله ۴ — پنل

به بخش [اتصال به پنل](#اتصال-به-پنل-x-ui--3x-ui) بروید. تمام!

### نصب آفلاین

```bash
# روی سرور خارج (یا هرجای آزاد):
curl -fL -o /tmp/ww.zip https://github.com/radkesvat/WaterWall/releases/download/v1.46.9/Waterwall-linux-gcc-x64.zip
unzip -o /tmp/ww.zip -d /tmp/wwrel
# فایل /tmp/wwrel/Waterwall را با scp به سرور ایران ببرید، سپس روی ایران:
GWT_LOCAL_BIN=/root/waterwall.prebuilt bash install.sh client --server ... --password ... --uuid ...
```

---

## اتصال به پنل x-ui / 3x-ui

### ۱) افزودن خروجی وایرگارد

**پنل ← Xray Configs ← بخش Outbounds ← افزودن** و محتوای `/etc/goldwater/xray-outbound.json` را بگذارید:

```json
{
  "tag": "waterwall-wg",
  "protocol": "wireguard",
  "settings": {
    "secretKey": "<کلید-خصوصی-تولیدشده>",
    "address": ["10.44.0.2/32"],
    "peers": [
      { "publicKey": "<کلید-عمومی-تانل>", "endpoint": "127.0.0.1:51820", "keepAlive": 25 }
    ],
    "mtu": 1420,
    "kernelMode": false
  }
}
```

(مقادیر واقعی در همان فایل روی سرور ایران هستند — اینجا فقط شکل کانفیگ است.)

### ۲) هدایت اینباند به تانل

در **Routing** پنل قانونی بسازید که اینباند دلخواه را به `waterwall-wg` بدهد:

```json
{ "type": "field", "inboundTag": ["نام-اینباند"], "outboundTag": "waterwall-wg" }
```

از همان لحظه، ترافیک آن اینباند با IP سرور خارج به اینترنت می‌رسد. چند اینباند را می‌توانید در یک قانون بدهید.

### ۳) DNS بدون نشتی (توصیه‌شده)

در بخش DNS پنل:

```json
{ "servers": ["198.18.0.2"], "queryStrategy": "UseIPv4" }
```

و این قانون را **اولِ لیست Routing** بگذارید:

```json
{ "type": "field", "ip": ["198.18.0.2/32"], "outboundTag": "waterwall-wg" }
```

نتیجه: resolve دامنه‌ها داخل تانل، با پاسخ فوریِ Fake-DNS داخلی — نه DNS Leak، نه دامنه‌ی اشتباه.

---

## تست و پایش پایداری

### تست یک‌ضربه‌ای

```bash
WaterWall-Test
```

روی سرور ایران ۱۲ مورد را چک می‌کند: سرویس‌ها، پورت‌ها، خروجی end-to-end، **مسیر کامل WireGuard** با کلاینت واقعی (wireproxy)، پهنای‌باند، ۲۰ درخواست همزمان، واتچ‌داگ، وجود outbound در پنل، خطاهای لاگ و مصرف منابع. خروجی سالم: `RESULT: PASS=12 FAIL=0` (روی سرور خارج: `PASS=4`).

### پایش در طول زمان

```bash
# هر ۲۰ ثانیه یک پروب واقعی از داخل کل زنجیره:
watch -n 20 'curl -s -m 10 --socks5-hostname 127.0.0.1:40000 https://api.ipify.org; echo'

# تعداد ری‌استارت‌های سرویس:
systemctl show waterwall -p NRestarts

# تاریخچه واتچ‌داگ:
grep -E "DOWN-CONFIRMED|RECOVERED|STILL DOWN|BACKOFF" /var/log/goldwater/watchdog.log | tail -20

# مصرف منابع:
ps -o pcpu,pmem,rss,etime,comm -C waterwall
```

### تست قطعی عمدی (ایمن)

```bash
# روی سرور خارج:
systemctl stop waterwall
# روی سرور ایران:
tail -f /var/log/goldwater/watchdog.log
# بعد از ~۶۰ ثانیه تأیید قطعی، خودش همه‌چیز را برمی‌گرداند
```

---

## واتچ‌داگ (نگهبان خودترمیم)

```
هر ۲۰ ثانیه یک درخواست واقعی از داخل کل زنجیره (socks→VLESS→Fisher→Reality→خارج→اینترنت)
   │
   ├─ موفق ───────────▶ شمارنده خطا صفر
   │
   └─ شکست ─▶ شمارنده +۱
              ├─ کمتر از ۳ شکست متوالی ──▶ هیچ اقدامی (فلیکرهای لحظه‌ای نادیده)
              └─ ۳ شکست متوالی (≈۶۰ ثانیه قطعیِ اثبات‌شده)
                   ├─ ری‌استارت waterwall ایران → ۳ بار تست
                   │     ├─ بازیابی ✔
                   │     └─ نه ──▶ ری‌استارت waterwall خارج با SSH محدود → ۳ بار تست
                   │                ├─ بازیابی ✔
                   │                └─ نه ──▶ ثبت لاگ، ادامه پروب
                   └─ بیش از ۶ سیکل در ساعت ──▶ مکث ۱۰ دقیقه‌ای actions (پروب ادامه دارد)
```

لاگ واقعی بازیابی (از استقرار مرجع):

```
20:56:41 FAIL 3/3: end-to-end probe failed
20:56:41 DOWN-CONFIRMED: 3 consecutive failures — restarting local waterwall (cycle #1)
20:56:58 still down after local restart — requesting remote waterwall restart
20:57:01 remote waterwall restarted
20:57:02 RECOVERED after remote restart
```

آستانه‌ها در `/etc/goldwater/env`: `GWT_CHECK_INTERVAL`، `GWT_FAIL_THRESHOLD`، `GWT_SOCKS_TIMEOUT` — بعد `systemctl restart goldwater-watchdog`.

---

## مدیریت روزمره و تغییر تنظیمات

```bash
systemctl restart waterwall           # ری‌استارت تانل
systemctl status waterwall            # وضعیت
journalctl -u waterwall -n 50         # لاگ سرویس (خطاهای شروع اینجاست)
tail -f /var/log/goldwater/*.log      # لاگ خود WaterWall
bash install.sh update                # ارتقای باینری WaterWall
bash install.sh uninstall             # حذف کامل
```

| مسیر | محتوا |
|---|---|
| `/etc/goldwater/env` | پارامترها: IP، پورت‌ها، آستانه واتچ‌داگ |
| `/etc/goldwater/core.json` + `nodes.json` | زنجیره WaterWall |
| `/etc/goldwater/keys.env` | کلیدها (**محرمانه**) |
| `/etc/goldwater/xray-outbound.json` | خروجی وایرگارد پنل (سرور ایران) |
| `/etc/goldwater/wg-test.conf` | کانفیگ تست وایرگارد (سرور ایران) |
| `/var/log/goldwater/` | لاگ‌ها + `watchdog.log` |

### پارامترهای نصب

| پارامتر | نقش | پیش‌فرض |
|---|---|---|
| `--port` | پورت TCP تانل بین دو سرور | 443 |
| `--password` | رمز Reality — **دو طرف یکسان** | تصادفی |
| `--uuid` | UUID لایه VLESS — **دو طرف یکسان** | تصادفی |
| `--cover` | دامنه پوششی Reality | www.microsoft.com |
| `--fisher` | تعداد اتصال موازی Fisher | 2 |
| `--wg-port` | پورت WireGuard لوکال (ایران) | 51820 |
| `--test-port` | پورت SOCKS تست (ایران) | 40000 |
| `--workers` | workerهای WaterWall | = تعداد CPU |

> 🔁 اجرای دوباره‌ی `install.sh client` کلیدها را **بازتولید نمی‌کند** — تغییر پارامترها ایمن است.

### تغییر دامنه پوششی (وقتی فیلتر شد)

روی **هر دو سرور** دوباره install بزنید با `--cover جدید` و همان رمز/UUID. نمونه‌های خوب: `www.bing.com`، `www.apple.com`، `www.samsung.com` (باید TLS 1.3 + x25519 داشته باشند و از ایران فیلتر نباشند).

---

## مسیریابی خروجی ایران (اختیاری)

اگر سرور ایران چند WAN دارد (میکروتیک با چند اینترنت)، کیفیت مسیر تا سرور خارج حیاتی است. قبل از استقرار هر WAN را بسنجید (روت موقت /32 به سرور خارج بگذارید و از سرور ایران):

```bash
ok=0; for i in $(seq 1 10); do
  timeout 6 openssl s_client -connect <IP-سرور-خارج>:443 -servername www.microsoft.com </dev/null 2>/dev/null \
    | grep -q "BEGIN CERT" && ok=$((ok+1))
done; echo "این WAN: $ok/10"
```

- **۹–۱۰ از ۱۰:** عالی — **۵–۸:** قابل استفاده (Fisher فعال بماند) — **زیر ۵:** DPI همان WAN اتصال‌ها را می‌کُشد، WAN دیگر انتخاب کنید.

در استقرار مرجع یک WAN با نرخ **۱/۱۰** و یکی با **۱۰/۱۰** اندازه‌گیری شد؛ تانل روی WAN دوم رفت. بدون این اندازه‌گیری، تانل ناپایدار می‌بود.

---

## عملکرد و ظرفیت (اندازه‌گیری‌شده)

| سناریو | نتیجه |
|---|---|
| دانلود ۲۵MB داخل تانل (Cloudflare) | ~۴۶ Mbit/s |
| دانلود مستقیم سرور خارج | ~۴۰۹ Mbit/s |
| ۲۰ درخواست موازی | ۲۰/۲۰ |
| تأخیر برقراری اتصال جدید (با Fisher+Reality) | ~۰.۹ ثانیه |
| RAM / CPU آرام | ~۳۰MB / <۱٪ |

**ظرفیت:** باینری آماده تا ~۲۰۴۸ جریان TCP همزمان (~۲۰۰ کاربر فعال) در پشته lwIP. برای بیشتر، WaterWall را با `-DWW_LWIP_MAX_TCP_FLOWS=8192` کامپایل کنید ([راهنمای بیلد](https://github.com/radkesvat/WaterWall)).

**محدودیت‌ها:** IPv6 داخلی و ICMP (ping) عبور نمی‌کنند؛ UDP (مثل DNS) پشتیبانی می‌شود.

---

## عیب‌یابی

| نشانه | علت | راه‌حل |
|---|---|---|
| `End-to-end probe returned nothing` | رمز/UUID دو طرف فرق دارد | `grep -E "password\|uuid" /etc/goldwater/nodes.json` را روی دو سرور مقایسه کنید |
| `ConnectionFisherClient: timed out` | مسیر تا سرور خارج TCP می‌کشد | WAN را با تست بالا بسنجید؛ `--fisher 3` امتحان کنید |
| `TCP port 443 is already in use` | پورت اشغال | `--port` دیگر (هر دو سرور) |
| پنل outbound را نمی‌شناسد | قالب Xray ذخیره نشده | در Xray Configs پنل Save کنید |
| سرعت پایین | WAN یا MTU | `WaterWall-Test`؛ مستقیم خارج باید >۱۰۰Mbps باشد؛ WAN عوض کنید |
| واتچ‌داگ زیاد ری‌استارت می‌زند | ناپایداری واقعی مسیر | زمان‌های `DOWN-CONFIRMED` را با ساعات شلوغی مقایسه کنید → مشکل WAN |
| `Node Map Failure` در journal | JSON دست‌کاری‌شده | دوباره install بزنید |

---

## سوالات متداول

**چند سرور خارج می‌شود داشت؟**
روی هر سرور خارج یک `install.sh server` مستقل (رمز/UUID جدا). روی ایران می‌توانید یک instance دیگر WaterWall با پورت‌های wg/test متفاوت برای سرور دوم اضافه کنید.

**پینگ از داخل تانل نمی‌رود؟**
درست است — پشته داخلی فقط TCP/UDP را بازسازی می‌کند.

**اگر فیلتر شد چه کنم؟**
۱) `--cover` را عوض کنید (هر دو سرور) ۲) `--port` را تغییر دهید ۳) IP سرور خارج را عوض کنید. کلیدها مستقل‌اند و می‌مانند.

**مصرف CPU زیر بار؟**
هر ~۱۰۰Mbps ترافیک تانل ≈ نیمی از یک هسته 2GHz (رمزنگاری چندلایه). WaterWall خودش C و سبک است.

**روی سرور خارج فقط همین سرویس است؟**
بله؛ تک‌پروسه بدون وابستگی و برای بیرونی‌ها فقط یک وب‌سرور TLS با گواهی معتبر سایت پوششی.

---

## امنیت

- 🔑 رمز Reality و UUID = کلید ورود به تانل؛ محرمانه (همراه `/etc/goldwater/keys.env`).
- 🔒 فایل‌های حساس با دسترسی `600`.
- 🛡️ کلید SSH واتچ‌داگ با forced-command فقط `restart`.
- 🕵️ سرور خارج برای اسکنرها فقط یک سایت پوششی واقعی است.

## اعتبارها و مجوز

- [radkesvat/WaterWall](https://github.com/radkesvat/WaterWall) — موتور تانل
- [MHSanaei/3x-ui](https://github.com/MHSanaei/3x-ui) — پنل
- [octeep/wireproxy](https://github.com/octeep/wireproxy) — تست مسیر WireGuard

مجوز: MIT — فایل [LICENSE](LICENSE)

> ⚠️ این ابزار برای حفظ دسترسی آزاد به اینترنت ساخته شده؛ مسئولیت استفاده با کاربر است.

</div>
