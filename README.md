<div align="center">

# CMD Notes

**ملاحظات ومذكرات**

Notes, journal and private notes on your phone

`v0.1.0` · Android 7.0+ · no internet permission · no account, no server

</div>

> **Status: first release, NOT yet tested on a physical device.** Screenshots in the PDFs are automated UI test renders with demo data, not device screenshots.

## Download

Open the release page and pick **`cmd-notes-0.1.0-arm64-v8a.apk`** for most phones (`armeabi-v7a` for older 32-bit phones, `x86_64` for emulators):

**https://github.com/moh500600/cmd-notes/releases/tag/v0.1.0**

SHA-256 of the arm64-v8a file:

```
5b2c31414cc47d4c8c3cefb5e1fbe5674d3ec6592963491d3845cc57ac60042d
```

Android will ask you to allow installing from an unknown source. The APK is signed with a new CMD key made for this app.

## Documents

- [Visual README (PDF, 4 pages)](docs/CMD-Notes-README-visual.pdf)
- [Showcase (PDF, 5 pages, 16:9)](docs/CMD-Notes-Showcase.pdf)

## ما هو التطبيق

- **ملاحظات غنية** (Rich notes): عناوين وقوائم وجداول وقوائم مهام.
- **الدفاتر والوسوم** (Notebooks & tags): تنظيم بدفاتر ومجلدات ووسوم وقوالب.
- **ملاحظات خاصة** (Private notes): مشفّرة بعبارة مرورك على الجهاز.
- **التسجيل الصوتي** (Voice notes): تسجيل وحفظ، والنص تكتبه بنفسك.
- **اليوميات والتقويم** (Journal & calendar): يوميات مشفّرة وتقويم للملاحظات.
- **البحث** (Search): بحث نصي كامل بالعربية والإنجليزية.
- **المشاركة بملف** (Share by file): ملاحظة أو دفتر كملف نصي، والطرف الآخر يستورده.
- **النسخ الاحتياطي** (Backup): نسخة احتياطية قابلة للتشفير.

## What it does

- **Rich notes**
- **Notebooks & tags**
- **Private notes**
- **Voice notes**
- **Journal & calendar**
- **Search**
- **Share by file**
- **Backup**

## Privacy and limits

- All data lives in a database on your phone. The release manifest has no INTERNET permission, there is no cloud account, no backend and no hosted AI.
- المزامنة والمساعد الذكي وقراءة النص من الصور والتفريغ الصوتي أُزيلت لأنها كانت تعتمد على الخادم.
- It installs **next to** the old app (new package id `com.cmdapps.notes`). It does not replace it and does not move data automatically. Old server data was not touched.
- Sharing between people is done by exporting a file and importing it on the other phone.
- Deleting the app or its data deletes your data. Keep a backup file.
- Not tested on a physical device yet. Report problems in the repository issues.

## Build

Flutter project. CI (`.github/workflows/android.yml`) runs analyze, tests and a release build. The APKs in the release were re-signed locally with the CMD key.

## License

No license has been chosen yet.
