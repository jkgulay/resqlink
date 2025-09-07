package com.example.resqlink

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel

class PermissionHelper(private val activity: Activity) {
    
    fun checkWifiDirectSupport(): Boolean {
        return activity.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT)
    }

    fun hasLocationPermission(): Boolean {
        val fineLocation = ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val coarseLocation = ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        return fineLocation && coarseLocation
    }

    fun hasNearbyDevicesPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(activity, Manifest.permission.NEARBY_WIFI_DEVICES) == PackageManager.PERMISSION_GRANTED
        } else {
            true // Not required on older versions
        }
    }

    fun requestLocationPermission() {
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !hasNearbyDevicesPermission()) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES),
                MainActivity.REQUEST_CODE_NEARBY_DEVICES
            )
        }
    }

    fun requestAllPermissions() {
        val permissionsToRequest = mutableListOf<String>()
        
        if (!hasLocationPermission()) {
            permissionsToRequest.addAll(listOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ))
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !hasNearbyDevicesPermission()) {
            permissionsToRequest.add(Manifest.permission.NEARBY_WIFI_DEVICES)
        }
        
        if (permissionsToRequest.isNotEmpty()) {
            ActivityCompat.requestPermissions(
                activity,
                permissionsToRequest.toTypedArray(),
                MainActivity.REQUEST_CODE_WIFI
            )
        }
    }

    fun checkAllPermissions(): Map<String, Boolean> {
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
        
        return permissions
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        when (requestCode) {
            MainActivity.REQUEST_CODE_LOCATION -> {
                val locationGranted = grantResults.isNotEmpty() && 
                    grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                sendPermissionResult("location", locationGranted)
            }
            MainActivity.REQUEST_CODE_NEARBY_DEVICES -> {
                val nearbyDevicesGranted = grantResults.isNotEmpty() && 
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
                sendPermissionResult("nearbyDevices", nearbyDevicesGranted)
            }
            MainActivity.REQUEST_CODE_WIFI -> {
                // Handle multiple permissions
                for (i in permissions.indices) {
                    val permission = permissions[i]
                    val granted = grantResults[i] == PackageManager.PERMISSION_GRANTED
                    
                    when (permission) {
                        Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION -> {
                            sendPermissionResult("location", hasLocationPermission())
                        }
                        Manifest.permission.NEARBY_WIFI_DEVICES -> {
                            sendPermissionResult("nearbyDevices", granted)
                        }
                    }
                }
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