package com.example.resqlink

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.lang.reflect.Method

class WiFiManagerPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: android.app.Activity? = null
    private var wifiManager: WifiManager? = null
    private var connectivityManager: ConnectivityManager? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "resqlink/wifi")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
        
        wifiManager = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
        connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "createHotspot" -> {
                val ssid = call.argument<String>("ssid")
                val password = call.argument<String>("password")
                createHotspot(ssid, password, result)
            }
            "connectToWiFi" -> {
                val ssid = call.argument<String>("ssid")
                val password = call.argument<String>("password")
                connectToWiFi(ssid, password, result)
            }
            "scanWifi" -> scanWiFi(result)
            "getCurrentWiFi" -> getCurrentWiFi(result)
            "getHotspotInfo" -> getHotspotInfo(result)
            else -> result.notImplemented()
        }
    }

    private fun createHotspot(ssid: String?, password: String?, result: Result) {
        if (ssid == null || password == null) {
            result.error("INVALID_ARGS", "SSID and password are required", null)
            return
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Android 8.0+ - Use WifiManager.LocalOnlyHotspotReservation
                createModernHotspot(ssid, password, result)
            } else {
                // Legacy method for older Android versions
                createLegacyHotspot(ssid, password, result)
            }
        } catch (e: Exception) {
            result.error("HOTSPOT_ERROR", "Failed to create hotspot: ${e.message}", null)
        }
    }

    private fun createModernHotspot(ssid: String, password: String, result: Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                // Request LocalOnlyHotspot
                wifiManager?.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                    override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation?) {
                        reservation?.let {
                            val config = it.wifiConfiguration
                            result.success(mapOf(
                                "success" to true,
                                "ssid" to (config?.SSID ?: ssid),
                                "password" to (config?.preSharedKey ?: password),
                                "message" to "Hotspot created successfully"
                            ))
                        } ?: result.error("HOTSPOT_ERROR", "Failed to get hotspot configuration", null)
                    }

                    override fun onStopped() {
                        // Hotspot stopped
                    }

                    override fun onFailed(reason: Int) {
                        val errorMsg = when (reason) {
                            ERROR_INCOMPATIBLE_MODE -> "Incompatible mode"
                            ERROR_NO_CHANNEL -> "No channel available"
                            ERROR_GENERIC -> "Generic error"
                            ERROR_TETHERING_DISALLOWED -> "Tethering not allowed"
                            else -> "Unknown error: $reason"
                        }
                        result.error("HOTSPOT_FAILED", errorMsg, null)
                    }
                }, null)
            } catch (e: SecurityException) {
                result.error("PERMISSION_DENIED", "Location permission required for hotspot", null)
            }
        }
    }

    private fun createLegacyHotspot(ssid: String, password: String, result: Result) {
        try {
            // Legacy method using reflection (Android 7.1 and below)
            val wifiConfig = WifiConfiguration().apply {
                SSID = ssid
                preSharedKey = password
                allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
            }

            // Use reflection to access hidden API
            val method: Method = wifiManager!!.javaClass.getMethod(
                "setWifiApEnabled",
                WifiConfiguration::class.java,
                Boolean::class.java
            )
            
            val success = method.invoke(wifiManager, wifiConfig, true) as Boolean
            
            if (success) {
                result.success(mapOf(
                    "success" to true,
                    "ssid" to ssid,
                    "password" to password,
                    "message" to "Legacy hotspot created"
                ))
            } else {
                result.error("HOTSPOT_FAILED", "Failed to enable legacy hotspot", null)
            }
        } catch (e: Exception) {
            result.error("REFLECTION_ERROR", "Legacy hotspot failed: ${e.message}", null)
        }
    }

    private fun connectToWiFi(ssid: String?, password: String?, result: Result) {
        if (ssid == null || password == null) {
            result.error("INVALID_ARGS", "SSID and password are required", null)
            return
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10+ - Use WifiNetworkSpecifier
                connectModernWiFi(ssid, password, result)
            } else {
                // Legacy method
                connectLegacyWiFi(ssid, password, result)
            }
        } catch (e: Exception) {
            result.error("WIFI_ERROR", "Failed to connect: ${e.message}", null)
        }
    }

    private fun connectModernWiFi(ssid: String, password: String, result: Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val specifier = WifiNetworkSpecifier.Builder()
                .setSsid(ssid)
                .setWpa2Passphrase(password)
                .build()

            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .setNetworkSpecifier(specifier)
                .build()

            val networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    result.success(mapOf(
                        "success" to true,
                        "message" to "Connected to $ssid"
                    ))
                }

                override fun onUnavailable() {
                    result.error("CONNECTION_FAILED", "Failed to connect to $ssid", null)
                }
            }

            connectivityManager?.requestNetwork(request, networkCallback, 30000)
        }
    }

    private fun connectLegacyWiFi(ssid: String, password: String, result: Result) {
        try {
            val wifiConfig = WifiConfiguration().apply {
                SSID = "\"$ssid\""
                preSharedKey = "\"$password\""
                allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
                allowedGroupCiphers.set(WifiConfiguration.GroupCipher.TKIP)
                allowedGroupCiphers.set(WifiConfiguration.GroupCipher.CCMP)
                allowedProtocols.set(WifiConfiguration.Protocol.RSN)
                allowedProtocols.set(WifiConfiguration.Protocol.WPA)
                allowedPairwiseCiphers.set(WifiConfiguration.PairwiseCipher.TKIP)
                allowedPairwiseCiphers.set(WifiConfiguration.PairwiseCipher.CCMP)
                status = WifiConfiguration.Status.ENABLED
            }

            val netId = wifiManager?.addNetwork(wifiConfig)
            if (netId != null && netId != -1) {
                wifiManager?.disconnect()
                wifiManager?.enableNetwork(netId, true)
                wifiManager?.reconnect()
                
                result.success(mapOf(
                    "success" to true,
                    "message" to "Connected to $ssid (legacy method)"
                ))
            } else {
                result.error("NETWORK_ADD_FAILED", "Failed to add network configuration", null)
            }
        } catch (e: Exception) {
            result.error("LEGACY_CONNECT_ERROR", "Legacy connection failed: ${e.message}", null)
        }
    }

    private fun scanWiFi(result: Result) {
        try {
            if (ActivityCompat.checkSelfPermission(
                    context,
                    Manifest.permission.ACCESS_FINE_LOCATION
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                result.error("PERMISSION_DENIED", "Location permission required for WiFi scan", null)
                return
            }

            val scanResults = wifiManager?.scanResults ?: emptyList()
            val networks = scanResults.map { scanResult ->
                mapOf(
                    "ssid" to scanResult.SSID,
                    "bssid" to scanResult.BSSID,
                    "level" to scanResult.level,
                    "frequency" to scanResult.frequency,
                    "capabilities" to scanResult.capabilities
                )
            }

            result.success(mapOf(
                "success" to true,
                "networks" to networks
            ))
        } catch (e: Exception) {
            result.error("SCAN_ERROR", "WiFi scan failed: ${e.message}", null)
        }
    }

    private fun getCurrentWiFi(result: Result) {
        try {
            val wifiInfo = wifiManager?.connectionInfo
            if (wifiInfo != null && wifiInfo.ssid != null) {
                result.success(mapOf(
                    "ssid" to wifiInfo.ssid.replace("\"", ""),
                    "bssid" to wifiInfo.bssid,
                    "rssi" to wifiInfo.rssi,
                    "linkSpeed" to wifiInfo.linkSpeed,
                    "networkId" to wifiInfo.networkId
                ))
            } else {
                result.success(mapOf("ssid" to null))
            }
        } catch (e: Exception) {
            result.error("WIFI_INFO_ERROR", "Failed to get WiFi info: ${e.message}", null)
        }
    }

    private fun getHotspotInfo(result: Result) {
        try {
            // Try to get hotspot state using reflection
            val method = wifiManager?.javaClass?.getMethod("getWifiApState")
            val state = method?.invoke(wifiManager) as? Int

            val isEnabled = when (state) {
                12, 13 -> true // WIFI_AP_STATE_ENABLED or WIFI_AP_STATE_ENABLING
                else -> false
            }

            result.success(mapOf(
                "isEnabled" to isEnabled,
                "state" to (state ?: -1)
            ))
        } catch (e: Exception) {
            result.success(mapOf(
                "isEnabled" to false,
                "error" to e.message
            ))
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}