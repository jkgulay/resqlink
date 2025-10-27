# GPS Accuracy Improvements for ResQLink

## ✅ Implemented Changes

### 1. **Upgraded Location Accuracy**

- Changed from `LocationAccuracy.high` to `LocationAccuracy.bestForNavigation`
- This uses the highest accuracy possible (typically 1-5 meters)
- Battery impact is higher but critical for disaster response

### 2. **Reduced Distance Filter**

- Changed from 10m to 5m for normal tracking
- Changed from 20m to 10m for stationary
- Changed from 5m to 3m for moving
- Smaller values = more frequent updates = better accuracy

### 3. **Increased Time Limit**

- Changed from 5 to 10 seconds
- Gives GPS more time to get a precise fix

## 📋 Additional Accuracy Tips

### Hardware Level

1. **Ensure Clear Sky View**

   - GPS accuracy improves significantly outdoors
   - Buildings, trees, and tunnels degrade signal
   - Best accuracy in open areas

2. **Enable High Accuracy Mode**

   - Go to Android Settings → Location → Mode
   - Select "High accuracy" (uses GPS + WiFi + mobile networks)

3. **A-GPS (Assisted GPS)**
   - Requires internet connection
   - Downloads satellite data faster
   - Significantly reduces time-to-first-fix

### Software Level

4. **Location Accuracy Levels** (in order of accuracy):

```dart
LocationAccuracy.bestForNavigation  // ~1-5m (IMPLEMENTED ✅)
LocationAccuracy.best               // ~5-10m
LocationAccuracy.high               // ~10-100m
LocationAccuracy.medium             // ~100-500m
LocationAccuracy.low                // ~500m-5km
LocationAccuracy.lowest             // >5km
```

5. **Distance Filter** (meters):

```dart
distanceFilter: 0   // Update on every position change (most accurate, drains battery)
distanceFilter: 3   // Update every 3 meters (IMPLEMENTED for moving ✅)
distanceFilter: 5   // Update every 5 meters (IMPLEMENTED ✅)
distanceFilter: 10  // Update every 10 meters (IMPLEMENTED for stationary ✅)
```

6. **Position Filtering** (reduce GPS jitter):

```dart
// Kalman filter or moving average can smooth GPS readings
// Useful if you see the marker "jumping" on the map
```

### Android Manifest Settings

Ensure `android/app/src/main/AndroidManifest.xml` has:

```xml
<!-- For best GPS accuracy -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

<!-- For A-GPS support -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

### Flutter Map Accuracy

7. **Map Tile Resolution**

```dart
// Use higher zoom levels for better detail
initialZoom: 18.0  // Very detailed street level
maxZoom: 19.0     // Maximum detail
```

8. **Marker Precision**

```dart
// Show accuracy circle around current location
Container(
  width: accuracy * 2, // accuracy from Position.accuracy
  decoration: BoxDecoration(
    shape: BoxShape.circle,
    color: Colors.blue.withOpacity(0.1),
    border: Border.all(color: Colors.blue),
  ),
)
```

## 🔋 Battery vs Accuracy Trade-offs

Current implementation:

- **High Battery (>20%)**: `bestForNavigation`, 5m filter, 10s timeout
- **Low Battery (<20%)**: `medium`, 20m filter, 10s timeout
- **SOS Mode**: Updates every 15 seconds regardless of battery

## 🎯 Expected Accuracy

| Condition              | Expected Accuracy |
| ---------------------- | ----------------- |
| Open sky, stationary   | 1-3 meters        |
| Open sky, moving       | 3-10 meters       |
| Urban area, clear view | 5-15 meters       |
| Near buildings         | 10-30 meters      |
| Indoor/weak signal     | 50-500 meters     |

## 🛠️ Troubleshooting Poor Accuracy

1. **Check GPS Status**

   ```dart
   Position position = await Geolocator.getCurrentPosition();
   print('Accuracy: ${position.accuracy} meters');
   print('Satellites: ${position.satelliteCount}'); // If available
   ```

2. **Verify Permissions**

   - Ensure "Allow all the time" for location (not "While using app")
   - This is critical for disaster response scenarios

3. **Cold Start Issue**

   - First GPS fix after boot can take 30-60 seconds
   - Keep app open for better accuracy over time

4. **Mock Locations**
   - Disable "Mock location apps" in Developer Options
   - Can interfere with real GPS

## 📊 Testing Accuracy

Compare with known locations:

1. Stand at a known landmark (corner of building, statue, etc.)
2. Note GPS coordinates from app
3. Check coordinates on Google Maps
4. Calculate deviation

Good accuracy: < 5 meters
Acceptable: 5-15 meters
Poor: > 15 meters

## 🚀 Future Enhancements

Consider implementing:

- [ ] Kalman filter for GPS smoothing
- [ ] Compass integration for heading accuracy
- [ ] GNSS (GPS + GLONASS + Galileo + BeiDou) support
- [ ] RTK (Real-Time Kinematic) for cm-level accuracy (requires base station)
- [ ] Display accuracy circle on map
- [ ] GPS signal strength indicator
- [ ] Satellite count display
