package com.example.resqlink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.util.Log

class NetworkStateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ConnectivityManager.CONNECTIVITY_ACTION -> {
                handleConnectivityChange(context)
            }
            WifiManager.WIFI_STATE_CHANGED_ACTION -> {
                handleWifiStateChange(intent)
            }
        }
    }

    private fun handleConnectivityChange(context: Context) {
        val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val activeNetwork = connectivityManager.activeNetwork
        val networkCapabilities = connectivityManager.getNetworkCapabilities(activeNetwork)
        
        val isConnected = networkCapabilities != null
        val hasInternet = networkCapabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        val isWifi = networkCapabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        val isCellular = networkCapabilities?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true
        
        Log.d("NetworkStateReceiver", "Network changed - Connected: $isConnected, Internet: $hasInternet, WiFi: $isWifi")
        
        // Send to MainActivity if available
        try {
            val mainActivity = context as? MainActivity
            mainActivity?.sendToFlutter("network", "onNetworkStateChanged", mapOf(
                "isConnected" to isConnected,
                "hasInternet" to hasInternet,
                "isWifi" to isWifi,
                "isCellular" to isCellular
            ))
        } catch (e: Exception) {
            Log.w("NetworkStateReceiver", "Could not send to Flutter", e)
        }
    }

    private fun handleWifiStateChange(intent: Intent) {
        val wifiState = intent.getIntExtra(WifiManager.EXTRA_WIFI_STATE, WifiManager.WIFI_STATE_UNKNOWN)
        val isEnabled = wifiState == WifiManager.WIFI_STATE_ENABLED
        
        Log.d("NetworkStateReceiver", "WiFi state changed: $isEnabled")
    }
}