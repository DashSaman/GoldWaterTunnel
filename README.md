# GoldWaterTunnel 🌊🔒

> **خفن‌ترین و مقاوم‌ترین تانل ضد فیلتر بر پایه‌ی [WaterWall](https://github.com/radkesvat/WaterWall)** — ترکیب WireGuard + Reality v2 + Connection Fisher + Fake-DNS در یک زنجیره‌ی چندلایه، با واتچ‌داگ خودترمیم و دستور تست یک‌ضربه‌ای.

[![WaterWall](https://img.shields.io/badge/Engine-WaterWall%20v1.46.9-blue)](https://github.com/radkesvat/WaterWall)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## ✨ این پروژه چیست؟

GoldWaterTunnel یک اسکریپت نصب خودکار است که بین **یک سرور خارج (آزاد)** و **یک سرور داخل ایران** یک تانل ضد DPI با این معماری می‌سازد:

```
┌─────────────────────────────── سرور ایران (کلاینت) ───────────────────────────────┐
│                                                                                    │
│  پنل Xray (x-ui/3x-ui) ──(WireGuard روی 127.0.0.1)──▶ WaterWall                  │
│                                                         │                          │
│                          PacketsToConnection (پشته lwIP + Fake-DNS داخلی)          │
│                                                         │                          │
│                          VlessClient  ← مقصد هر کانکشن داخل تونل حمل می‌شود        │
│                                                         │                          │
│              ConnectionFisherClient (مسابقه ۲ اتصال موازی، مقاوم به قطع‌کردن DPI)  │
│                                                         │                          │
│              RealityClient (دست‌دادنِ واقعی TLS با دامنه‌ی پوششی + رمز AEAD)        │
│                                                         │                          │
└─────────────────────────────────────────────────────────┼──────────────────────────┘
                                                          │ TCP:443 (ظاهر: HTTPS معمولی)
┌─────────────────────────────── سرور خارج (سرور) ────────┼──────────────────────────┐
│                                                         ▼                          │
│              RealityServer (پروب‌های ناشناس → پروکسی به سایت واقعی، بی‌آسیب)        │
│                                                         │                          │
│              ConnectionFisherServer (اعتبارسنجی مسابقه)                             │
│                                                         │                          │
│              VlessServer → TcpUdpConnector ──▶ اینترنت آزاد 🌍                     │
└────────────────────────────────────────────────────────────────────────────────────┘
```

### چرا این ترکیب «ضد فیلتر» است؟

| لایه | تکنیک | چه چیزی را از DPI پنهان می‌کند |
|---|---|---|
| **Reality v2** | هندشیک TLS *واقعی* با دامنه‌ی پوششی (مثل `www.microsoft.com`) و سپس TAKEOVER با رمز AEAD | ترافیک از نظر بسته‌بندی، اندازه رکوردها و رفتار بستن، دقیقاً TLS واقعی دیده می‌شود؛ اسکنر فعال هم به سایت واقعیِ پوشش وصل می‌شود و پاسخ می‌گیرد |
| **ConnectionFisher** | برای هر اتصال، ۲ اتصال موازی ساخته و اولین سالم نگه داشته می‌شود | اگر DPI بعضی TCPها را با RST بکُشد (رفتار معروف اپراتورهای ایرانی) اتصال spare جایگزین می‌شود |
| **Fake-DNS داخلی** | DNS داخل خود تانل و در حافظه پاسخ داده می‌شود (شبکه 100.64.0.0/10) | نه DNS Leak دارید، نه تأخیر؛ دامنه‌ها رمزگشایی‌شده به سرور خارج می‌رسند و آن‌جا با DNS سالم resolve می‌شوند |
| **VLESS داخلی** | مقصد هر کانکشن داخل تونل رمز شده حمل می‌شود | سرور خارج بدون افشای مقصد، دقیقاً به همان مقصد وصل می‌شود |

### ویژگی‌ها

- ✅ **خروجی WireGuard برای پنل** — یک outbound آماده برای بخش Outbounds پنل x-ui/3x-ui؛ هر اینباندی را با یک قانون Routing به آن بدهید تا از تانل خارج شود
- ✅ **پایدار و خودترمیم** — سرویس systemd با `Restart=always` + واتچ‌داگ که واقعی‌بودن قطعی را با ۳ خطای متوالی *تأیید* می‌کند، بعد اول WaterWall ایران و در صورت نیاز WaterWall خارج (با کلید SSH محدود) را ری‌استارت می‌کند
- ✅ **سبک** — WaterWall با C نوشته شده؛ مصرف عادی: ~۳۰MB رم و کمتر از ۱٪ CPU
- ✅ **دستور تست جامع** — یک دستور `WaterWall-Test` همه‌چیز را از هندشیک تا پهنای‌باند و پنل چک می‌کند
- ✅ **نصب یک‌خطی** روی هر دو سرور

---

## 🧰 پیش‌نیازها

| مورد | سرور خارج (Server) | سرور ایران (Client) |
|---|---|---|
| OS | Ubuntu 20.04+ / Debian 11+ (x86_64) | همان |
| دسترسی | root | root |
| پورت آزاد | یک پورت TCP (پیشنهاد: 443) | — |
| اینترنت | آزاد (برای دانلود باینری GitHub) | هر طور — باینری را می‌توانید دستی بگذارید |
| اختیاری | — | پنل x-ui / 3x-ui نصب‌شده |

> 💡 اگر سرور ایران به GitHub وصل نمی‌شود، فایل زیپ WaterWall را جداگانه دانلود و از حالت فشرده خارج کنید و با `GWT_LOCAL_BIN=/root/Waterwall bash install.sh ...` نصب کنید.

---

## 🚀 نصب — قدم‌به‌قدم

### مرحله ۱: سرور خارج (مثلاً هتزنر، آلمان)

```bash
curl -fsSL https://raw.githubusercontent.com/DashSaman/GoldWaterTunnel/main/install.sh -o install.sh
curl -fsSL https://raw.githubusercontent.com/DashSaman/GoldWaterTunnel/main/watchdog.sh -o watchdog.sh
curl -fsSL https://raw.githubusercontent.com/DashSaman/GoldWaterTunnel/main/WaterWall-Test -o WaterWall-Test

bash install.sh server --port 443 --cover www.microsoft.com
```

خروجی، یک **رمز Reality** و یک **UUID وایرگارد-داخلی** چاپ می‌کند. آن‌ها را نگه دارید:
(اگر خودتان مقدار می‌خواهید: `--password MYSTRONGPASS --uuid $(cat /proc/sys/kernel/random/uuid)`)

### مرحله ۲: سرور ایران

```bash
bash install.sh client \
  --server <IP-سرور-خارج> \
  --port 443 \
  --password <همان-رمز-مرحله-۱> \
  --uuid <همان-UUID-مرحله-۱> \
  --cover www.microsoft.com
```

نصاب خودش:
1. باینری WaterWall را نصب می‌کند
2. کلیدهای WireGuard می‌سازد
3. کانفیگ زنجیره را در `/etc/goldwater/` می‌نویسد
4. سرویس‌های `waterwall` و `goldwater-watchdog` را فعال و اجرا می‌کند
5. یک **تست end-to-end** اجرا می‌کند (باید IP سرور خارج را برگرداند)
6. فایل `/etc/goldwater/xray-outbound.json` را می‌سازد — همین را به پنل می‌دهید

### مرحله ۳: اتصال به پنل (x-ui / 3x-ui)

1. محتوای `/etc/goldwater/xray-outbound.json` را در مسیر زیر اضافه کنید:
   **پنل ← Xray Configs ← Outbounds ← افزودن** (یا ویرایش JSON خروجی‌ها)
2. حالا در **Routing** هر اینباندی را خواستید با یک قانون به outbound تگ‌شده‌ی `waterwall-wg` بدهید:
   ```json
   { "type": "field", "inboundTag": ["نام-اینباند"], "outboundTag": "waterwall-wg" }
   ```
3. (پیشنهادی) DNS پنل را روی سرور `198.18.0.2` بگذارید تا resolveها داخل تونل و بدون نشتی انجام شود:
   ```json
   "dns": { "servers": ["198.18.0.2"], "queryStrategy": "UseIPv4" }
   ```
   و این قانون Routing را **قبل از بقیه** بگذارید:
   ```json
   { "type": "field", "ip": ["198.18.0.2/32"], "outboundTag": "waterwall-wg" }
   ```

> 🎯 از این لحظه، هر اینباندی که به `waterwall-wg` هدایت شود، ترافیکش از کل زنجیره‌ی ضد DPI عبور کرده و با IP سرور خارج به اینترنت می‌رسد.

### مرحله ۴ (اختیاری، ولی توصیه‌شده): ری‌استارت ریموت برای واتچ‌داگ

کلید عمومی واتچ‌داگ را که نصاب ایران چاپ می‌کند، **روی سرور خارج** اضافه کنید تا واتچ‌داگ بتواند در صورت مرگِ WaterWall خارج، آن را از راه دور بالا بیاورد:

```bash
# روی سرور خارج:
mkdir -p /root/.ssh && chmod 700 /root/.ssh
echo 'command="/usr/local/bin/goldwater-remote-restart",no-pty,no-X11-forwarding ssh-ed25519 AAAA... goldwater-watchdog' >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
```

این کلید فقط و فقط اجازه‌ی اجرای `restart` را دارد (_forced command_) — نه شل، نه چیز دیگر.

---

## 🧪 تست: دستور `WaterWall-Test`

روی هر دو سرور نصب است و وضعیت را کامل گزارش می‌کند:

```bash
WaterWall-Test
```

روی سرور ایران این موارد را چک می‌کند: سرویس‌ها، پورت‌ها، خروجی end-to-end (باید IP سرور خارج باشد)، **مسیر کامل WireGuard** با یک کلاینت واقعی، پهنای‌باند، ۲۰ درخواست همزمان، وضعیت واتچ‌داگ، وجود outbound در پنل، خطاهای لاگ و مصرف منابع.
خروجی موفق: `RESULT: PASS=12 FAIL=0`

### تست پایداری واتچ‌داگ (دستی)

```bash
# روی سرور خارج، تانل را بکشید:
systemctl stop waterwall
# روی سرور ایران، لاگ را ببینید — بعد از ~۶۰ ثانیه تأییدِ قطعی، خودش همه‌چیز را برمی‌گرداند:
tail -f /var/log/goldwater/watchdog.log
```

رفتار قابل انتظار:
```
FAIL 3/3 → DOWN-CONFIRMED → restart محلی → هنوز مرده؟ → restart ریموت با SSH → RECOVERED
```

---

## ⚙️ مدیریت و تنظیمات

```bash
systemctl restart waterwall      # ری‌استارت تانل
systemctl status waterwall       # وضعیت
journalctl -u waterwall -n 50    # لاگ سرویس
tail -f /var/log/goldwater/*.log # لاگ خود WaterWall
WaterWall-Test                   # تست کامل
bash install.sh update           # ارتقای باینری WaterWall
bash install.sh uninstall        # حذف کامل
cat /etc/goldwater/env           # پارامترها (پورت‌ها، IP، آستانه‌ی واتچ‌داگ ...)
cat /etc/goldwater/keys.env      # کلیدها (محرمانه!)
```

### پارامترهای نصب

| پارامتر | نقش | پیش‌فرض |
|---|---|---|
| `--port` | پورت TCP تانل بین دو سرور | 443 |
| `--password` | رمز Reality (دو طرف یکسان) | تصادفی |
| `--uuid` | UUID لایه VLESS داخلی (دو طرف یکسان) | تصادفی |
| `--cover` | دامنه پوششی Reality | www.microsoft.com |
| `--fisher` | تعداد اتصال موازی Fisher | 2 |
| `--wg-port` | پورت WireGuard لوکال (ایران) | 51820 |
| `--test-port` | پورت SOCKS تست (ایران) | 40000 |
| `--workers` | تعداد worker هسته WaterWall | = تعداد CPU |

> 🔁 اجرای دوباره‌ی `install.sh client` کلیدها را **دوباره‌سازی نمی‌کند**؛ ایمن برای تغییر پارامترها.

### تغییر دامنه پوششی (وقتی فیلتر شد)

روی **هر دو سرور** `--cover` را عوض کنید و هر دو را دوباره نصب/ری‌استارت کنید. دامنه باید TLS 1.3 و x25519 پشتیبانی کند و از ایران فیلتر نباشد. نمونه‌های خوب: `www.bing.com`، `www.apple.com`، `www.samsung.com`

---

## 🩺 عیب‌یابی

| نشانه | علت احتمالی | راه‌حل |
|---|---|---|
| `End-to-end probe returned nothing` | رمز/UUID دو طرف فرق دارد | `grep password /etc/goldwater/nodes.json` را روی هر دو سرور مقایسه کنید |
| ConnectionFisherClient: timed out | مسیر اینترنت ایران→سرور، TCPها را می‌کُشد | WAN دیگری را امتحان کنید (تست: `for i in $(seq 10); do timeout 6 openssl s_client -connect IP:443 -servername www.microsoft.com </dev/null 2>/dev/null \| grep -c CERT; done` — باید 10/10 شود) |
| `TCP port 443 is already in use` | پورت اشغال است | با `--port` پورت دیگر بدهید |
| پنل، outbound را نمی‌شناسد | قالب Xray ذخیره نشده | از صفحه Xray Configs پنل ذخیره کنید تا در DB ثبت شود |
| سرعت پایین | MTU یا WAN | `WaterWall-Test` را ببینید؛ WAN مستقیم سرور خارج باید بالای 100Mbps باشد |

---

## 🔐 امنیت

- رمز Reality و UUID را مثل رمز عبور نگه دارید — هر کسی که هر دو را داشته باشد می‌تواند از تانل استفاده کند.
- فایل‌های `/etc/goldwater/{keys.env,nodes.json,env}` با دسترسی 600 هستند؛ آن‌ها را جایی آپلود نکنید.
- کلید SSH واتچ‌داگ با forced-command محدود شده است.
- سرور خارج برای اسکنرها فقط یک وب‌سرور TLS به نظر می‌رسد (پاسخ واقعی از دامنه پوششی می‌گیرند).

## 📐 محدودیت‌های شناخته‌شده

- باینری آماده‌ی WaterWall حدود **۲۰۴۸ جریان TCP همزمان** را در پشته lwIP پشتیبانی می‌کند (مثل ~۲۰۰ کاربر فعال همزمان). برای ظرفیت بالاتر باید WaterWall را با `-DWW_LWIP_MAX_TCP_FLOWS=8192` کامپایل کنید (راهنمای بیلد ریپوی WaterWall).
- ترافیک IPv6 داخلی پشتیبانی نمی‌شود (DNS روی UseIPv4 است).
- ICMP (ping) از داخل تونل عبور نمی‌کند — طبیعی است.

## 🙏 اعتبارها

- [radkesvat/WaterWall](https://github.com/radkesvat/WaterWall) — موتور تانل (C، سریع و ماژولار)
- [MHSanaei/3x-ui](https://github.com/MHSanaei/3x-ui) — پنل
- [octeep/wireproxy](https://github.com/octeep/wireproxy) — برای تست مسیر WireGuard

## 📄 مجوز

MIT — فایل [LICENSE](LICENSE)

> ⚠️ این ابزار برای حفظ دسترسی آزاد به اینترنت ساخته شده است. مسئولیت استفاده از آن با کاربر است.
