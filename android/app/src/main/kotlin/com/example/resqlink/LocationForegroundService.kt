package com.example.resqlink

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

class LocationForegroundService : Service(), LocationListener {
    companion object {
        const val CHANNEL_ID = "LOCATION_SERVICE_CHANNEL"
        const val NOTIFICATION_ID = 1002
    }

    private lateinit var locationManager: LocationManager
    private var isTracking = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        Log.d("LocationForegroundService", "Service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val isEmergencyMode = intent?.getBooleanExtra("emergency_mode", false) ?: false
        
        Log.d("LocationForegroundService", "Location service started - Emergency: $isEmergencyMode")
        
        val notification = createNotification(isEmergencyMode)
        startForeground(NOTIFICATION_ID, notification)
        
        startLocationTracking(isEmergencyMode)
        
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "ResQLink Location Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Tracks location for emergency communication"
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(isEmergencyMode: Boolean): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val title = if (isEmergencyMode) "ResQLink - Emergency Location" else "ResQLink - Location Tracking"
        val text = if (isEmergencyMode) 
            "Tracking location for emergency response" 
        else 
            "Background location tracking active"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(if (isEmergencyMode) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun startLocationTracking(isEmergencyMode: Boolean) {
        try {
            val minTime = if (isEmergencyMode) 10000L else 300000L // 10s vs 5min
            val minDistance = if (isEmergencyMode) 5f else 50f     // 5m vs 50m

            // GPS provider
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    minTime,
                    minDistance,
                    this
                )
            }

            // Network provider as backup
            if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    minTime * 2,
                    minDistance,
                    this
                )
            }

            isTracking = true
            Log.d("LocationForegroundService", "Location tracking started")
        } catch (e: SecurityException) {
            Log.e("LocationForegroundService", "Security exception starting location tracking", e)
        }
    }

    override fun onLocationChanged(location: Location) {
        Log.d("LocationForegroundService", "Location updated: ${location.latitude}, ${location.longitude}")
        
        // Send location update to your database or P2P service
        // You can integrate this with your LocationHelper or DatabaseService
    }

    override fun onProviderEnabled(provider: String) {
        Log.d("LocationForegroundService", "Location provider enabled: $provider")
    }

    override fun onProviderDisabled(provider: String) {
        Log.d("LocationForegroundService", "Location provider disabled: $provider")
    }

    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {
        Log.d("LocationForegroundService", "Location provider status changed: $provider")
    }

    override fun onDestroy() {
        super.onDestroy()
        if (isTracking) {
            locationManager.removeUpdates(this)
            isTracking = false
        }
        Log.d("LocationForegroundService", "Location service destroyed")
    }
}