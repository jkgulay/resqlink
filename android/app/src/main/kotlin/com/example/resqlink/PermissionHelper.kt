package com.example.resqlink

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel

class PermissionHelper(private val activity: Activity) {

    companion object {
        private const val TAG = "PermissionHelper"
    }

    fun checkWifiDirectSupport(): Boolean {
        val hasFeature = activity.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT)
        android.util.Log.d(TAG, "WiFi Direct hardware support: $hasFeature")
        return hasFeature
    }

    fun hasLocationPermission(): Boolean {
        val fineLocation = ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val coarseLocation = ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val hasLocation = fineLocation && coarseLocation
        android.util.Log.d(TAG, "Location permission - Fine: $fineLocation, Coarse: $coarseLocation, Has Both: $hasLocation")
        return hasLocation
    }

    fun hasNearbyDevicesPermission(): Boolean {
        val hasPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(activity, Manifest.permission.NEARBY_WIFI_DEVICES) == PackageManager.PERMISSION_GRANTED
        } else {
            true // Not required on older versions
        }
        android.util.Log.d(TAG, "Nearby devices permission (API ${Build.VERSION.SDK_INT}): $hasPermission")
        return hasPermission
    }

    fun requestWifiDirectPermissions(): Boolean {
        android.util.Log.d(TAG, "=== WiFi Direct Permission Check ===")

        val permissionsToRequest = mutableListOf<String>()

        // Always request location permissions for WiFi Direct
        if (!hasLocationPermission()) {
            android.util.Log.d(TAG, "Adding location permissions to request")
            permissionsToRequest.addAll(listOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ))
        }

        // Add nearby devices permission for Android 13+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !hasNearbyDevicesPermission()) {
            android.util.Log.d(TAG, "Adding NEARBY_WIFI_DEVICES permission to request (API 33+)")
            permissionsToRequest.add(Manifest.permission.NEARBY_WIFI_DEVICES)
        }

        if (permissionsToRequest.isNotEmpty()) {
            android.util.Log.d(TAG, "Requesting ${permissionsToRequest.size} permissions: ${permissionsToRequest.joinToString(", ")}")
            ActivityCompat.requestPermissions(
                activity,
                permissionsToRequest.toTypedArray(),
                MainActivity.REQUEST_CODE_WIFI
            )
            return false // Permissions requested, wait for callback
        } else {
            android.util.Log.d(TAG, "All WiFi Direct permissions already granted")
            return true // All permissions already granted
        }
    }

    fun requestLocationPermission() {
        android.util.Log.d(TAG, "Requesting location permissions individually")
        if (!hasLocationPermission()) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                ),
                MainActivity.REQUEST_CODE_LOCATION
            )
        }
    }

    fun requestNearbyDevicesPermission() {
        android.util.Log.d(TAG, "Requesting nearby devices permission individually")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !hasNearbyDevicesPermission()) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES),
                MainActivity.REQUEST_CODE_NEARBY_DEVICES
            )
        }
    }

    fun hasAllWifiDirectPermissions(): Boolean {
        val hasLocation = hasLocationPermission()
        val hasNearbyDevices = hasNearbyDevicesPermission()
        val hasSupport = checkWifiDirectSupport()

        android.util.Log.d(TAG, "WiFi Direct readiness - Location: $hasLocation, NearbyDevices: $hasNearbyDevices, HWSupport: $hasSupport")
        return hasLocation && hasNearbyDevices && hasSupport
    }

    fun checkAllPermissions(): Map<String, Boolean> {
        android.util.Log.d(TAG, "Checking all permissions...")
        val permissions = mutableMapOf<String, Boolean>()

        permissions["location"] = hasLocationPermission()
        permissions["wifi"] = true // WiFi permission is automatically granted
        permissions["wifiDirect"] = checkWifiDirectSupport()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions["nearbyDevices"] = hasNearbyDevicesPermission()
        } else {
            permissions["nearbyDevices"] = true
        }

        // Additional permissions for emergency features
        permissions["camera"] = ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        permissions["microphone"] = ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        permissions["storage"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            true // MANAGE_EXTERNAL_STORAGE not needed for scoped storage
        } else {
            ContextCompat.checkSelfPermission(activity, Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }

        android.util.Log.d(TAG, "Permission status: $permissions")
        return permissions
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        android.util.Log.d(TAG, "=== Permission Results ===")
        android.util.Log.d(TAG, "Request code: $requestCode")
        android.util.Log.d(TAG, "Permissions: ${permissions.joinToString(", ")}")
        android.util.Log.d(TAG, "Grant results: ${grantResults.joinToString(", ")}")

        when (requestCode) {
            MainActivity.REQUEST_CODE_LOCATION -> {
                val locationGranted = grantResults.isNotEmpty() &&
                    grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                android.util.Log.d(TAG, "Location permission result: $locationGranted")
                sendPermissionResult("location", locationGranted)
            }
            MainActivity.REQUEST_CODE_NEARBY_DEVICES -> {
                val nearbyDevicesGranted = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
                android.util.Log.d(TAG, "Nearby devices permission result: $nearbyDevicesGranted")
                sendPermissionResult("nearbyDevices", nearbyDevicesGranted)
            }
            MainActivity.REQUEST_CODE_WIFI -> {
                android.util.Log.d(TAG, "Processing WiFi Direct permissions batch result...")

                // Track results for each permission type
                var locationPermissionsGranted = true
                var nearbyDevicesGranted = true

                for (i in permissions.indices) {
                    val permission = permissions[i]
                    val granted = grantResults.getOrNull(i) == PackageManager.PERMISSION_GRANTED

                    android.util.Log.d(TAG, "Permission $permission: $granted")

                    when (permission) {
                        Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION -> {
                            if (!granted) locationPermissionsGranted = false
                        }
                        Manifest.permission.NEARBY_WIFI_DEVICES -> {
                            nearbyDevicesGranted = granted
                        }
                    }
                }

                // Re-check actual permission status (in case of partial grants)
                val finalLocationStatus = hasLocationPermission()
                val finalNearbyDevicesStatus = hasNearbyDevicesPermission()

                android.util.Log.d(TAG, "Final status - Location: $finalLocationStatus, NearbyDevices: $finalNearbyDevicesStatus")

                // Send individual results
                sendPermissionResult("location", finalLocationStatus)
                sendPermissionResult("nearbyDevices", finalNearbyDevicesStatus)

                // Send overall WiFi Direct readiness
                val wifiDirectReady = hasAllWifiDirectPermissions()
                android.util.Log.d(TAG, "WiFi Direct ready: $wifiDirectReady")
                sendPermissionResult("wifiDirectReady", wifiDirectReady)
            }
        }
    }

    private fun sendPermissionResult(permission: String, granted: Boolean) {
        val data = mapOf(
            "permission" to permission,
            "granted" to granted
        )
        (activity as MainActivity).sendToFlutter("permission", "onPermissionResult", data)
    }
}