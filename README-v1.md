<div dir="rtl">

# مستندات نسخه ۱ (WaterWall Reality)

نسخه ۱ با موتور WaterWall و Reality v2 مستقر در تگ `v1.0.0` است و مستندات کامل فارسی آن (معماری چندلایه، نصب دقیق، تحلیل DPI، پایش پایداری) در همان تگ نگهداری می‌شود:

[README کامل نسخه ۱ در تگ v1.0.0](https://github.com/DashSaman/GoldWaterTunnel/blob/v1.0.0/README.md)

## خلاصه دستورهای نسخه ۱

```bash
# روی سرور خارج:
bash install.sh server --port 443

# روی سرور ایران:
bash install.sh client --server FOREIGN_IP --password PASS --uuid UUID

# تست یک‌ضربه‌ای:
bash WaterWall-Test
```

## چه زمانی نسخه ۱؟

- CPU سرور ایران AVX2 دارد (از ۲۰۱۳ به بعد)
- DPI سخت‌گیرانه است و وایرگارد خام شناخته می‌شود
- مقاومت حداکثری مهم‌تر از سادگی نصب است

در غیر این صورت [نسخه ۲ وایرگارد](README.md) سریع‌تر و ساده‌تر است.
