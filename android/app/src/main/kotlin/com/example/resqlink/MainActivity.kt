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
import android.net.wifi.p2p.WifiP2pDevice 
import android.net.wifi.p2p.WifiP2pConfig  
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.net.ServerSocket
import java.net.Socket
import java.net.InetSocketAddress
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.PrintWriter
import org.json.JSONObject

import android.os.Handler
import android.os.Looper

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

    private var serverSocket: ServerSocket? = null
    private var clientSocket: Socket? = null
    private var isSocketEstablished = false

    private lateinit var wifiMethodChannel: MethodChannel
    private lateinit var hotspotMethodChannel: MethodChannel
    private lateinit var permissionMethodChannel: MethodChannel
    private lateinit var locationMethodChannel: MethodChannel
    private lateinit var vibrationMethodChannel: MethodChannel

    private lateinit var wifiManager: WifiManager
    private lateinit var wifiP2pManager: WifiP2pManager
    private lateinit var hotspotManager: HotspotManager
    private lateinit var permissionHelper: PermissionHelper
    private lateinit var wifiDirectDiagnostic: WiFiDirectDiagnostic

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
        wifiDirectDiagnostic = WiFiDirectDiagnostic(this)

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
                "getConnectionInfo" -> getWifiDirectConnectionInfo(result)
                "establishSocketConnection" -> establishSocketConnection(result)
                "sendMessage" -> {
                    val message = call.argument<String>("message") ?: ""
                    sendMessage(message, result)
                }
                "runDiagnostic" -> {
                    val diagnostic = wifiDirectDiagnostic.runFullDiagnostic()
                    wifiDirectDiagnostic.logDetailedStatus()
                    result.success(diagnostic)
                }
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
                "requestWifiDirectPermissions" -> {
                    val allGranted = permissionHelper.requestWifiDirectPermissions()
                    result.success(allGranted)
                }
                "hasAllWifiDirectPermissions" -> result.success(permissionHelper.hasAllWifiDirectPermissions())
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
            // Try to open WiFi Direct settings directly
            try {
                val intent = Intent("android.settings.WIFI_DIRECT_SETTINGS")
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                startActivity(intent)
                android.util.Log.d("WiFiDirect", "Opened WiFi Direct settings directly")
            } catch (e: Exception) {
                // Fallback to WiFi settings if Direct settings not available
                android.util.Log.d("WiFiDirect", "WiFi Direct settings not available, opening WiFi settings")
                startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
            }
        } else {
            @Suppress("DEPRECATION")
            wifiManager.isWifiEnabled = true
        }
    }

    private fun startWifiDirectDiscovery(result: MethodChannel.Result) {
        android.util.Log.d("WiFiDirect", "=== Starting WiFi Direct Discovery ===")
        android.util.Log.d("WiFiDirect", "WiFi enabled: ${wifiManager.isWifiEnabled}")
        android.util.Log.d("WiFiDirect", "WiFi Direct support: ${checkWifiDirectSupport()}")
        android.util.Log.d("WiFiDirect", "All permissions: ${permissionHelper.hasAllWifiDirectPermissions()}")

        // Check WiFi is enabled
        if (!wifiManager.isWifiEnabled) {
            android.util.Log.e("WiFiDirect", "WiFi is disabled")
            result.error("WIFI_DISABLED", "WiFi must be enabled for device discovery", null)
            return
        }

        // Check hardware support
        if (!checkWifiDirectSupport()) {
            android.util.Log.e("WiFiDirect", "WiFi Direct not supported on this device")
            result.error("UNSUPPORTED", "WiFi Direct not supported on this device", null)
            return
        }

        // Check all required permissions
        if (!permissionHelper.hasAllWifiDirectPermissions()) {
            android.util.Log.e("WiFiDirect", "WiFi Direct permissions not granted")
            result.error("PERMISSION_DENIED", "All WiFi Direct permissions required", null)
            return
        }

        channel?.let { ch ->
            android.util.Log.d("WiFiDirect", "Initiating peer discovery with retry logic...")
            startDiscoveryWithRetry(ch, result, 0)
        } ?: run {
            android.util.Log.e("WiFiDirect", "WiFi P2P channel not initialized")
            result.error("NOT_INITIALIZED", "WiFi P2P channel not initialized", null)
        }
    }

    private fun establishSocketConnection(result: MethodChannel.Result?) {
        channel?.let { ch ->
            wifiP2pManager.requestConnectionInfo(ch) { info ->
                if (info?.groupFormed == true) {
                    Thread {
                        try {
                            if (info.isGroupOwner) {
                                // Start server socket
                                startServerSocket()
                            } else {
                                // Connect to group owner
                                connectToGroupOwner(info.groupOwnerAddress?.hostAddress ?: "")
                            }
                            
                            isSocketEstablished = true
                            
                            runOnUiThread {
                                val socketData = mapOf(
                                    "success" to true,
                                    "isGroupOwner" to info.isGroupOwner,
                                    "groupOwnerAddress" to (info.groupOwnerAddress?.hostAddress ?: ""),
                                    "socketPort" to 8888
                                )
                                wifiMethodChannel.invokeMethod("onSocketEstablished", socketData)
                                result?.success(socketData)
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result?.error("SOCKET_ERROR", "Failed to establish socket: ${e.message}", null)
                            }
                        }
                    }.start()
                } else {
                    result?.error("NO_GROUP", "No WiFi Direct group formed", null)
                }
            }
        } ?: result?.error("NOT_INITIALIZED", "WiFi P2P not initialized", null)
    }

    private fun startServerSocket() {
        try {
            serverSocket = ServerSocket(8888)
            android.util.Log.d("WiFiDirect", "Server socket started on port 8888")
            
            // Accept client connections
            Thread {
                while (true) {
                    try {
                        val client = serverSocket?.accept()
                        client?.let {
                            handleClientConnection(it)
                        }
                    } catch (e: Exception) {
                        android.util.Log.e("WiFiDirect", "Error accepting client", e)
                        break
                    }
                }
            }.start()
        } catch (e: Exception) {
            android.util.Log.e("WiFiDirect", "Failed to start server socket", e)
        }
    }

    private fun connectToGroupOwner(address: String) {
        try {
            clientSocket = Socket()
            clientSocket?.connect(InetSocketAddress(address, 8888), 5000)
            android.util.Log.d("WiFiDirect", "Connected to group owner at $address")
            
            // Start message handling
            handleClientConnection(clientSocket!!)
        } catch (e: Exception) {
            android.util.Log.e("WiFiDirect", "Failed to connect to group owner", e)
        }
    }

   private fun handleClientConnection(socket: Socket) {
    Thread {
        try {
            val input = BufferedReader(InputStreamReader(socket.getInputStream()))
            val output = PrintWriter(socket.getOutputStream(), true)
            
            // Send handshake
            val handshake = JSONObject().apply {
                put("type", "handshake")
                put("deviceId", android.provider.Settings.Secure.getString(
                    contentResolver, 
                    android.provider.Settings.Secure.ANDROID_ID
                ))
                put("timestamp", System.currentTimeMillis())
            }
            output.println(handshake.toString())
            
            // Listen for messages
            var line: String?
            while (input.readLine().also { line = it } != null) {
                runOnUiThread {
                    wifiMethodChannel.invokeMethod("onMessageReceived", mapOf(
                        "message" to line,
                        "from" to socket.remoteSocketAddress.toString()
                    ))
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("WiFiDirect", "Error handling client connection", e)
        }
    }.start()
}

  private fun sendMessage(message: String, result: MethodChannel.Result) {
    Thread {
        try {
            val output = when {
                clientSocket?.isConnected == true -> 
                    PrintWriter(clientSocket!!.getOutputStream(), true)
                serverSocket != null -> {
                    // Send to all connected clients
                    // You'd need to maintain a list of connected client sockets
                    null
                }
                else -> null
            }
            
            output?.println(message)
            runOnUiThread {
                result.success(true)
            }
        } catch (e: Exception) {
            runOnUiThread {
                result.error("SEND_ERROR", "Failed to send message: ${e.message}", null)
            }
        }
    }.start()
}

    private fun startDiscoveryWithRetry(
        channel: WifiP2pManager.Channel,
        result: MethodChannel.Result,
        retryCount: Int
    ) {
        val maxRetries = 3

        wifiP2pManager.discoverPeers(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                android.util.Log.d("WiFiDirect", "Peer discovery started successfully (attempt ${retryCount + 1})")
                result.success(true)
            }
            override fun onFailure(reason: Int) {
                val errorMsg = when (reason) {
                    WifiP2pManager.P2P_UNSUPPORTED -> "P2P unsupported on device"
                    WifiP2pManager.ERROR -> "Internal WiFi Direct error"
                    WifiP2pManager.BUSY -> "WiFi Direct system busy"
                    else -> "Unknown error code $reason"
                }

                android.util.Log.w("WiFiDirect", "Discovery attempt ${retryCount + 1} failed: $errorMsg")

                if (retryCount < maxRetries) {
                    // Simple exponential backoff: 1s, 2s, 4s
                    val delayMs = 1000L * (1 shl retryCount) // Bit shift for 2^retryCount
                    android.util.Log.d("WiFiDirect", "Retrying discovery in ${delayMs}ms...")

                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                        startDiscoveryWithRetry(channel, result, retryCount + 1)
                    }, delayMs)
                } else {
                    android.util.Log.e("WiFiDirect", "All discovery attempts failed: $errorMsg")
                    result.error("DISCOVERY_FAILED", "Discovery failed after $maxRetries attempts: $errorMsg", null)
                }
            }
        })
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

    private fun getWifiDirectConnectionInfo(result: MethodChannel.Result) {
        channel?.let { ch ->
            wifiP2pManager.requestConnectionInfo(ch) { info ->
                if (info != null) {
                    val connectionInfo = mapOf(
                        "isConnected" to true,
                        "isGroupOwner" to info.isGroupOwner,
                        "groupOwnerAddress" to (info.groupOwnerAddress?.hostAddress ?: ""),
                        "groupFormed" to info.groupFormed
                    )
                    result.success(connectionInfo)
                } else {
                    result.success(mapOf(
                        "isConnected" to false,
                        "isGroupOwner" to false,
                        "groupOwnerAddress" to "",
                        "groupFormed" to false
                    ))
                }
            }
        } ?: result.error("NOT_INITIALIZED", "WiFi P2P not initialized", null)
    }

    override fun onResume() {
        super.onResume()
        
        // Register receiver
        val intentFilter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        wifiDirectReceiver = WifiDirectBroadcastReceiver(wifiP2pManager, channel, this)
        registerReceiver(wifiDirectReceiver, intentFilter)
        
        // CRITICAL: Check for existing connections
        checkExistingWiFiDirectConnection()
    }

    private fun checkExistingWiFiDirectConnection() {
    channel?.let { ch ->
        // Check connection info
        wifiP2pManager.requestConnectionInfo(ch) { info ->
            if (info?.groupFormed == true) {
                android.util.Log.d("WiFiDirect", "Existing connection detected!")
                
                // Notify Flutter about existing connection
                val connectionData = mapOf(
                    "isConnected" to true,
                    "isGroupOwner" to info.isGroupOwner,
                    "groupOwnerAddress" to (info.groupOwnerAddress?.hostAddress ?: ""),
                    "groupFormed" to true
                )
                wifiMethodChannel.invokeMethod("onExistingConnectionFound", connectionData)
                
                // Request peer list
                requestPeerList()
                
                // Establish socket if not already done
                if (!isSocketEstablished) {
                    // Create a dummy MethodChannel.Result for internal calls
                    val dummyResult = object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            android.util.Log.d("WiFiDirect", "Socket established on app resume")
                        }
                        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                            android.util.Log.e("WiFiDirect", "Socket establishment failed: $errorMessage")
                        }
                        override fun notImplemented() {}
                    }
                    establishSocketConnection(dummyResult)
                }
            }
        }
        
        // Also request group info
        wifiP2pManager.requestGroupInfo(ch) { group ->
            if (group != null) {
                val groupData = mapOf(
                    "networkName" to group.networkName,
                    "passphrase" to group.passphrase,
                    "isGroupOwner" to group.isGroupOwner,
                    "clients" to group.clientList.map { client ->
                        mapOf(
                            "deviceName" to client.deviceName,
                            "deviceAddress" to client.deviceAddress
                        )
                    }
                )
                wifiMethodChannel.invokeMethod("onGroupInfoAvailable", groupData)
            }
        }
    }
}

  private fun requestPeerList() {
    channel?.let { ch ->
        wifiP2pManager.requestPeers(ch) { peers ->
            val peersList = peers.deviceList.map { device ->
                mapOf(
                    "deviceName" to device.deviceName,
                    "deviceAddress" to device.deviceAddress,
                    "status" to when(device.status) {
                        WifiP2pDevice.AVAILABLE -> "available"
                        WifiP2pDevice.INVITED -> "invited"
                        WifiP2pDevice.CONNECTED -> "connected"
                        WifiP2pDevice.FAILED -> "failed"
                        WifiP2pDevice.UNAVAILABLE -> "unavailable"
                        else -> "unknown"
                    }
                )
            }
            wifiMethodChannel.invokeMethod("onPeersUpdated", mapOf("peers" to peersList))
        }
    }
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
