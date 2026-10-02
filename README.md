<div dir="rtl">

# 🌊 GoldWaterTunnel v2

> تانل WireGuard مستقیم + موتور WaterWall Reality — دو روش در یک ابزار

## دو موتور تانل

| نسخه | پروتکل | CPU نیاز | مقاومت DPI | نصب |
|---|---|---|---|---|
| **v2 WireGuard** | Kernel WG | هر CPU ✅ | متوسط | ‏۲ دقیقه |
| **v1 WaterWall** | Reality v2 + VLESS | AVX2 لازم | عالی | ‏۵ دقیقه |

## نصب سریع v2 (WireGuard) — ۲ دقیقه

### سرور خارج:
```bash
bash install-v2.sh server
```
Public Key و IP و Port رو یادداشت کن.
(فوروارد و MASQUERADE خودکار اضافه می‌شود — تنظیم دستی لازم نیست)

### سرور ایران:
```bash
bash install-v2.sh client --server FOREIGN_IP --port PORT --server-pub KEY
```

**خودکار تشخیص می‌دهد:**
- سرور اختصاصی با IP عمومی مستقیم → بدون تنظیم اضافه
- سرور پشت NAT/MikroTik → WG UDP خودش punch می‌کند، اگر نشد پورت forward کن

### تکمیل روی سرور خارج:
دستور `addpeer` که سرور ایران چاپ کرد رو همین‌جا بزن:
```bash
bash install-v2.sh addpeer --pub CLIENT_PUB --ip 10.70.0.X
```
همتا بدون قطعی و بدون ری‌استارت اضافه می‌شود.

### outbound برای پنل 3x-ui:
```bash
bash install-v2.sh outbound FOREIGN_IP
```
JSON آماده paste در: پنل → Xray Configs → Outbounds → Add

### تست:
```bash
bash install-v2.sh test FOREIGN_IP    # هندشیک + پینگ + IP خروجی
bash install-v2.sh status             # وضعیت همه تانل‌ها
```

## معماری v2

```
کاربر → 3x-ui inbound → Routing Rule → WaterWall-IP outbound (WireGuard)
    → Kernel WG UDP tunnel → Foreign Server → SNAT → Internet
```

- بدون SIT، بدون گت‌وی واسط — WG مستقیم A→B
- MTU 1380 — سازگار با همه مسیرها
- Keepalive 15s — NAT session زنده می‌ماند
- Table = off — default route عوض نمی‌شود
- fwmark لازم نیست — Xray WireGuard outbound خودش handle می‌کند

## مدیریت

```bash
bash install-v2.sh status              # وضعیت همه تانل‌ها
bash install-v2.sh test 91.107.158.40  # تست یک تانل
# حذف:
wg-quick down gwt40
rm /etc/wireguard/gwt40.conf /etc/goldwater-v2/91.107.158.40 -rf
```

## نصب v1 (WaterWall Reality) — نیاز به CPU مدرن

```bash
bash install.sh server  --port 443          # روی خارج
bash install.sh client  --server IP --password PASS --uuid UUID  # روی ایران
```

مستندات کامل v1 در تگ نسخه ۱: [README v1](README-v1.md)

## نتیجه تست واقعی (بار سنگین ممتد — Iran Asiatech ↔ Hetzner)

| متریک | نتیجه اندازه‌گیری‌شده |
|---|---|
| پهنای‌باند تجمعی داخل تونل | ‏145–171 Mbps (چند جریان) |
| ۲۰۰ اتصال همزمان (درخواست‌های سبک) | ‏99.9٪ موفق، p50=166ms |
| ۲۰۰۰ اتصال همزمان (churn بالا) | ‏96٪+ موفق، 715 req/s، p50=171ms |
| جریان‌های سنگین ۱MB (500 همزمان) | ‏97.5٪ موفق در اشباع کامل پهنای‌باند |
| تأخیر پایه تونل (پینگ WG) | ‏~73ms، 0% packet loss روی Asiatech |
| CPU سرور خارج زیر 1000 اتصال | ‏~5% (۲ هسته) |
| ریبوت | خودکار برگشت (systemd + wg-quick) |
| سازگاری CPU | همه (حتی 2012) |

> نکته: p95 در سناریوهای اشباع‌کننده‌ی پهنای‌باند بالا می‌رود (صف عادلانه) — رفتار طبیعی هر لینک اشباع‌شده است، نه افت تانل.

## تغییرات v2.1

- **رفع باگ مهم تداخل سشن**: اینترفیس کرنل (برای `test`) و outbound یوزرسپیس Xray دیگر از یک کلید استفاده نمی‌کنند — قبلا سرور endpoint را بین دو سشن جابه‌جا می‌کرد (ping-pong) و باعث از دست رفتن بسته‌ها می‌شد. حالا `outbound` یک peer اختصاصی با IP جدا می‌سازد.
- keepalive از 15 به 10 ثانیه (ایمنی NAT)
- MSS clamp روی FORWARD سرور (جلوگیری از blackhole MTU)
- بهینه‌سازی بافرهای UDP/TCP (sysctl) روی هر دو طرف برای بار سنگین

## نکته‌ها

- v2 برای backup عالی است — وقتی تانل اصلی مشکل دارد در پنل به WaterWall-IP سوییچ کن
- WireGuard UDP ممکن است توسط DPI شناخته شود — برای مقاومت کامل از v1 استفاده کن
- چند تانل همزمان ممکن است (هر کدام به یک سرور خارج)
- اگر outbound را به پنل دادید، دستور `addpeer` دوم (peer اختصاصی Xray) را هم روی سرور خارج اجرا کنید — خود `outbound` یادآوری می‌کند

## مجوز

MIT
