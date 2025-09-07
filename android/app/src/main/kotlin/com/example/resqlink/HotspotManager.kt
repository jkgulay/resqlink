package com.example.resqlink

import android.content.Context
import android.net.ConnectivityManager
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.Method
import java.net.InetAddress
import java.net.NetworkInterface
import java.util.Collections

class HotspotManager(private val context: Context) {
    private val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private var localOnlyHotspotReservation: WifiManager.LocalOnlyHotspotReservation? = null

    fun checkHotspotCapabilities(): Boolean {
        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> {
                // Android 8.0+ - check if LocalOnlyHotspot is available
                try {
                    val method = wifiManager.javaClass.getMethod("startLocalOnlyHotspot", 
                        WifiManager.LocalOnlyHotspotCallback::class.java, android.os.Handler::class.java)
                    true
                } catch (e: Exception) {
                    Log.w("HotspotManager", "LocalOnlyHotspot not supported", e)
                    false
                }
            }
            else -> {
                // Older Android versions - check if reflection methods work
                checkLegacyHotspotSupport()
            }
        }
    }

    private fun checkLegacyHotspotSupport(): Boolean {
        return try {
            val method = wifiManager.javaClass.getMethod("setWifiApEnabled", WifiConfiguration::class.java, Boolean::class.java)
            true
        } catch (e: Exception) {
            Log.w("HotspotManager", "Legacy hotspot not supported", e)
            false
        }
    }

    @Suppress("DEPRECATION")
    fun createLocalOnlyHotspot(ssid: String, password: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                wifiManager.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                    override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation?) {
                        super.onStarted(reservation)
                        localOnlyHotspotReservation = reservation
                        val config = reservation?.wifiConfiguration
                        
                        val resultMap = hashMapOf<String, Any>(
                            "success" to true,
                            "ssid" to (config?.SSID ?: ssid),
                            "password" to (config?.preSharedKey ?: password),
                            "frequency" to 0,
                            "networkId" to (config?.networkId ?: -1)
                        )
                        
                        Log.d("HotspotManager", "LocalOnlyHotspot started: ${config?.SSID}")
                        result.success(resultMap)
                    }

                    override fun onStopped() {
                        super.onStopped()
                        Log.d("HotspotManager", "LocalOnlyHotspot stopped")
                        localOnlyHotspotReservation = null
                        val data = mapOf("event" to "hotspot_stopped")
                        (context as MainActivity).sendToFlutter("hotspot", "onHotspotStateChanged", data)
                    }

                    override fun onFailed(reason: Int) {
                        super.onFailed(reason)
                        val errorMessage = when (reason) {
                            ERROR_NO_CHANNEL -> "No available channel"
                            ERROR_GENERIC -> "Generic error"
                            ERROR_INCOMPATIBLE_MODE -> "Incompatible mode"
                            ERROR_TETHERING_DISALLOWED -> "Tethering not allowed"
                            else -> "Unknown error: $reason"
                        }
                        Log.e("HotspotManager", "LocalOnlyHotspot failed: $errorMessage")
                        result.error("HOTSPOT_FAILED", errorMessage, null)
                    }
                }, null)
            } catch (e: SecurityException) {
                Log.e("HotspotManager", "Security exception creating hotspot", e)
                result.error("PERMISSION_DENIED", "Location permission required for hotspot", null)
            } catch (e: Exception) {
                Log.e("HotspotManager", "Exception creating hotspot", e)
                result.error("HOTSPOT_EXCEPTION", e.message, null)
            }
        } else {
            createLegacyHotspot(ssid, password, result)
        }
    }

    @Suppress("DEPRECATION")
    fun createLegacyHotspot(ssid: String, password: String, result: MethodChannel.Result) {
        try {
            // Disable WiFi first
            if (wifiManager.isWifiEnabled) {
                wifiManager.isWifiEnabled = false
                Thread.sleep(1000) // Wait for WiFi to disable
            }

            val wifiConfig = WifiConfiguration().apply {
                SSID = ssid
                preSharedKey = password
                allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
                allowedAuthAlgorithms.set(WifiConfiguration.AuthAlgorithm.OPEN)
                allowedProtocols.set(WifiConfiguration.Protocol.RSN)
                allowedProtocols.set(WifiConfiguration.Protocol.WPA)
                allowedGroupCiphers.set(WifiConfiguration.GroupCipher.TKIP)
                allowedGroupCiphers.set(WifiConfiguration.GroupCipher.CCMP)
                allowedPairwiseCiphers.set(WifiConfiguration.PairwiseCipher.TKIP)
                allowedPairwiseCiphers.set(WifiConfiguration.PairwiseCipher.CCMP)
            }

            // Use reflection to enable hotspot on older Android versions
            val method = wifiManager.javaClass.getMethod("setWifiApEnabled", WifiConfiguration::class.java, Boolean::class.java)
            val success = method.invoke(wifiManager, wifiConfig, true) as Boolean

            if (success) {
                val resultMap = hashMapOf<String, Any>(
                    "success" to true,
                    "ssid" to ssid,
                    "password" to password,
                    "method" to "legacy"
                )
                Log.d("HotspotManager", "Legacy hotspot created: $ssid")
                result.success(resultMap)
            } else {
                result.error("LEGACY_HOTSPOT_FAILED", "Failed to enable legacy hotspot", null)
            }
        } catch (e: Exception) {
            Log.e("HotspotManager", "Legacy hotspot creation failed", e)
            result.error("LEGACY_HOTSPOT_EXCEPTION", e.message, null)
        }
    }

    fun stopHotspot(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && localOnlyHotspotReservation != null) {
                localOnlyHotspotReservation?.close()
                localOnlyHotspotReservation = null
                Log.d("HotspotManager", "LocalOnlyHotspot stopped")
                result.success(true)
            } else {
                // Legacy method
                val method = wifiManager.javaClass.getMethod("setWifiApEnabled", WifiConfiguration::class.java, Boolean::class.java)
                method.invoke(wifiManager, null, false)
                Log.d("HotspotManager", "Legacy hotspot stopped")
                result.success(true)
            }
        } catch (e: Exception) {
            Log.e("HotspotManager", "Failed to stop hotspot", e)
            result.error("STOP_HOTSPOT_FAILED", e.message, null)
        }
    }

    fun getConnectedClients(result: MethodChannel.Result) {
        try {
            val clients = mutableListOf<Map<String, Any>>()
            
            // Method 1: Try to get clients from ARP table
            val arpClients = getClientsFromArpTable()
            clients.addAll(arpClients)
            
            // Method 2: Try to get clients using reflection (for some devices)
            try {
                val reflectionClients = getClientsUsingReflection()
                clients.addAll(reflectionClients)
            } catch (e: Exception) {
                Log.w("HotspotManager", "Reflection method failed", e)
            }
            
            Log.d("HotspotManager", "Found ${clients.size} connected clients")
            result.success(clients)
        } catch (e: Exception) {
            Log.e("HotspotManager", "Failed to get connected clients", e)
            result.error("GET_CLIENTS_FAILED", e.message, null)
        }
    }

    private fun getClientsFromArpTable(): List<Map<String, Any>> {
        val clients = mutableListOf<Map<String, Any>>()
        
        try {
            val process = Runtime.getRuntime().exec("cat /proc/net/arp")
            val reader = process.inputStream.bufferedReader()
            
            reader.readLines().forEach { line ->
                if (line.contains("192.168") && !line.contains("00:00:00:00:00:00")) {
                    val tokens = line.split("\\s+".toRegex())
                    if (tokens.size >= 4) {
                        val ipAddress = tokens[0]
                        val macAddress = tokens[3]
                        
                        clients.add(mapOf(
                            "ipAddress" to ipAddress,
                            "macAddress" to macAddress,
                            "deviceName" to "Unknown Device",
                            "connectionTime" to System.currentTimeMillis()
                        ))
                    }
                }
            }
            reader.close()
        } catch (e: Exception) {
            Log.w("HotspotManager", "Failed to read ARP table", e)
        }
        
        return clients
    }

    private fun getClientsUsingReflection(): List<Map<String, Any>> {
        val clients = mutableListOf<Map<String, Any>>()
        
        try {
            val method = wifiManager.javaClass.getMethod("getWifiApConfiguration")
            val config = method.invoke(wifiManager) as? WifiConfiguration
            
            // This is a simplified approach - actual implementation varies by device
            // Some manufacturers provide additional methods to get connected clients
            
        } catch (e: Exception) {
            Log.w("HotspotManager", "Reflection client detection failed", e)
        }
        
        return clients
    }

    fun getHotspotInfo(result: MethodChannel.Result) {
        try {
            val hotspotInfo = mutableMapOf<String, Any>()
            
            // Check if hotspot is enabled
            val isEnabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                localOnlyHotspotReservation != null
            } else {
                getWifiApState() == 13 // WIFI_AP_STATE_ENABLED
            }
            
            hotspotInfo["isEnabled"] = isEnabled
            hotspotInfo["androidVersion"] = Build.VERSION.SDK_INT
            hotspotInfo["canCreateProgrammatically"] = checkHotspotCapabilities()
            
            if (isEnabled) {
                // Get hotspot configuration
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && localOnlyHotspotReservation != null) {
                    val config = localOnlyHotspotReservation?.wifiConfiguration
                    hotspotInfo["ssid"] = config?.SSID ?: "Unknown"
                    hotspotInfo["password"] = config?.preSharedKey ?: "Unknown"
                    hotspotInfo["frequency"] = 0
                } else {
                    // Legacy method to get configuration
                    try {
                        val method = wifiManager.javaClass.getMethod("getWifiApConfiguration")
                        val config = method.invoke(wifiManager) as? WifiConfiguration
                        hotspotInfo["ssid"] = config?.SSID ?: "Unknown"
                        hotspotInfo["password"] = config?.preSharedKey ?: "Unknown"
                    } catch (e: Exception) {
                        Log.w("HotspotManager", "Failed to get hotspot config", e)
                    }
                }
                
                // Get IP address
                hotspotInfo["ipAddress"] = getHotspotIpAddress()
            }
            
            result.success(hotspotInfo)
        } catch (e: Exception) {
            Log.e("HotspotManager", "Failed to get hotspot info", e)
            result.error("GET_HOTSPOT_INFO_FAILED", e.message, null)
        }
    }

    private fun getWifiApState(): Int {
        return try {
            val method = wifiManager.javaClass.getMethod("getWifiApState")
            method.invoke(wifiManager) as Int
        } catch (e: Exception) {
            -1
        }
    }

    private fun getHotspotIpAddress(): String {
        try {
            val interfaces = Collections.list(NetworkInterface.getNetworkInterfaces())
            for (networkInterface in interfaces) {
                if (networkInterface.name.contains("wlan") || networkInterface.name.contains("ap")) {
                    val addresses = Collections.list(networkInterface.inetAddresses)
                    for (address in addresses) {
                        if (!address.isLoopbackAddress && address is InetAddress) {
                            val hostAddress = address.hostAddress
                            if (hostAddress?.contains("192.168") == true) {
                                return hostAddress
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.w("HotspotManager", "Failed to get hotspot IP", e)
        }
        return "192.168.43.1" // Default hotspot IP
    }
}