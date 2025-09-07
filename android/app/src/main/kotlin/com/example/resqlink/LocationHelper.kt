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
    private val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private var isTracking = false
    private var isEmergencyMode = false
    private var lastKnownLocation: Location? = null

    fun startLocationTracking(emergency: Boolean, result: MethodChannel.Result) {
        if (!hasLocationPermission()) {
            result.error("PERMISSION_DENIED", "Location permission required", null)
            return
        }

        if (!isLocationEnabled()) {
            result.error("LOCATION_DISABLED", "Location services are disabled", null)
            return
        }

        try {
            isEmergencyMode = emergency
            isTracking = true

            // Emergency mode: more frequent updates
            val minTime = if (emergency) 10000L else 300000L // 10s vs 5min
            val minDistance = if (emergency) 5f else 50f     // 5m vs 50m

            // GPS provider for highest accuracy
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    minTime,
                    minDistance,
                    this
                )
                Log.d("LocationHelper", "GPS location updates started")
            }

            // Network provider as backup
            if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    minTime * 2, // Less frequent for network
                    minDistance,
                    this
                )
                Log.d("LocationHelper", "Network location updates started")
            }

            // Passive provider for battery efficiency when not in emergency
            if (!emergency && locationManager.isProviderEnabled(LocationManager.PASSIVE_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.PASSIVE_PROVIDER,
                    minTime * 4, // Much less frequent
                    minDistance * 2,
                    this
                )
                Log.d("LocationHelper", "Passive location updates started")
            }

            val resultMap = mapOf(
                "success" to true,
                "emergency" to emergency,
                "interval" to minTime,
                "distance" to minDistance
            )
            result.success(resultMap)
            
        } catch (e: SecurityException) {
            Log.e("LocationHelper", "Security exception starting location tracking", e)
            result.error("SECURITY_EXCEPTION", e.message, null)
        } catch (e: Exception) {
            Log.e("LocationHelper", "Exception starting location tracking", e)
            result.error("LOCATION_ERROR", e.message, null)
        }
    }

    fun stopLocationTracking(result: MethodChannel.Result) {
        try {
            if (isTracking) {
                locationManager.removeUpdates(this)
                isTracking = false
                isEmergencyMode = false
                Log.d("LocationHelper", "Location tracking stopped")
            }
            result.success(true)
        } catch (e: Exception) {
            Log.e("LocationHelper", "Error stopping location tracking", e)
            result.error("STOP_LOCATION_ERROR", e.message, null)
        }
    }

    fun getCurrentLocation(result: MethodChannel.Result) {
        if (!hasLocationPermission()) {
            result.error("PERMISSION_DENIED", "Location permission required", null)
            return
        }

        try {
            // Try to get the most recent location from any provider
            val gpsLocation = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
            val networkLocation = locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            val passiveLocation = locationManager.getLastKnownLocation(LocationManager.PASSIVE_PROVIDER)

            // Choose the most recent and accurate location
            val bestLocation = listOfNotNull(gpsLocation, networkLocation, passiveLocation)
                .maxByOrNull { location ->
                    // Score based on accuracy and recency
                    val accuracyScore = if (location.hasAccuracy()) (100 - location.accuracy).coerceAtLeast(0.0) else 0.0
                    val timeScore = (System.currentTimeMillis() - location.time) / 1000.0 // seconds ago
                    accuracyScore - (timeScore / 60.0) // Prefer recent locations
                }

            if (bestLocation != null) {
                lastKnownLocation = bestLocation
                val locationMap = createLocationMap(bestLocation)
                result.success(locationMap)
            } else {
                result.error("NO_LOCATION", "No location available", null)
            }
        } catch (e: SecurityException) {
            Log.e("LocationHelper", "Security exception getting current location", e)
            result.error("SECURITY_EXCEPTION", e.message, null)
        } catch (e: Exception) {
            Log.e("LocationHelper", "Exception getting current location", e)
            result.error("LOCATION_ERROR", e.message, null)
        }
    }

    fun isLocationEnabled(): Boolean {
        return locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
               locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
    }

    private fun hasLocationPermission(): Boolean {
        return ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
    }

    private fun createLocationMap(location: Location): Map<String, Any> {
        val locationMap = mutableMapOf<String, Any>(
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "timestamp" to location.time,
            "provider" to location.provider
        )

        if (location.hasAccuracy()) {
            locationMap["accuracy"] = location.accuracy.toDouble()
        }
        
        if (location.hasAltitude()) {
            locationMap["altitude"] = location.altitude
        }
        
        if (location.hasSpeed()) {
            locationMap["speed"] = location.speed.toDouble()
        }
        
        if (location.hasBearing()) {
            locationMap["heading"] = location.bearing.toDouble()
        }

        // Add emergency context
        locationMap["isEmergency"] = isEmergencyMode
        locationMap["isTracking"] = isTracking

        return locationMap
    }

    // LocationListener implementation
    override fun onLocationChanged(location: Location) {
        lastKnownLocation = location
        val locationData = createLocationMap(location)
        
        Log.d("LocationHelper", "Location changed: ${location.latitude}, ${location.longitude} (accuracy: ${location.accuracy}m)")
        
        // Send to Flutter
        (context as MainActivity).sendToFlutter("location", "onLocationChanged", locationData)
    }

    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {
        val statusData = mapOf(
            "provider" to (provider ?: "unknown"),
            "status" to status,
            "isEmergency" to isEmergencyMode
        )
        (context as MainActivity).sendToFlutter("location", "onLocationStatusChanged", statusData)
    }

    override fun onProviderEnabled(provider: String) {
        Log.d("LocationHelper", "Location provider enabled: $provider")
        val data = mapOf(
            "provider" to provider,
            "enabled" to true
        )
        (context as MainActivity).sendToFlutter("location", "onLocationProviderChanged", data)
    }

    override fun onProviderDisabled(provider: String) {
        Log.d("LocationHelper", "Location provider disabled: $provider")
        val data = mapOf(
            "provider" to provider,
            "enabled" to false
        )
        (context as MainActivity).sendToFlutter("location", "onLocationProviderChanged", data)
    }
}