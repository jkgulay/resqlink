package com.example.resqlink

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pDeviceList
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pGroup
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import kotlin.collections.HashMap

class MainActivity: FlutterActivity() {
    companion object {
        const val WIFI_CHANNEL = "resqlink/wifi"
        const val HOTSPOT_CHANNEL = "resqlink/hotspot"
        const val PERMISSION_CHANNEL = "resqlink/permissions"
        const val LOCATION_CHANNEL = "resqlink/location"
        const val VIBRATION_CHANNEL = "resqlink/vibration"
        
        const val REQUEST_CODE_LOCATION = 1001
        const val REQUEST_CODE_WIFI = 1002
        const val REQUEST_CODE_NEARBY_DEVICES = 1003
    }

    private lateinit var wifiMethodChannel: MethodChannel
    private lateinit var hotspotMethodChannel: MethodChannel
    private lateinit var permissionMethodChannel: MethodChannel
    private lateinit var locationMethodChannel: MethodChannel
    private lateinit var vibrationMethodChannel: MethodChannel

    private lateinit var wifiManager: WifiManager
    private lateinit var wifiP2pManager: WifiP2pManager
    private lateinit var hotspotManager: HotspotManager
    private lateinit var locationHelper: LocationHelper
    private lateinit var permissionHelper: PermissionHelper

