package com.example.resqlink

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel

class LocationHelper(private val context: Context) : LocationListener {
    private val locationManager =
        context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private var methodChannel: MethodChannel? = null

    fun setMethodChannel(channel: MethodChannel) {
        this.methodChannel = channel
    }

    private fun hasLocationPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    // ✅ Added wrapper to support MainActivity
    fun startLocationTracking(isEmergency: Boolean, result: MethodChannel.Result) {
        if (!hasLocationPermission()) {
            result.error("PERMISSION_DENIED", "Location permission not granted", null)
            return
        }

        try {
            val minTimeGps: Long = if (isEmergency) 2000L else 10000L
            val minDistanceGps: Float = if (isEmergency) 2.0f else 10.0f
            val minTimeNetwork: Long = if (isEmergency) 5000L else 30000L
            val minDistanceNetwork: Float = if (isEmergency) 5.0f else 50.0f

            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                minTimeGps,
                minDistanceGps,
                this
            )

            locationManager.requestLocationUpdates(
                LocationManager.NETWORK_PROVIDER,
                minTimeNetwork,
                minDistanceNetwork,
                this
            )

            result.success(true)
        } catch (e: SecurityException) {
            result.error("LOCATION_ERROR", "Failed to request location updates", e.message)
        }
    }

    // ✅ Matches MainActivity
    fun stopLocationTracking(result: MethodChannel.Result) {
        try {
            locationManager.removeUpdates(this)
            result.success(true)
        } catch (e: Exception) {
            result.error("LOCATION_ERROR", "Failed to stop location updates", e.message)
        }
    }

    // ✅ Matches MainActivity
    fun isLocationEnabled(): Boolean {
        return locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
    }

    fun getCurrentLocation(result: MethodChannel.Result) {
        if (!hasLocationPermission()) {
            result.error("PERMISSION_DENIED", "Location permission not granted", null)
            return
        }

        try {
            val location = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                ?: locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)

            if (location != null) {
                val locationMap = getLocationMap(location)
                result.success(locationMap)
            } else {
                result.error("LOCATION_UNAVAILABLE", "No location available", null)
            }
        } catch (e: SecurityException) {
            result.error("LOCATION_ERROR", "Security exception: ${e.message}", null)
        }
    }

    private fun getLocationMap(location: Location): Map<String, Any?> {
        val locationMap = mutableMapOf<String, Any?>()

        locationMap["latitude"] = location.latitude
        locationMap["longitude"] = location.longitude
        locationMap["accuracy"] = location.accuracy.toDouble()
        locationMap["timestamp"] = location.time

        if (location.hasAltitude()) {
            locationMap["altitude"] = location.altitude
        }

        if (location.hasSpeed()) {
            locationMap["speed"] = location.speed.toDouble()
        }

        if (location.hasBearing()) {
            locationMap["bearing"] = location.bearing.toDouble()
        }

        // Calculate age of location
        val currentTime = System.currentTimeMillis()
        val locationTime = location.time
        val timeDifference = currentTime - locationTime
        locationMap["age"] = timeDifference

        return locationMap
    }

    fun sendLocationUpdate(location: Location, result: MethodChannel.Result) {
        val locationData = getLocationMap(location)
        val responseMap = mapOf("location" to locationData)
        result.success(responseMap)
    }

    // LocationListener methods
    override fun onLocationChanged(location: Location) {
        Log.d("LocationHelper", "Location changed: ${location.latitude}, ${location.longitude}")
        val locationData = getLocationMap(location)
        methodChannel?.invokeMethod("onLocationChanged", locationData)
    }

    override fun onProviderEnabled(provider: String) {
        Log.d("LocationHelper", "Location provider enabled: $provider")
        methodChannel?.invokeMethod("onProviderEnabled", provider)
    }

    override fun onProviderDisabled(provider: String) {
        Log.d("LocationHelper", "Location provider disabled: $provider")
        methodChannel?.invokeMethod("onProviderDisabled", provider)
    }

    @Deprecated("Deprecated in Java")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {
        Log.d("LocationHelper", "Location provider status changed: $provider, status: $status")
    }
}
