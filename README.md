# 🆘 ResQLink — Offline Emergency Communication App

**ResQLink** is a disaster response communication tool designed to work without internet or cellular service. Built with Flutter, it enables peer-to-peer messaging via Wi-Fi Direct, and logs GPS coordinates offline. Designed for emergency responders and disaster victims in network-compromised environments.

---

## 🚀 Features

- 📡 **Offline Messaging** — Send and receive emergency messages using Wi-Fi Direct, no internet required.
- 📍 **Location Tracking** — Logs and stores GPS coordinates even when offline.
- 💾 **Local Storage** — Uses SQLite for persistent local message and location storage.
- 🔌 **Fully Offline** — No internet or cloud services required, works completely offline.
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
- SQLite (via sqflite plugin) — Local data persistence
- Wi-Fi Direct plugins (Android support)
- Geolocator — GPS tracking

---

## 📂 Project Structure (Simplified)

```
lib/
├── main.dart
│   ├── gps_page.dart
│   ├── messages_page.dart
|   ├── home_page.dart
|   ├── database_helper.dart
|   ├── firebase_auth_helper.dart
|   ├── firebase_options.dart
│   └── settings_page.dart
├── services/
│   ├── auth_service.dart
│   ├── database_service.dart
│   ├── firebase_debug.dart
│   ├── map_service.dart
|   ├── message_sync_service.dart
|   ├── p2p_service.dart
|   └── settings_service.dart
└── models/
    ├── message_model.dart
    ├── user_model.dart
    └── device_model.dart
```

---

## 📈 Key Metrics (Future Integration)

- Monthly Active Users (MAU)
- Message delivery rate (offline and synced)
- Sync success rate
- Battery consumption during extended usage

---

## 📌 Status

🚧 _This project is under active development as part of a university thesis._

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
