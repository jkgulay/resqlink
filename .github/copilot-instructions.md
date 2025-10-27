# ResQLink - AI Coding Agent Instructions

## Project Overview

ResQLink is a disaster response communication app built with Flutter that enables **offline peer-to-peer messaging** via WiFi Direct when internet/cellular networks are down. The app syncs messages and location data to Firebase when connectivity is restored.

## Critical Architecture Concepts

### 1. Dual-Layer Messaging Architecture

Messages flow through TWO distinct systems that must stay synchronized:

**P2P Layer** (`lib/services/p2p/`)

- WiFi Direct device-to-device communication (no internet needed)
- Socket-based messaging protocol (`protocols/socket_protocol.dart`)
- Multi-hop mesh networking with TTL (max 5 hops)
- Event-driven updates via `P2PEventBus` (`lib/features/p2p/events/p2p_event_bus.dart`)

**Chat/Database Layer** (`lib/features/chat/` and `lib/features/database/`)

- SQLite local persistence (`resqlink_enhanced.db`, version 11)
- Chat sessions and message repositories
- Firebase cloud sync when online
- UI state management via `ChatService` (Provider pattern)

**Integration Point**: The `MessageRouter` (`lib/services/messaging/message_router.dart`) bridges these layers:

```dart
// P2P receives message → MessageRouter → ChatRepository → UI updates
// UI sends message → ChatService → P2PMainService → WiFi Direct transmission
```

### 2. Device Identification System (CRITICAL)

ResQLink uses a **UUID-based identification** system, NOT MAC addresses for device identity:

- **endpointId**: Device's wlan0 MAC address (used for routing/network sessions only)
- **deviceId**: UUID generated per app instance (persisted in SharedPreferences)
- **fromUser**: User's display name (from landing page, UI display only)
- **targetDeviceId**: Recipient's MAC for routing (null = broadcast)

**Why this matters**: When working with device identification:

- User-facing features: Use `deviceId` (UUID) and `fromUser` (display name)
- Network routing/sockets: Use `endpointId` or `targetDeviceId` (MAC addresses)
- Chat sessions: Generated as `session_${sortedUserNames}_${timestamp}` to prevent duplicates

See: `lib/models/message_model.dart` lines 8-14, `ENHANCED_P2P_FEATURES.md` section 4.

### 3. WiFi Direct Native Integration

WiFi Direct functionality is implemented in **Kotlin** (Android-only currently):

- `android/app/src/main/kotlin/com/example/resqlink/MainActivity.kt` (1,200+ lines)
- Method channels: `resqlink/wifi` and `resqlink/permissions`
- Socket establishment happens in native code, then Dart creates `SocketProtocol` wrapper

**Key workflow**:

1. Flutter calls `WiFiDirectService.startDiscovery()`
2. Native code broadcasts WiFi Direct presence
3. Peers discovered → `onPeersAvailable` callback → Flutter receives `List<WiFiDirectPeer>`
4. Connection established → `establishSocketConnection()` → Socket server/client setup
5. `SocketProtocol` initialized with group owner IP/port from native side

### 4. Database Transaction Patterns

To prevent deadlocks and race conditions, follow these patterns:

**Always use `DatabaseManager.transaction()` wrapper** (not raw `db.transaction()`):

```dart
await DatabaseManager.transaction((txn) async {
  await txn.insert('table', data);
  await txn.rawUpdate('UPDATE ...');
});
```

**Message deduplication**:

- `MessageRepository._processingMessageIds` prevents concurrent inserts of same message
- `_recentlyProcessed` cache (5min window) prevents duplicates from mesh forwarding
- See `lib/features/database/repositories/message_repository.dart` lines 11-18

**Chat session deduplication**:

- `ChatRepository.cleanupDuplicateSessions()` merges sessions with same participants
- Called on app startup in `main.dart`

### 5. P2P Service Hierarchy

```
P2PMainService (extends P2PBaseService)
├── P2PNetworkService          # Network interface management
├── P2PDiscoveryService         # Device discovery (WiFi Direct, mDNS, broadcast)
├── SocketProtocol              # Message transmission
├── MessageRouter               # Message routing and forwarding
├── P2PWiFiDirectHandler        # WiFi Direct event handling
├── P2PMessageHandler           # Message send/receive logic
├── P2PDeviceManager            # Device tracking and info
├── ConnectionQualityMonitor    # RTT, packet loss tracking
├── ReconnectionManager         # Auto-reconnect with exponential backoff
└── DevicePrioritization        # Score-based device ranking
```

**Service communication**: Uses event bus pattern (`P2PEventBus`) for loose coupling:

- `DeviceConnectionEvent`, `MessageReceivedEvent`, `MessageSendStatusEvent`
- Subscribers in `ChatService` (`_initializeEventListeners()`)

## Development Workflows

### Running the App

