package com.example.resqlink

import android.content.Context
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.util.Log

class WiFiDirectDiagnostic(private val context: Context) {

    companion object {
        private const val TAG = "WiFiDirectDiagnostic"
    }

    fun runFullDiagnostic(): Map<String, Any> {
        Log.d(TAG, "=== WiFi Direct Full Diagnostic ===")

        val diagnosticResults = mutableMapOf<String, Any>()

        // Device info
        diagnosticResults["deviceInfo"] = getDeviceInfo()

        // Hardware support
        diagnosticResults["hardwareSupport"] = checkHardwareSupport()

        // Permission status
        diagnosticResults["permissions"] = checkPermissions()

        // WiFi status
        diagnosticResults["wifiStatus"] = checkWifiStatus()

        // System services
        diagnosticResults["systemServices"] = checkSystemServices()

        Log.d(TAG, "Diagnostic Results: $diagnosticResults")
        return diagnosticResults
    }

    private fun getDeviceInfo(): Map<String, Any> {
        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "device" to Build.DEVICE,
            "androidVersion" to Build.VERSION.SDK_INT,
            "androidRelease" to Build.VERSION.RELEASE
        )
    }

    private fun checkHardwareSupport(): Map<String, Boolean> {
        val packageManager = context.packageManager

        return mapOf(
            "wifiDirectSupport" to packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT),
            "wifiSupport" to packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI),
            "locationSupport" to packageManager.hasSystemFeature(PackageManager.FEATURE_LOCATION),
            "locationGpsSupport" to packageManager.hasSystemFeature(PackageManager.FEATURE_LOCATION_GPS),
            "locationNetworkSupport" to packageManager.hasSystemFeature(PackageManager.FEATURE_LOCATION_NETWORK)
        )
    }

    private fun checkPermissions(): Map<String, Any> {
        val permissionHelper = PermissionHelper(context as MainActivity)

        val permissions = mutableMapOf<String, Any>()
        permissions["locationPermission"] = permissionHelper.hasLocationPermission()
        permissions["nearbyDevicesPermission"] = permissionHelper.hasNearbyDevicesPermission()
        permissions["wifiDirectReady"] = permissionHelper.hasAllWifiDirectPermissions()
        permissions["allPermissions"] = permissionHelper.checkAllPermissions()

        return permissions
    }

    private fun checkWifiStatus(): Map<String, Any> {
        val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

        return mapOf(
            "wifiEnabled" to wifiManager.isWifiEnabled,
            "wifiState" to wifiManager.wifiState,
            "connectionInfo" to mapOf(
                "ssid" to (wifiManager.connectionInfo?.ssid ?: "none"),
                "bssid" to (wifiManager.connectionInfo?.bssid ?: "none"),
                "networkId" to (wifiManager.connectionInfo?.networkId ?: -1),
                "frequency" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    wifiManager.connectionInfo?.frequency ?: -1
                } else {
                    -1
                }
            )
        )
    }

    private fun checkSystemServices(): Map<String, Boolean> {
        return mapOf(
            "wifiServiceAvailable" to (context.getSystemService(Context.WIFI_SERVICE) != null),
            "wifiP2pServiceAvailable" to (context.getSystemService(Context.WIFI_P2P_SERVICE) != null),
            "locationServiceAvailable" to (context.getSystemService(Context.LOCATION_SERVICE) != null)
        )
    }

    fun logDetailedStatus() {
        Log.d(TAG, "=== Detailed WiFi Direct Status ===")

        val diagnostic = runFullDiagnostic()

        Log.d(TAG, "Device: ${Build.MANUFACTURER} ${Build.MODEL} (API ${Build.VERSION.SDK_INT})")

        val hardware = diagnostic["hardwareSupport"] as Map<String, Boolean>
        Log.d(TAG, "Hardware Support:")
        hardware.forEach { (key, value) -> Log.d(TAG, "  - $key: $value") }

        val permissions = diagnostic["permissions"] as Map<String, Any>
        Log.d(TAG, "Permissions:")
        Log.d(TAG, "  - Location: ${permissions["locationPermission"]}")
        Log.d(TAG, "  - Nearby Devices: ${permissions["nearbyDevicesPermission"]}")
        Log.d(TAG, "  - WiFi Direct Ready: ${permissions["wifiDirectReady"]}")

        val wifi = diagnostic["wifiStatus"] as Map<String, Any>
        Log.d(TAG, "WiFi Status:")
        Log.d(TAG, "  - Enabled: ${wifi["wifiEnabled"]}")
        Log.d(TAG, "  - State: ${wifi["wifiState"]}")

        val services = diagnostic["systemServices"] as Map<String, Boolean>
        Log.d(TAG, "System Services:")
        services.forEach { (key, value) -> Log.d(TAG, "  - $key: $value") }

        // Recommendations
        val recommendations = generateRecommendations(diagnostic)
        if (recommendations.isNotEmpty()) {
            Log.w(TAG, "=== Recommendations ===")
            recommendations.forEach { Log.w(TAG, "⚠️ $it") }
        }
    }

    private fun generateRecommendations(diagnostic: Map<String, Any>): List<String> {
        val recommendations = mutableListOf<String>()

        val hardware = diagnostic["hardwareSupport"] as Map<String, Boolean>
        val permissions = diagnostic["permissions"] as Map<String, Any>
        val wifi = diagnostic["wifiStatus"] as Map<String, Any>

        if (hardware["wifiDirectSupport"] != true) {
            recommendations.add("WiFi Direct not supported on this device - discovery will fail")
        }

        if (wifi["wifiEnabled"] != true) {
            recommendations.add("WiFi is disabled - enable WiFi for device discovery")
        }

        if (permissions["locationPermission"] != true) {
            recommendations.add("Location permission required for WiFi Direct discovery")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && permissions["nearbyDevicesPermission"] != true) {
            recommendations.add("NEARBY_WIFI_DEVICES permission required on Android 13+")
        }

        return recommendations
    }
}