package com.example.resqlink

import android.content.Context
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.net.ConnectivityManager
import android.net.NetworkRequest
import android.net.Network
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class WiFiManagerPlugin: FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var wifiManager: WifiManager
    private lateinit var connectivityManager: ConnectivityManager

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "resqlink/wifi")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
        wifiManager = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
        connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "connectToWiFi" -> {
                val ssid = call.argument<String>("ssid")
                val password = call.argument<String>("password")
                val timeout = call.argument<Int>("timeout") ?: 30000
                
                if (ssid != null && password != null) {
                    connectToWiFi(ssid, password, timeout, result)
                } else {
                    result.error("INVALID_ARGUMENTS", "SSID and password are required", null)
                }
            }
            "getCurrentWiFi" -> {
                getCurrentWiFiInfo(result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun connectToWiFi(ssid: String, password: String, timeout: Int, result: Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                connectToWiFiAndroid10Plus(ssid, password, timeout, result)
            } else {
                connectToWiFiLegacy(ssid, password, result)
            }
        } catch (e: Exception) {
            result.error("CONNECTION_ERROR", "Failed to connect to WiFi: ${e.message}", null)
        }
    }

    private fun connectToWiFiAndroid10Plus(ssid: String, password: String, timeout: Int, result: Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val wifiNetworkSpecifier = WifiNetworkSpecifier.Builder()
                .setSsid(ssid)
                .setWpa2Passphrase(password)
                .build()

            val networkRequest = NetworkRequest.Builder()
                .addTransportType(android.net.NetworkCapabilities.TRANSPORT_WIFI)
                .setNetworkSpecifier(wifiNetworkSpecifier)
                .build()

            val networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    super.onAvailable(network)
                    result.success(mapOf("success" to true, "message" to "Connected successfully"))
                }

                override fun onUnavailable() {
                    super.onUnavailable()
                    result.success(mapOf("success" to false, "message" to "Connection failed"))
                }
            }

            connectivityManager.requestNetwork(networkRequest, networkCallback, timeout)
        }
    }

    private fun connectToWiFiLegacy(ssid: String, password: String, result: Result) {
        val wifiConfig = WifiConfiguration().apply {
            SSID = "\"$ssid\""
            preSharedKey = "\"$password\""
            allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
        }

        val networkId = wifiManager.addNetwork(wifiConfig)
        if (networkId != -1) {
            wifiManager.disconnect()
            wifiManager.enableNetwork(networkId, true)
            wifiManager.reconnect()
            result.success(mapOf("success" to true, "message" to "Connection initiated"))
        } else {
            result.success(mapOf("success" to false, "message" to "Failed to add network"))
        }
    }

    private fun getCurrentWiFiInfo(result: Result) {
        try {
            val wifiInfo = wifiManager.connectionInfo
            val ssid = wifiInfo.ssid?.replace("\"", "")
            
            result.success(mapOf(
                "ssid" to ssid,
                "bssid" to wifiInfo.bssid,
                "rssi" to wifiInfo.rssi,
                "linkSpeed" to wifiInfo.linkSpeed,
                "isConnected" to (ssid != null && ssid != "<unknown ssid>")
            ))
        } catch (e: Exception) {
            result.error("WIFI_INFO_ERROR", "Failed to get WiFi info: ${e.message}", null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}