    private var channel: WifiP2pManager.Channel? = null
    private var wifiDirectReceiver: WifiDirectBroadcastReceiver? = null

override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)

    // Register the existing WiFi plugin - THIS IS REDUNDANT
    // flutterEngine.plugins.add(WiFiManagerPlugin()) // Remove this line
    
    // The WiFiManagerPlugin uses its own channel "resqlink/wifi" 
    // which conflicts with your wifiMethodChannel
    
    // Initialize managers
    wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    wifiP2pManager = getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager
    channel = wifiP2pManager.initialize(this, mainLooper, null)

    hotspotManager = HotspotManager(this)
    locationHelper = LocationHelper(this)
    permissionHelper = PermissionHelper(this)

    // Setup method channels
    setupMethodChannels(flutterEngine)
}

    private fun setupMethodChannels(flutterEngine: FlutterEngine) {
        // Vibration channel (existing)
        vibrationMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VIBRATION_CHANNEL)
        vibrationMethodChannel.setMethodCallHandler { call, result ->
            if (call.method == "vibrate") {
                val vibrator = getSystemService(VIBRATOR_SERVICE) as Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(VibrationEffect.createOneShot(1200, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(1200)
                }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        // WiFi Direct channel
        wifiMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_CHANNEL)
        wifiMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkWifiDirectSupport" -> {
                    result.success(checkWifiDirectSupport())
                }
                "enableWifi" -> {
                    enableWifi()
                    result.success(true)
                }
                "startDiscovery" -> {
                    startWifiDirectDiscovery(result)
                }
                "stopDiscovery" -> {
                    stopWifiDirectDiscovery(result)
                }
                "connectToPeer" -> {
                    val deviceAddress = call.argument<String>("deviceAddress")
                    connectToWifiDirectPeer(deviceAddress, result)
                }
                "createGroup" -> {
                    createWifiDirectGroup(result)
                }
                "removeGroup" -> {
                    removeWifiDirectGroup(result)
                }
                "getGroupInfo" -> {
                    getWifiDirectGroupInfo(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Hotspot channel
        hotspotMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HOTSPOT_CHANNEL)
        hotspotMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkHotspotCapabilities" -> {
                    result.success(hotspotManager.checkHotspotCapabilities())
                }
                "createLocalOnlyHotspot" -> {
                    val ssid = call.argument<String>("ssid") ?: "ResQLink_${System.currentTimeMillis()}"
                    val password = call.argument<String>("password") ?: "RESQLINK911"
                    hotspotManager.createLocalOnlyHotspot(ssid, password, result)
                }
                "createLegacyHotspot" -> {
                    val ssid = call.argument<String>("ssid") ?: "ResQLink_${System.currentTimeMillis()}"
                    val password = call.argument<String>("password") ?: "RESQLINK911"
                    hotspotManager.createLegacyHotspot(ssid, password, result)
                }
                "stopHotspot" -> {
                    hotspotManager.stopHotspot(result)
                }
                "getConnectedClients" -> {
                    hotspotManager.getConnectedClients(result)
                }
                "getHotspotInfo" -> {
                    hotspotManager.getHotspotInfo(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Permission channel
        permissionMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSION_CHANNEL)
        permissionMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkWifiDirectSupport" -> {
                    result.success(permissionHelper.checkWifiDirectSupport())
                }
                "requestLocationPermission" -> {
                    permissionHelper.requestLocationPermission()
                    result.success(true)
                }
                "requestNearbyDevicesPermission" -> {
                    permissionHelper.requestNearbyDevicesPermission()
                    result.success(true)
                }
                "checkAllPermissions" -> {
                    result.success(permissionHelper.checkAllPermissions())
                }
                "openSettings" -> {
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = android.net.Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Location channel
        locationMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_CHANNEL)
        locationMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startLocationTracking" -> {
                    val isEmergency = call.argument<Boolean>("emergency") ?: false
                    locationHelper.startLocationTracking(isEmergency, result)
                }
                "stopLocationTracking" -> {
                    locationHelper.stopLocationTracking(result)
                }
                "getCurrentLocation" -> {
                    locationHelper.getCurrentLocation(result)
                }
                "isLocationEnabled" -> {
                    result.success(locationHelper.isLocationEnabled())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    // WiFi Direct Support Check
    private fun checkWifiDirectSupport(): Boolean {
        return packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT)
    }

    private fun enableWifi() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+ requires user to enable WiFi manually
            val intent = Intent(Settings.ACTION_WIFI_SETTINGS)
            startActivity(intent)
        } else {
            // Legacy method for older versions
            @Suppress("DEPRECATION")
            wifiManager.isWifiEnabled = true
        }
    }

    // WiFi Direct Methods
    private fun startWifiDirectDiscovery(result: MethodChannel.Result) {
        if (!checkWifiDirectSupport()) {
            result.error("UNSUPPORTED", "WiFi Direct not supported", null)
            return
        }

        if (!permissionHelper.hasLocationPermission()) {
            result.error("PERMISSION_DENIED", "Location permission required", null)
            return
        }

        channel?.let { channel ->
            wifiP2pManager.discoverPeers(channel, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    result.success(true)
                }

                override fun onFailure(reason: Int) {
                    val errorMessage = when (reason) {
                        WifiP2pManager.ERROR -> "Internal error"
                        WifiP2pManager.P2P_UNSUPPORTED -> "P2P unsupported"
                        WifiP2pManager.BUSY -> "System busy"
                        else -> "Unknown error: $reason"
                    }
                    result.error("DISCOVERY_FAILED", errorMessage, null)
                }
            })
        } ?: result.error("NOT_INITIALIZED", "WiFi P2P not initialized", null)
    }

    private fun stopWifiDirectDiscovery(result: MethodChannel.Result) {
        channel?.let { channel ->
            wifiP2pManager.stopPeerDiscovery(channel, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    result.success(true)
                }

                override fun onFailure(reason: Int) {
                    result.error("STOP_DISCOVERY_FAILED", "Failed to stop discovery: $reason", null)
                }
            })
        } ?: result.error("NOT_INITIALIZED", "WiFi P2P not initialized", null)
    }

    private fun connectToWifiDirectPeer(deviceAddress: String?, result: MethodChannel.Result) {
        if (deviceAddress == null) {
            result.error("INVALID_ARGUMENT", "Device address is null", null)
            return
        }

        channel?.let { channel ->
            val config = android.net.wifi.p2p.WifiP2pConfig().apply {
                deviceAddress = deviceAddress
            }
            
            wifiP2pManager.connect(channel, config, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    result.success(true)
                }

                override fun onFailure(reason: Int) {
                    result.error("CONNECTION_FAILED", "Failed to connect: $reason", null)
                }
            })
        } ?: result.error("NOT_INITIALIZED", "WiFi P2P not initialized", null)
    }

    private fun createWifiDirectGroup(result: MethodChannel.Result) {
        channel?.let { channel ->
            wifiP2pManager.createGroup(channel, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    result.success(true)
                }

                override fun onFailure(reason: Int) {
                    result.error("GROUP_CREATION_FAILED", "Failed to create group: $reason", null)
                }
            })
        } ?: result.error("NOT_INITIALIZED", "WiFi P2P not initialized", null)
    }

    private fun removeWifiDirectGroup(result: MethodChannel.Result) {
        channel?.let { channel ->
            wifiP2pManager.removeGroup(channel, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    result.success(true)
                }

                override fun onFailure(reason: Int) {
                    result.error("GROUP_REMOVAL_FAILED", "Failed to remove group: $reason", null)
                }
            })
        } ?: result.error("NOT_INITIALIZED", "WiFi P2P not initialized", null)
    }

    private fun getWifiDirectGroupInfo(result: MethodChannel.Result) {
        channel?.let { channel ->
            wifiP2pManager.requestGroupInfo(channel) { group ->
                if (group != null) {
                    val clients = group.clientList.map { client ->
                        mapOf(
                            "deviceName" to client.deviceName,
                            "deviceAddress" to client.deviceAddress,
                            "status" to client.status
                        )
                    }
                    
                    val groupInfo = mapOf(
                        "networkName" to group.networkName,
                        "passphrase" to group.passphrase,
                        "owner" to mapOf(
                            "deviceName" to group.owner.deviceName,
                            "deviceAddress" to group.owner.deviceAddress
                        ),
                        "clients" to clients,
                        "isGroupOwner" to group.isGroupOwner
                    )
                    result.success(groupInfo)
                } else {
                    result.success(null)
                }
            }
        } ?: result.error("NOT_INITIALIZED", "WiFi P2P not initialized", null)
    }

    override fun onResume() {
        super.onResume()
        registerReceivers()
    }

    override fun onPause() {
        super.onPause()
        unregisterReceivers()
    }

    private fun registerReceivers() {
        val intentFilter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        
        wifiDirectReceiver = WifiDirectBroadcastReceiver(wifiP2pManager, channel, this)
        registerReceiver(wifiDirectReceiver, intentFilter)
    }

    private fun unregisterReceivers() {
        wifiDirectReceiver?.let {
            unregisterReceiver(it)
            wifiDirectReceiver = null
        }
    }

    // Method to send data back to Flutter
    fun sendToFlutter(channel: String, method: String, data: Map<String, Any>) {
        runOnUiThread {
            when (channel) {
                "wifi" -> wifiMethodChannel.invokeMethod(method, data)
                "hotspot" -> hotspotMethodChannel.invokeMethod(method, data)
                "permission" -> permissionMethodChannel.invokeMethod(method, data)
                "location" -> locationMethodChannel.invokeMethod(method, data)
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        permissionHelper.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}