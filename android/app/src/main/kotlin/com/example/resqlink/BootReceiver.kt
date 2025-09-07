package com.example.resqlink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> {
                Log.d("BootReceiver", "Device boot completed")
                handleBootCompleted(context)
            }
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_PACKAGE_REPLACED -> {
                Log.d("BootReceiver", "Package replaced")
                handlePackageReplaced(context)
            }
        }
    }

    private fun handleBootCompleted(context: Context) {
        // Check if emergency mode was active before shutdown
        val sharedPrefs = context.getSharedPreferences("resqlink_prefs", Context.MODE_PRIVATE)
        val wasEmergencyActive = sharedPrefs.getBoolean("emergency_mode_active", false)
        
        if (wasEmergencyActive) {
            Log.d("BootReceiver", "Restoring emergency mode after boot")
            // Start emergency services
            startEmergencyServices(context)
        }
    }

    private fun handlePackageReplaced(context: Context) {
        // Handle app updates - restore any persistent emergency state
        Log.d("BootReceiver", "ResQLink package updated")
    }

    private fun startEmergencyServices(context: Context) {
        try {
            // Start foreground service for emergency mode
            val serviceIntent = Intent(context, P2PForegroundService::class.java).apply {
                putExtra("emergency_mode", true)
                putExtra("auto_start", true)
            }
            context.startForegroundService(serviceIntent)
        } catch (e: Exception) {
            Log.e("BootReceiver", "Failed to start emergency services", e)
        }
    }
}