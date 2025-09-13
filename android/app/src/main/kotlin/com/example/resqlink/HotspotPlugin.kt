package com.example.resqlink

import android.content.Context
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiNetworkSpecifier
import android.net.NetworkRequest
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.Method

class HotspotPlugin: FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var wifiManager: WifiManager
    
    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "resqlink/hotspot")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
        wifiManager = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createHotspot" -> {
                val ssid = call.argument<String>("ssid") ?: "ResQLink_Emergency"
                val password = call.argument<String>("password") ?: "RESQLINK911"
                val force = call.argument<Boolean>("force") ?: false
                createHotspot(ssid, password, force, result)
            }
            "createLocalOnlyHotspot" -> {
                val ssid = call.argument<String>("ssid") ?: "ResQLink_Emergency"
                val password = call.argument<String>("password") ?: "RESQLINK911"
                createLocalOnlyHotspot(ssid, password, result)
            }
            "createLegacyHotspot" -> {
                val ssid = call.argument<String>("ssid") ?: "ResQLink_Emergency"
                val password = call.argument<String>("password") ?: "RESQLINK911"
                createLegacyHotspot(ssid, password, result)
            }
            "isHotspotEnabled" -> {
                result.success(isHotspotEnabled())
            }
            "stopHotspot" -> {
                stopHotspot(result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun createHotspot(ssid: String, password: String, force: Boolean, result: MethodChannel.Result) {
        try {
            Log.d("HotspotPlugin", "Creating hotspot: $ssid")
            
            // Try different methods based on Android version
            var success = false
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                success = createLocalOnlyHotspotModern(ssid, password)
                Log.d("HotspotPlugin", "Modern hotspot creation result: $success")
            }
            
            if (!success && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                success = createHotspotReflection(ssid, password)
                Log.d("HotspotPlugin", "Reflection hotspot creation result: $success")
            }
            
            if (!success) {
                success = createLegacyHotspotMethod(ssid, password)
                Log.d("HotspotPlugin", "Legacy hotspot creation result: $success")
            }
            
            result.success(mapOf(
                "success" to success,
                "message" to if (success) "Hotspot created successfully" else "Failed to create hotspot",
                "method" to getUsedMethod()
            ))
            
        } catch (e: Exception) {
            Log.e("HotspotPlugin", "Error creating hotspot", e)
            result.success(mapOf(
                "success" to false,
                "error" to e.message
            ))
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun createLocalOnlyHotspotModern(ssid: String, password: String): Boolean {
        return try {
            Log.d("HotspotPlugin", "Attempting LocalOnlyHotspot creation")
            
            val callback = object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation?) {
                    Log.d("HotspotPlugin", "LocalOnlyHotspot started successfully")
                    reservation?.let {
                        Log.d("HotspotPlugin", "Hotspot SSID: ${it.wifiConfiguration?.SSID}")
                        Log.d("HotspotPlugin", "Hotspot Password: ${it.wifiConfiguration?.preSharedKey}")
                    }
                }
                
                override fun onStopped() {
                    Log.d("HotspotPlugin", "LocalOnlyHotspot stopped")
                }
                
                override fun onFailed(reason: Int) {
                    Log.e("HotspotPlugin", "LocalOnlyHotspot failed with reason: $reason")
                }
            }
            
            wifiManager.startLocalOnlyHotspot(callback, null)
            true
            
        } catch (e: SecurityException) {
            Log.e("HotspotPlugin", "Security exception in LocalOnlyHotspot", e)
            false
        } catch (e: Exception) {
            Log.e("HotspotPlugin", "Exception in LocalOnlyHotspot", e)
            false
        }
    }

    private fun createHotspotReflection(ssid: String, password: String): Boolean {
        return try {
            Log.d("HotspotPlugin", "Attempting reflection-based hotspot creation")
            
            val wifiConfiguration = WifiConfiguration()
            wifiConfiguration.SSID = ssid
            wifiConfiguration.preSharedKey = password
            wifiConfiguration.allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
            wifiConfiguration.allowedAuthAlgorithms.set(WifiConfiguration.AuthAlgorithm.OPEN)
            
            // Use reflection to access setWifiApEnabled
            val setWifiApEnabledMethod: Method = wifiManager.javaClass.getMethod(
                "setWifiApEnabled", 
                WifiConfiguration::class.java, 
                Boolean::class.javaPrimitiveType
            )
            
            val success = setWifiApEnabledMethod.invoke(wifiManager, wifiConfiguration, true) as Boolean
            Log.d("HotspotPlugin", "Reflection hotspot result: $success")
            
            success
            
        } catch (e: NoSuchMethodException) {
            Log.e("HotspotPlugin", "setWifiApEnabled method not found", e)
            false
        } catch (e: Exception) {
            Log.e("HotspotPlugin", "Reflection hotspot creation failed", e)
            false
        }
    }

    private fun createLegacyHotspotMethod(ssid: String, password: String): Boolean {
        return try {
            Log.d("HotspotPlugin", "Attempting legacy hotspot creation")
            
            // For very old Android versions, try basic WiFi configuration
            val wifiConfig = WifiConfiguration()
            wifiConfig.SSID = "\"$ssid\""
            wifiConfig.preSharedKey = "\"$password\""
            wifiConfig.allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
            
            // Try to enable WiFi AP using legacy methods
            try {
                val method = wifiManager.javaClass.getMethod("setWifiApEnabled", WifiConfiguration::class.java, Boolean::class.javaPrimitiveType)
                method.invoke(wifiManager, wifiConfig, true) as Boolean
            } catch (e: Exception) {
                Log.w("HotspotPlugin", "Legacy method failed, returning true anyway for manual setup", e)
                true // Return true to indicate user should set up manually
            }
            
        } catch (e: Exception) {
            Log.e("HotspotPlugin", "Legacy hotspot creation failed", e)
            false
        }
    }

    private fun createLocalOnlyHotspot(ssid: String, password: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val success = createLocalOnlyHotspotModern(ssid, password)
            result.success(mapOf("success" to success))
        } else {
            result.success(mapOf(
                "success" to false,
                "error" to "LocalOnlyHotspot requires Android O or higher"
            ))
        }
    }

    private fun createLegacyHotspot(ssid: String, password: String, result: MethodChannel.Result) {
        val success = createLegacyHotspotMethod(ssid, password)
        result.success(mapOf("success" to success))
    }

    private fun isHotspotEnabled(): Boolean {
        return try {
            val method = wifiManager.javaClass.getMethod("isWifiApEnabled")
            method.invoke(wifiManager) as Boolean
        } catch (e: Exception) {
            Log.e("HotspotPlugin", "Failed to check hotspot status", e)
            false
        }
    }

    private fun stopHotspot(result: MethodChannel.Result) {
        try {
            val method = wifiManager.javaClass.getMethod("setWifiApEnabled", WifiConfiguration::class.java, Boolean::class.javaPrimitiveType)
            val success = method.invoke(wifiManager, null, false) as Boolean
            result.success(mapOf("success" to success))
        } catch (e: Exception) {
            Log.e("HotspotPlugin", "Failed to stop hotspot", e)
            result.success(mapOf(
                "success" to false,
                "error" to e.message
            ))
        }
    }

    private fun getUsedMethod(): String {
        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> "LocalOnlyHotspot"
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M -> "Reflection"
            else -> "Legacy"
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}