# ResQLink User Manual

## Brief Description

ResQLink is an offline emergency communication app for Android. It lets nearby users exchange messages and share locations using WiFi Direct when internet or cellular networks are unavailable. The app is offline-first and saves communication data locally on the device.

## What ResQLink Does

- Creates or joins nearby WiFi Direct groups.
- Discovers nearby ResQLink users and opens direct chat sessions.
- Sends text, voice, emergency, and location messages.
- Supports mesh relay so messages can pass through nearby devices when direct links are unavailable.
- Provides GPS map tools for saving, sharing, and marking emergency-related locations.
- Includes an SOS mode for repeated emergency location broadcasting.

## Device Requirements

- Android physical devices (at least 2 for peer-to-peer testing).
- WiFi enabled.
- Location services enabled.
- Nearby devices and location permissions granted.

Note: Android emulators are not reliable for WiFi Direct workflows.

## Run The App (Developer/Test Setup)

1. Install Flutter SDK and Android toolchain.
2. Connect an Android device via USB (or use wireless debugging).
3. Run:

```bash
flutter pub get
flutter run --release
```

Use release mode for better WiFi Direct behavior during field tests.

## Step-By-Step Usage Guide

### 1. Launch and Enter

1. Open the app.
2. On the landing screen, tap Start Emergency Chat.
3. Complete the emergency auth dialog (if prompted).

### 2. Grant Required Permissions

1. Allow Location permission.
2. Allow Nearby Devices permission.
3. If prompted again, tap GRANT from the in-app banner and retry.

### 3. Set Up Network Connectivity (Home Tab)

Use the Connection and Discovery section:

- Create WiFi Direct Group:
  - Use this on one device to act as host.
  - Button: Create WiFi Direct Group.
- Join WiFi Direct Group:
  - Use this on other devices to scan and join host groups.
  - Button: Join WiFi Direct Group.
- Cancel Scan:
  - Stops active discovery.
- Leave/Disband Group:
  - If host: Disband Group.
  - If client: Leave Group.

The card also shows:

- Discovered device count
- Connected device count
- WiFi Direct status (Ready, Scanning, Active)

### 4. Connect To A Device

1. In discovered devices, tap Connect on a target peer.
2. After connection succeeds, use Chat from connected device actions.
3. You can also open device details from the info button.

### 5. Use Chat (Chat Tab)

1. Open Chat tab.
2. Select a conversation or start from connected device actions.
3. Send messages:
   - Text: type then send.
   - Voice: tap mic to record, tap send to transmit.
   - Location message: tap location button.
4. If peer is unreachable, messages are stored locally and retried/queued by the app logic.
5. Chat options menu:
   - Clear Chat for the current conversation.

Chat status indicators:

- Direct link: peer is directly connected.
- Relay via mesh: message can route through intermediate peers.
- Offline: no route currently available.

### 6. Use Emergency Actions (Home Tab)

When connected, quick templates are available:

- SOS
- Trapped
- Medical
- Safe

These send preformatted emergency messages to connected peers.

### 7. Use GPS and Map Tools (Location Tab)

Main capabilities:

- Center on current location (target icon).
- Share current location to connected devices.
- Download/update/delete offline maps.
- Tap saved locations to focus map.
- Share or delete saved locations from the bottom panel.
- Long-press map to mark location type:
  - Current Location
  - Emergency Location
  - SOS Location
  - Safe Zone
  - Hazard Area
  - Evacuation Point
  - Medical Aid
  - Supplies

### 8. Use SOS Broadcast Mode

1. In Location tab, tap the red emergency floating button.
2. Confirm Activate SOS.
3. App starts repeated emergency location broadcasts.
4. Tap again and confirm I'm Safe to stop SOS mode.

### 9. Configure App Behavior (Settings Tab)

Available sections:

- Statistics:
  - Messages, sessions, locations, active connections, storage.
- Location Services:
  - Toggle Location Sharing.
  - Open app settings for permission management.
- Notifications:
  - Emergency Notifications
  - Sound Notifications
  - Vibration
  - Silent Mode
- Data Management:
  - Merge Duplicate Sessions
  - Clear Chat History
- Account:
  - About ResQLink
  - Logout

## Recommended Field Workflow

1. Choose one responder device as host and create group.
2. Have all other devices join the host group.
3. Verify connected peers in Home tab.
4. Send a short test message to confirm routing.
5. Share location updates periodically from Location tab.
6. Use emergency templates and SOS mode only when required.

## Troubleshooting

### No devices found

- Ensure WiFi and Location are enabled on all devices.
- Re-run Join WiFi Direct Group scan.
- Keep devices physically close.

### Cannot connect

- Confirm permissions were granted.
- If already in another group, leave/disband first.
- Retry scan and connect.

### Cannot send location

- Enable GPS/location services.
- Grant location permission in system settings.

### Messages not delivering immediately

- Check chat status (Direct link / Relay via mesh / Offline).
- Keep app open while restoring nearby connectivity.

## Data and Privacy Notes

- Primary operation is offline-first with local database storage.
- Message and location data are retained on-device for resilience during outages.

## Project Status

ResQLink is under active development as part of a university thesis focused on resilient disaster communication.

## License

ResQLink is proprietary software with a non-commercial license.

- No commercial use.
- No derivative works without permission.
- Academic/reference use only under license terms.

Read full terms in [LICENSE](LICENSE).
