package com.example.resqlink

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import android.net.wifi.WifiManager
import android.net.wifi.p2p.WifiP2pManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity : FlutterActivity() {
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
    private lateinit var permissionHelper: PermissionHelper

    private var channel: WifiP2pManager.Channel? = null
    private var wifiDirectReceiver: WifiDirectBroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        // Managers
        wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        wifiP2pManager = getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager
        channel = wifiP2pManager.initialize(this, mainLooper, null)

        hotspotManager = HotspotManager(this)
        permissionHelper = PermissionHelper(this)

        // Channels
        setupMethodChannels(flutterEngine)
    }

    private fun setupMethodChannels(flutterEngine: FlutterEngine) {
        // Vibrate
        vibrationMethodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VIBRATION_CHANNEL)
        vibrationMethodChannel.setMethodCallHandler { call, result ->
            if (call.method == "vibrate") {
                val vibrator = getSystemService(VIBRATOR_SERVICE) as Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(
                        VibrationEffect.createOneShot(
                            1200,
                            VibrationEffect.DEFAULT_AMPLITUDE
                        )
                    )
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(1200)
                }
                result.success(null)
            } else result.notImplemented()
        }

        // Wi-Fi Direct
        wifiMethodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_CHANNEL)
        wifiMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkWifiDirectSupport" -> result.success(checkWifiDirectSupport())
                "enableWifi" -> {
                    enableWifi()
                    result.success(true)
                }

                "startDiscovery" -> startWifiDirectDiscovery(result)
                "stopDiscovery" -> stopWifiDirectDiscovery(result)
                "getPeerList" -> getWifiDirectPeerList(result)
                "connectToPeer" -> connectToWifiDirectPeer(
                    call.argument("deviceAddress"),
                    result
                )

                "createGroup" -> createWifiDirectGroup(result)
                "removeGroup" -> removeWifiDirectGroup(result)
                "getGroupInfo" -> getWifiDirectGroupInfo(result)
                else -> result.notImplemented()
            }
        }

        // Hotspot
        hotspotMethodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HOTSPOT_CHANNEL)
        hotspotMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkHotspotCapabilities" -> result.success(hotspotManager.checkHotspotCapabilities())
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

                "stopHotspot" -> hotspotManager.stopHotspot(result)
                "getConnectedClients" -> hotspotManager.getConnectedClients(result)
                "getHotspotInfo" -> hotspotManager.getHotspotInfo(result)
                else -> result.notImplemented()
            }
        }

        // Permissions
        permissionMethodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSION_CHANNEL)
        permissionMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkWifiDirectSupport" -> result.success(permissionHelper.checkWifiDirectSupport())
                "requestLocationPermission" -> {
                    permissionHelper.requestLocationPermission()
                    result.success(true)
                }

                "requestNearbyDevicesPermission" -> {
                    permissionHelper.requestNearbyDevicesPermission()
                    result.success(true)
                }

                "checkAllPermissions" -> result.success(permissionHelper.checkAllPermissions())
                "openSettings" -> {
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = android.net.Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        // Location (Placeholder - implement LocationHelper if needed)
        locationMethodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_CHANNEL)
        locationMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startLocationTracking" -> result.success(true)
                "stopLocationTracking" -> result.success(true)
                "getCurrentLocation" -> result.success(mapOf("latitude" to 0.0, "longitude" to 0.0))
                "isLocationEnabled" -> result.success(true)
                else -> result.notImplemented()
            }
        }
    }

    // Wi-Fi Direct
    private fun checkWifiDirectSupport(): Boolean {
        return packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT)
    }

    private fun enableWifi() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
        } else {
            @Suppress("DEPRECATION")
            wifiManager.isWifiEnabled = true
        }
    }

    private fun startWifiDirectDiscovery(result: MethodChannel.Result) {
        android.util.Log.d("WiFiDirect", "Starting WiFi Direct discovery...")

        if (!checkWifiDirectSupport()) {
            android.util.Log.e("WiFiDirect", "WiFi Direct not supported")
            result.error("UNSUPPORTED", "WiFi Direct not supported", null)
            return
        }

        if (!permissionHelper.hasLocationPermission()) {
            android.util.Log.e("WiFiDirect", "Location permission not granted")
            result.error("PERMISSION_DENIED", "Location permission required", null)
            return
        }

        channel?.let { ch ->
            android.util.Log.d("WiFiDirect", "Initiating peer discovery...")
            wifiP2pManager.discoverPeers(ch, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    android.util.Log.d("WiFiDirect", "Peer discovery started successfully")
                    result.success(true)
                }
                override fun onFailure(reason: Int) {
                    val errorMsg = when (reason) {
                        WifiP2pManager.P2P_UNSUPPORTED -> "P2P unsupported"
                        WifiP2pManager.ERROR -> "Internal error"
                        WifiP2pManager.BUSY -> "System busy"
                        else -> "Unknown error code $reason"
                    }
                    android.util.Log.e("WiFiDirect", "Discovery failed: $errorMsg")
                    result.error("DISCOVERY_FAILED", errorMsg, null)
                }
            })
        } ?: run {
            android.util.Log.e("WiFiDirect", "WiFi P2P channel not initialized")
            result.error("NOT_INITIALIZED", "WiFi P2P not initialized", null)
        }
    }

    private fun stopWifiDirectDiscovery(result: MethodChannel.Result) {
        channel?.let { ch ->
            wifiP2pManager.stopPeerDiscovery(ch, object : WifiP2pManager.ActionListener {
                override fun onSuccess() = result.success(true)
                override fun onFailure(reason: Int) =
                    result.error("STOP_FAILED", "Error code $reason", null)
            })
        } ?: result.error("NOT_INITIALIZED", "WiFi P2P not initialized", null)
    }

    private fun getWifiDirectPeerList(result: MethodChannel.Result) {
        android.util.Log.d("WiFiDirect", "Requesting peer list...")

        channel?.let { ch ->
            wifiP2pManager.requestPeers(ch) { peers ->
                android.util.Log.d("WiFiDirect", "Found ${peers.deviceList.size} peers")

                val peersList = peers.deviceList.map { device ->
                    android.util.Log.d("WiFiDirect", "Peer: ${device.deviceName} (${device.deviceAddress})")
                    mapOf(
                        "deviceName" to (device.deviceName ?: "Unknown Device"),
                        "deviceAddress" to (device.deviceAddress ?: "Unknown Address"),
                        "primaryDeviceType" to (device.primaryDeviceType ?: "Unknown Type"),
                        "secondaryDeviceType" to (device.secondaryDeviceType ?: "Unknown Secondary Type"),
                        "status" to device.status,
                        "supportsWps" to true
                    )
                }
                result.success(mapOf("peers" to peersList))

                // Also notify via broadcast receiver
                wifiDirectReceiver?.onPeersAvailable(peers)
            }
        } ?: run {
            android.util.Log.e("WiFiDirect", "WiFi P2P channel not initialized")
            result.error("NOT_INITIALIZED", "WiFi P2P not initialized", null)
        }
    }

    private fun connectToWifiDirectPeer(deviceAddress: String?, result: MethodChannel.Result) {
        if (deviceAddress == null) {
            result.error("INVALID_ARGUMENT", "Device address is null", null); return
        }
        channel?.let { ch ->
            val config = android.net.wifi.p2p.WifiP2pConfig().apply {
                this.deviceAddress = deviceAddress
            }
            wifiP2pManager.connect(ch, config, object : WifiP2pManager.ActionListener {
                override fun onSuccess() = result.success(true)
                override fun onFailure(reason: Int) =
                    result.error("CONNECTION_FAILED", "Error code $reason", null)
            })
        } ?: result.error("NOT_INITIALIZED", "WiFi P2P not initialized", null)
    }

    private fun createWifiDirectGroup(result: MethodChannel.Result) {
        channel?.let { ch ->
            wifiP2pManager.createGroup(ch, object : WifiP2pManager.ActionListener {
                override fun onSuccess() = result.success(true)
                override fun onFailure(reason: Int) =
                    result.error("GROUP_FAILED", "Error code $reason", null)
            })
        } ?: result.error("NOT_INITIALIZED", "WiFi P2P not initialized", null)
    }

    private fun removeWifiDirectGroup(result: MethodChannel.Result) {
        channel?.let { ch ->
            wifiP2pManager.removeGroup(ch, object : WifiP2pManager.ActionListener {
                override fun onSuccess() = result.success(true)
                override fun onFailure(reason: Int) =
                    result.error("REMOVE_FAILED", "Error code $reason", null)
            })
        } ?: result.error("NOT_INITIALIZED", "WiFi P2P not initialized", null)
    }

    private fun getWifiDirectGroupInfo(result: MethodChannel.Result) {
        channel?.let { ch ->
            wifiP2pManager.requestGroupInfo(ch) { group ->
                if (group != null) {
                    val clients = group.clientList.map { client ->
                        mapOf(
                            "deviceName" to client.deviceName,
                            "deviceAddress" to client.deviceAddress,
                            "status" to client.status
                        )
                    }
                    val info = mapOf(
                        "networkName" to group.networkName,
                        "passphrase" to group.passphrase,
                        "owner" to mapOf(
                            "deviceName" to group.owner.deviceName,
                            "deviceAddress" to group.owner.deviceAddress
                        ),
                        "clients" to clients,
                        "isGroupOwner" to group.isGroupOwner
                    )
                    result.success(info)
                } else result.success(null)
            }
        } ?: result.error("NOT_INITIALIZED", "WiFi P2P not initialized", null)
    }

    // Receivers
    override fun onResume() {
        super.onResume()
        val intentFilter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        wifiDirectReceiver = WifiDirectBroadcastReceiver(wifiP2pManager, channel, this)
        registerReceiver(wifiDirectReceiver, intentFilter)
    }

    override fun onPause() {
        super.onPause()
        wifiDirectReceiver?.let { unregisterReceiver(it) }
    }

    // Permission handling
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        permissionHelper.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    // Flutter callback
    fun sendToFlutter(channel: String, method: String, data: Map<String, Any>) {
        runOnUiThread {
            when (channel) {
                "wifi" -> wifiMethodChannel.invokeMethod(method, data)
                "hotspot" -> hotspotMethodChannel.invokeMethod(method, data)
                "permission" -> permissionMethodChannel.invokeMethod(method, data)
                "location" -> locationMethodChannel.invokeMethod(method, data)
                "wifi_direct" -> wifiMethodChannel.invokeMethod(method, data)
            }
        }
    }
}