```bash
flutter run                    # Development mode
flutter run --release          # Release mode (required for WiFi Direct testing)
```

**Note**: WiFi Direct requires **two physical Android devices** - emulators don't support it. Debug mode may have permission issues; use `--release` for P2P testing.

### Database Migrations

When modifying schema:

1. Increment `_dbVersion` in `lib/features/database/core/database_manager.dart`
2. Add migration logic to `_upgradeDatabase()` function
3. Test with existing data - migrations must preserve user messages/locations

### Testing P2P Features

See `ENHANCED_P2P_FEATURES.md` for test scenarios:

```dart
// Check connection quality
final quality = p2pService.getDeviceQuality(deviceId);
print('RTT: ${quality?.rtt}ms, Loss: ${quality?.packetLoss}%');

// Get prioritized device list
final devices = p2pService.getPrioritizedDevices();

// Monitor reconnection
if (p2pService.isReconnecting(deviceId)) { /* ... */ }
```

## Project-Specific Conventions

### Logging

- **Always use `debugPrint()`**, never `print()` (stripped in release builds)
- Emoji prefixes for log categorization:
  - `🚀` Initialization, `✅` Success, `❌` Error
  - `📡` WiFi/Network, `💾` Database, `📤📥` Message send/receive
  - `🔍` Discovery, `🔌` Socket operations, `🧹` Cleanup

### Error Handling

- All async operations have `try-catch` with `debugPrint` logging
- Network operations have timeouts (e.g., `.timeout(Duration(seconds: 10))`)
- Database operations gracefully degrade (app works in memory-only mode if DB fails)

### State Management

- **Provider** pattern for global state (`ChatService`, `P2PMainService`)
- **StatefulWidget** with controllers for page-level state (`HomeController`, `GPSController`)
- Avoid direct database calls from widgets - use service layer

### File Organization

```
lib/
├── features/           # Feature modules (chat, database, p2p)
│   └── [feature]/
│       ├── services/   # Business logic
│       └── [...]
├── models/             # Data models (message_model, device_model, etc.)
├── pages/              # Full-screen UI pages
├── widgets/            # Reusable UI components
│   └── [context]/      # Grouped by usage context (home/, message/, etc.)
├── services/           # Global services (settings, location, auth)
├── controllers/        # Page-level controllers (not MVC, just state helpers)
└── helpers/            # Utility functions
```

### UI Theme

- **Dark theme only** (`AppTheme.darkTheme`)
- Primary color: Orange (hex: FF6500) - disaster/emergency context
- Fonts: Ubuntu (headings), Inter (body), JetBrains Mono (technical data)
- Material 3 design with custom color scheme

### Firebase Integration

- Optional - app works fully offline if Firebase fails
- `FirebaseDebugService` runs checks in debug mode only
- Sync services wrap Firebase calls in try-catch (see `lib/services/messaging/message_sync_service.dart`)

## Common Pitfalls to Avoid

1. **Don't confuse deviceId (UUID) with endpointId (MAC)** - check identifier usage in models
2. **Don't bypass `DatabaseManager.transaction()`** - causes deadlocks
3. **Don't assume internet connectivity** - all features must work offline
4. **Don't call P2P methods from UI thread** - always use event bus or callbacks
5. **Don't modify WiFi Direct native code without testing on real devices** - emulators crash

## Key Files for Common Tasks

| Task                        | Primary Files                                                                                 |
| --------------------------- | --------------------------------------------------------------------------------------------- |
| Add new message type        | `models/message_model.dart`, `features/database/repositories/message_repository.dart`         |
| Modify P2P connection logic | `services/p2p/handlers/p2p_wifi_direct_handler.dart`, `services/p2p/wifi_direct_service.dart` |
| Change chat UI              | `pages/chat_session_page.dart`, `widgets/message/`                                            |
| Add database table          | `features/database/core/database_manager.dart` (onCreate/onUpgrade)                           |
| Update WiFi Direct native   | `android/app/src/main/kotlin/com/example/resqlink/MainActivity.kt`                            |
| Modify message routing      | `services/messaging/message_router.dart`                                                      |

## External Dependencies

- **Firebase**: Firestore, Auth, Realtime Database (cloud sync)
- **Geolocator**: GPS location tracking (offline capable)
- **SQLite**: Local persistence via `sqflite` package
- **WiFi Direct Plugin**: Native Android P2P (custom fork with enhanced features)
- **Provider**: State management
- **Flutter Map**: Offline map rendering with cached tiles

## Testing Considerations

- **Unit tests**: None currently (thesis project)
- **Integration testing**: Manual on physical devices
- **Firebase emulator**: Not configured - test against live Firebase or offline
- **Performance**: Connection quality monitoring in `P2PEventBus` tracks RTT/packet loss

---

_For detailed feature documentation, see `ENHANCED_P2P_FEATURES.md` and `OBJECTIVES_ACHIEVEMENT_ANALYSIS.md`_
