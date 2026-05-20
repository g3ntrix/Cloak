# کلوک

**کلوک** یک اپلیکیشن macOS است که ترافیک را از طریق یک پل محلی SNI Spoofing و هستهٔ تعبیه‌شدهٔ **Xray** عبور می‌دهد. می‌توانید پروفایل‌های CDN (مانند VLESS، Trojan و بیشتر) را وارد کنید، با یک کلیک متصل شوید و در صورت نیاز، تمام ترافیک سیستم را از طریق پراکسی محلی SOCKS عبور دهید.

این برنامه کاربر را از دردسر ستاپ‌های پیچیده و داشتن کلاینت جداگانهٔ V2Ray برای اتصال نجات می‌دهد. تنها کافی است یک کانفیگ سالم داشته باشید و دکمهٔ Connect را بزنید.

<table>
  <tr>
    <td align="center" width="50%">
      <strong>Dashboard</strong><br />
      <img src="macos-app/screenshot/app-dashboard.png" alt="Dashboard — connect, Egress IP, session stats" width="100%" />
    </td>
    <td align="center" width="50%">
      <strong>Profiles</strong><br />
      <img src="macos-app/screenshot/profiles.png" alt="Profiles — import, ping, bulk actions" width="100%" />
    </td>
  </tr>
  <tr>
    <td align="center">
      <strong>Menu bar</strong><br />
      <img src="macos-app/screenshot/menubar.png" alt="Menu bar popover" width="100%" />
    </td>
    <td align="center">
      <strong>Light mode</strong><br />
      <img src="macos-app/screenshot/light-mode.png" alt="Cloak in light appearance" width="100%" />
    </td>
  </tr>
</table>

## ویژگی‌ها

- **One-click connect** — شروع/توقف Listener پایتون و Xray از Dashboard یا Menu bar
- **Profile library** — چسباندن لینک یا Drag-and-Drop فایل متنی (`vless`، `trojan`، `vmess`، `ss`)
- **Real profile ping** — اندازه‌گیری latency از داخل tunnel هر پروفایل؛ ping همه با امکان لغو؛ حذف پروفایل‌های بدون ping
- **System proxy toggle** — عبور ترافیک همهٔ app‌های macOS از local SOCKS endpoint کلوک
- **LAN sharing** — Listener فقط روی همین مک Bind شود یا روی شبکه در دسترس باشد (Local / LAN)
- **Egress IP** — نمایش public IP شما از طریق پروفایل فعال در زمان اتصال
- **Menu bar control** — اتصال، تعویض پروفایل و بازکردن پنجرهٔ اصلی بدون بازماندن دائمی آن
- **Appearance** — پیروی از system یا انتخاب دستی Light / Dark
- **Logs** — ثبت اختیاری خروجی Listener و Xray برای troubleshooting

## دانلود (macOS)

آخرین فایل **`.dmg`** را از [GitHub Releases](https://github.com/g3ntrix/Cloak/releases) دریافت کنید.

> **نسخهٔ بدون امضا:** ممکن است macOS در اولین اجرا برنامه را مسدود کند. در صورت نیاز از **System Settings → Privacy & Security** اجازهٔ اجرا را بدهید.

## شروع سریع

1. کلوک را باز کنید و مجوز یک‌بارهٔ Helper را بدهید (Settings).
2. اگر از پل SNI داخلی استفاده می‌کنید، JSON مربوط به Cloudflare Listener را در **Settings** قرار دهید.
3. یک پروفایل را انتخاب کنید، سپس در Dashboard روی **Connect** بزنید.
4. اگر می‌خواهید همهٔ برنامه‌ها به‌صورت خودکار از کلوک استفاده کنند، **System proxy** را روشن کنید.

## ساختار پروژه

| مسیر | توضیح |
|------|-------|
| `macos-app/` | کلاینت macOS مبتنی بر SwiftUI (Cloak) |
| `main.py` / listener | پل SNI Spoofing پایتون (نسخهٔ bundled یا مسیر توسعه) |

## پشتیبانی و منبع

- **مخزن:** [github.com/g3ntrix/Cloak](https://github.com/g3ntrix/Cloak) — اگر کلوک برایتان مفید بود، ستاره دادن به مخزن باعث دلگرمی است
- **نویسنده:** [t.me/g3ntrix](https://t.me/g3ntrix)

## حمایت مالی

اگر این پروژه برای شما مفید بوده، می‌توانید از توسعهٔ آن حمایت کنید:

- **TON:** `UQCriHkMUa6h9oN059tyC23T13OsQhGGM3hUS2S4IYRBZgvx`
- **USDT (BEP20):** `0x71F41696c60C4693305e67eE3Baa650a4E3dA796`
- **TRX (TRON):** `TFrCzU7bDey9WSh3fhqCBqhaiMzr8VhcUV`

## لایسنس

به [LICENSE](LICENSE) مراجعه کنید.
