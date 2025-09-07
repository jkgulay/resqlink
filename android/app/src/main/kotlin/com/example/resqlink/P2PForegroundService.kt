package com.example.resqlink

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

// Remove any duplicate LocationForegroundService class from this file
// Keep only the P2PForegroundService class

class P2PForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "P2P_SERVICE_CHANNEL"
        const val NOTIFICATION_ID = 1001
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        Log.d("P2PForegroundService", "Service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val isEmergencyMode = intent?.getBooleanExtra("emergency_mode", false) ?: false
        val isAutoStart = intent?.getBooleanExtra("auto_start", false) ?: false
        
        Log.d("P2PForegroundService", "Service started - Emergency: $isEmergencyMode, Auto: $isAutoStart")
        
        val notification = createNotification(isEmergencyMode)
        startForeground(NOTIFICATION_ID, notification)
        
        // Start P2P operations here
        startP2POperations(isEmergencyMode)
        
        return START_STICKY // Restart if killed
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "ResQLink P2P Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Manages peer-to-peer connections and emergency communications"
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

        val title = if (isEmergencyMode) "ResQLink - Emergency Mode" else "ResQLink - P2P Active"
        val text = if (isEmergencyMode) 
            "Emergency communication active - Monitoring for nearby devices" 
        else 
            "Peer-to-peer communication ready"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(if (isEmergencyMode) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun startP2POperations(isEmergencyMode: Boolean) {
        Log.d("P2PForegroundService", "Starting P2P operations")
        
        // Save emergency state
        val sharedPrefs = getSharedPreferences("resqlink_prefs", Context.MODE_PRIVATE)
        sharedPrefs.edit()
            .putBoolean("emergency_mode_active", isEmergencyMode)
            .apply()
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d("P2PForegroundService", "Service destroyed")
        
        // Clear emergency state
        val sharedPrefs = getSharedPreferences("resqlink_prefs", Context.MODE_PRIVATE)
        sharedPrefs.edit()
            .putBoolean("emergency_mode_active", false)
            .apply()
    }
}