# 🆘 ResQLink — Offline Emergency Communication App

**ResQLink** is a disaster response communication tool designed to work without internet or cellular service. Built with Flutter, it enables peer-to-peer messaging via Wi-Fi Direct, logs GPS coordinates offline, and syncs data to the cloud (Firebase) once connectivity is restored. Designed for emergency responders and disaster victims in network-compromised environments.

---

## 🚀 Features

- 📡 **Offline Messaging** — Send and receive emergency messages using Wi-Fi Direct, no internet required.
- 📍 **Location Tracking** — Logs and stores GPS coordinates even when offline.
- 🔄 **Auto-Sync** — Automatically syncs messages and location data to Firebase when internet is restored.
- 💾 **Local Storage** — Uses SQLite for persistent local message and location storage.
- 🧭 **Crisis-Optimized UI** — Simple interface designed for fast, stress-free interaction during emergencies.

---

## 🎯 Use Cases

- Natural disasters: typhoons, earthquakes, floods
- Search and rescue coordination
- Rural or off-grid emergency situations
- Community-based disaster preparedness networks

---

## 🛠 Built With

- [Flutter](https://flutter.dev/) + Dart
- [Firebase](https://firebase.google.com/) — Firestore, Authentication, Cloud Functions
- SQLite (via sqflite plugin)
- Wi-Fi Direct plugins (Android support)

---

## 📂 Project Structure (Simplified)

```
lib/
├── main.dart
│   ├── gps_page.dart
│   ├── messages_page.dart
│   └── settings_page.dart
├── services/
│   ├── wifi_direct_service.dart
│   ├── gps_service.dart
│   ├── firebase_sync.dart
│   └── storage_service.dart
└── models/
    ├── message.dart
    └── location.dart
```

---

## 📈 Key Metrics (Future Integration)
- Monthly Active Users (MAU)
- Message delivery rate (offline and synced)
- Sync success rate
- Battery consumption during extended usage

---

## 📌 Status

🚧 *This project is under active development as part of a university thesis.*

Testing is being conducted in simulated offline environments. Real-world field testing and polish will follow in the next release cycle.

---

## 🧠 Future Work

- iOS support (currently Android-only)
- Encrypted messaging
- Expanded mesh support (multi-group Wi-Fi Direct)
- Offline map tiles and routing

---

## 🤝 Acknowledgements

- NDRRMC, DICT, and community responders for insight into real-world disaster communication challenges.
- Open-source plugin developers and contributors to Flutter’s networking ecosystem.

---

## 📃 License

This project is currently academic and licensed for educational/non-commercial use.
