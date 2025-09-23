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
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pGroup
import android.net.wifi.p2p.WifiP2pDeviceList
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
import java.util.Timer
import java.util.TimerTask
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
    private var connectedClients = mutableListOf<Socket>()
    private var isSocketEstablished = false
    private var isGroupOwner = false
    private lateinit var wifiMethodChannel: MethodChannel
    private lateinit var hotspotMethodChannel: MethodChannel
    private lateinit var permissionMethodChannel: MethodChannel
    private lateinit var locationMethodChannel: MethodChannel
    private lateinit var vibrationMethodChannel: MethodChannel
    private val messageQueue = mutableListOf<PendingMessage>()
    private var messageHandler: Handler? = null
    private lateinit var wifiManager: WifiManager
    private lateinit var wifiP2pManager: WifiP2pManager
    private lateinit var hotspotManager: HotspotManager
    private lateinit var permissionHelper: PermissionHelper
    private lateinit var wifiDirectDiagnostic: WiFiDirectDiagnostic

    private var channel: WifiP2pManager.Channel? = null
    private var wifiDirectReceiver: WifiDirectBroadcastReceiver? = null

    data class PendingMessage(
        val message: String,
        val timestamp: Long,
        val retryCount: Int = 0
    )
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
                "testOfflineConnection" -> testOfflineConnection(result)
                "detectSystemNetworks" -> detectSystemNetworks(result)
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
                    val password = call.argument<String>("password") ?: "resqlink911"
                    hotspotManager.createLocalOnlyHotspot(ssid, password, result)
                }

                "createLegacyHotspot" -> {
                    val ssid = call.argument<String>("ssid") ?: "ResQLink_${System.currentTimeMillis()}"
                    val password = call.argument<String>("password") ?: "resqlink911"
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
            android.util.Log.d("WiFiDirect", "Initiating peer discovery with automatic group creation...")
            startDiscoveryWithAutoGroupCreation(ch, result)
        } ?: run {
            android.util.Log.e("WiFiDirect", "WiFi P2P channel not initialized")
            result.error("NOT_INITIALIZED", "WiFi P2P channel not initialized", null)
        }
    }

    private fun startDiscoveryWithAutoGroupCreation(
        channel: WifiP2pManager.Channel,
        result: MethodChannel.Result
    ) {
        // First, try to discover existing groups
        wifiP2pManager.discoverPeers(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                android.util.Log.d("WiFiDirect", "Discovery started, checking for existing peers...")

                // Wait a moment for discovery, then check if we found any peers
                Handler(Looper.getMainLooper()).postDelayed({
                    wifiP2pManager.requestPeers(channel) { peers ->
                        if (peers.deviceList.isEmpty()) {
                            android.util.Log.d("WiFiDirect", "No peers found, creating our own group...")
                            createWifiDirectGroupForDiscovery(channel, result)
                        } else {
                            android.util.Log.d("WiFiDirect", "Found ${peers.deviceList.size} existing peers")
                            result.success(true)
                        }
                    }
                }, 3000) // Wait 3 seconds for discovery
            }

            override fun onFailure(reason: Int) {
                android.util.Log.w("WiFiDirect", "Discovery failed, creating group anyway...")
                createWifiDirectGroupForDiscovery(channel, result)
            }
        })
    }

    private fun createWifiDirectGroupForDiscovery(
        channel: WifiP2pManager.Channel,
        result: MethodChannel.Result
    ) {
        wifiP2pManager.createGroup(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                android.util.Log.d("WiFiDirect", "✅ WiFi Direct group created automatically")
                result.success(true)
            }

            override fun onFailure(reason: Int) {
                android.util.Log.e("WiFiDirect", "Failed to create group (reason: $reason), trying discovery only...")
                // Fallback to discovery only
                startDiscoveryWithRetry(channel, result, 0)
            }
        })
    }

private fun establishSocketConnection(result: MethodChannel.Result) {  // Remove the ? from Result
    channel?.let { ch ->
        wifiP2pManager.requestConnectionInfo(ch) { info ->
            if (info?.groupFormed == true) {
                Thread {
                    try {
                        if (info.isGroupOwner) {
                            startServerSocket()
                            isGroupOwner = true
                        } else {
                            // Add retry mechanism for client connection
                            var connected = false
                            var attempts = 0
                            while (!connected && attempts < 3) {
                                try {
                                    connectToGroupOwner(info.groupOwnerAddress?.hostAddress ?: "")
                                    connected = true
                                } catch (e: Exception) {
                                    attempts++
                                    Thread.sleep(1000)
                                }
                            }
                            isGroupOwner = false
                        }
                        
                        isSocketEstablished = true
                        
                        runOnUiThread {
                            val socketData = mapOf(
                                "success" to true,
                                "isGroupOwner" to info.isGroupOwner,
                                "groupOwnerAddress" to (info.groupOwnerAddress?.hostAddress ?: ""),
                                "socketPort" to 8888,
                                "socketEstablished" to true
                            )
                            wifiMethodChannel.invokeMethod("onSocketEstablished", socketData)
                            result.success(socketData)
                        }
                    } catch (e: Exception) {
                        isSocketEstablished = false
                        runOnUiThread {
                            result.error("SOCKET_ERROR", "Failed to establish socket: ${e.message}", null)
                        }
                    }
                }.start()
            } else {
                result.error("NO_GROUP", "No WiFi Direct group formed", null)
            }
        }
    } ?: result.error("NOT_INITIALIZED", "WiFi P2P not initialized", null)
}

    private fun startServerSocket() {
        try {
            // Close existing server socket if any
            serverSocket?.close()

            // Try to find an available port starting from 8888
            var port = 8888
            var socketCreated = false

            for (i in 0..10) { // Try 10 different ports
                try {
                    serverSocket = ServerSocket(port + i)
                    android.util.Log.d("WiFiDirect", "✅ Server socket started on port ${port + i}")

                    // Notify Flutter of the actual port used
                    runOnUiThread {
                        wifiMethodChannel.invokeMethod("onServerSocketReady", mapOf(
                            "port" to (port + i),
                            "address" to "0.0.0.0"
                        ))
                    }

                    socketCreated = true
                    break
                } catch (e: Exception) {
                    android.util.Log.w("WiFiDirect", "Port ${port + i} not available, trying next...")
                }
            }

            if (!socketCreated) {
                throw Exception("No available ports found")
            }

            // Accept client connections
            Thread {
                while (serverSocket?.isClosed == false) {
                    try {
                        val client = serverSocket?.accept()
                        client?.let {
                            synchronized(connectedClients) {
                                connectedClients.add(it)
                            }
                            android.util.Log.d("WiFiDirect", "Client connected: ${it.remoteSocketAddress}")
                            handleClientConnection(it)
                        }
                    } catch (e: Exception) {
                        if (serverSocket?.isClosed == false) {
                            android.util.Log.e("WiFiDirect", "Error accepting client", e)
                        }
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
            // Close any existing connection first
            clientSocket?.close()

            clientSocket = Socket()
            android.util.Log.d("WiFiDirect", "Attempting to connect to group owner at $address:8888")
            clientSocket?.connect(InetSocketAddress(address, 8888), 10000) // Increased timeout
            android.util.Log.d("WiFiDirect", "✅ Connected to group owner at $address")

            // Start message handling
            handleClientConnection(clientSocket!!)
        } catch (e: Exception) {
            android.util.Log.e("WiFiDirect", "❌ Failed to connect to group owner at $address", e)

            // Notify Flutter of connection failure
            runOnUiThread {
                wifiMethodChannel.invokeMethod("onConnectionError", mapOf(
                    "error" to "Failed to connect to group owner",
                    "details" to e.message
                ))
            }
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
            var line: String? = null
            while (socket.isConnected && !socket.isClosed && input.readLine().also { line = it } != null) {
                line?.let { message ->
                    android.util.Log.d("WiFiDirect", "Received message: $message from ${socket.remoteSocketAddress}")
                    runOnUiThread {
                        wifiMethodChannel.invokeMethod("onMessageReceived", mapOf(
                            "message" to message,
                            "from" to socket.remoteSocketAddress.toString()
                        ))
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("WiFiDirect", "Error handling client connection", e)
        } finally {
            // Clean up connection
            try {
                synchronized(connectedClients) {
                    connectedClients.remove(socket)
                }
                socket.close()
                android.util.Log.d("WiFiDirect", "Client connection closed: ${socket.remoteSocketAddress}")
            } catch (e: Exception) {
                android.util.Log.e("WiFiDirect", "Error closing socket", e)
            }
        }
    }.start()
}

    private fun sendMessage(message: String, result: MethodChannel.Result) {
        Thread {
            try {
                var messageSent = false
                
                // Check socket connectivity first
                if (!isSocketEstablished) {
                    // Queue message for retry
                    messageQueue.add(PendingMessage(message, System.currentTimeMillis()))
                    runOnUiThread {
                        result.error("NOT_CONNECTED", "Socket not established, message queued", null)
                    }
                    return@Thread
                }
                
                // Try sending with timeout
                val sendTimeout = 5000L // 5 seconds
                val startTime = System.currentTimeMillis()
                
                while (!messageSent && (System.currentTimeMillis() - startTime) < sendTimeout) {
                    messageSent = attemptSendMessage(message)
                    if (!messageSent) {
                        Thread.sleep(500) // Wait before retry
                    }
                }
                
                runOnUiThread {
                    if (messageSent) {
                        result.success(true)
                        processQueuedMessages() // Try to send queued messages
                    } else {
                        messageQueue.add(PendingMessage(message, System.currentTimeMillis()))
                        result.error("SEND_TIMEOUT", "Failed to send message within timeout", null)
                    }
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("SEND_ERROR", "Failed to send message: ${e.message}", null)
                }
            }
        }.start()
    }

    private fun attemptSendMessage(message: String): Boolean {
        var messageSent = false
        
        // If we're a client, send to server
        clientSocket?.let { socket ->
            if (socket.isConnected && !socket.isClosed) {
                try {
                    val output = PrintWriter(socket.getOutputStream(), true)
                    output.println(message)
                    output.flush() // Ensure message is sent
                    messageSent = true
                    android.util.Log.d("WiFiDirect", "Message sent to server: $message")
                } catch (e: Exception) {
                    android.util.Log.e("WiFiDirect", "Failed to send to server", e)
                }
            }
        }
        
        // If we're a server, send to all connected clients
        if (!messageSent && serverSocket != null && !serverSocket!!.isClosed) {
            synchronized(connectedClients) {
                val iterator = connectedClients.iterator()
                while (iterator.hasNext()) {
                    val client = iterator.next()
                    try {
                        if (client.isConnected && !client.isClosed) {
                            val output = PrintWriter(client.getOutputStream(), true)
                            output.println(message)
                            output.flush()
                            messageSent = true
                            android.util.Log.d("WiFiDirect", "Message sent to client ${client.remoteSocketAddress}")
                        } else {
                            iterator.remove()
                        }
                    } catch (e: Exception) {
                        android.util.Log.e("WiFiDirect", "Failed to send to client", e)
                        iterator.remove()
                    }
                }
            }
        }
        
        return messageSent
    }
    
    private fun processQueuedMessages() {
        if (messageQueue.isEmpty()) return
        
        Thread {
            val iterator = messageQueue.iterator()
            while (iterator.hasNext()) {
                val pendingMsg = iterator.next()
                if (attemptSendMessage(pendingMsg.message)) {
                    iterator.remove()
                    android.util.Log.d("WiFiDirect", "Queued message sent successfully")
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
    
    // CRITICAL FIX: Always request peer list on resume
    Timer().schedule(object : TimerTask() {
        override fun run() {
            requestPeerList()
        }
    }, 1000) 
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
                
                // Request peer list for existing connections
                requestPeerList()
                
                // Establish socket if not already done
                if (!isSocketEstablished) {
                    // Create a dummy result for internal call
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
                            "deviceAddress" to client.deviceAddress,
                            "status" to when(client.status) {
                                WifiP2pDevice.CONNECTED -> "connected"
                                WifiP2pDevice.AVAILABLE -> "available"
                                WifiP2pDevice.INVITED -> "invited"
                                WifiP2pDevice.FAILED -> "failed"
                                WifiP2pDevice.UNAVAILABLE -> "unavailable"
                                else -> "unknown"
                            }
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
                    "deviceName" to (device.deviceName ?: "Unknown Device"),
                    "deviceAddress" to (device.deviceAddress ?: "Unknown Address"),
                    "status" to when(device.status) {
                        WifiP2pDevice.AVAILABLE -> "available"
                        WifiP2pDevice.INVITED -> "invited"
                        WifiP2pDevice.CONNECTED -> "connected"
                        WifiP2pDevice.FAILED -> "failed"
                        WifiP2pDevice.UNAVAILABLE -> "unavailable"
                        else -> "unknown"
                    },
                    "primaryDeviceType" to (device.primaryDeviceType ?: "Unknown Type"),
                    "secondaryDeviceType" to (device.secondaryDeviceType ?: "Unknown Secondary Type"),
                    "supportsWps" to true // Simplified assumption
                )
            }
            
            android.util.Log.d("WiFiDirect", "Peer list updated: ${peersList.size} peers")
            peersList.forEach { peer ->
                android.util.Log.d("WiFiDirect", "  - ${peer["deviceName"]} (${peer["deviceAddress"]}) - ${peer["status"]}")
            }
            
            wifiMethodChannel.invokeMethod("onPeersUpdated", mapOf("peers" to peersList))
        }
    }
}


   override fun onPause() {
    super.onPause()

    wifiDirectReceiver?.let {
        try {
            unregisterReceiver(it)
        } catch (e: IllegalArgumentException) {
            // Receiver wasn't registered
        }
    }
}

override fun onDestroy() {
    super.onDestroy()
    // Clean up sockets
    serverSocket?.close()
    clientSocket?.close()
    connectedClients.forEach { it.close() }
    connectedClients.clear()
}

    private fun testOfflineConnection(result: MethodChannel.Result) {
        Thread {
            try {
                val testResults = mutableMapOf<String, Any>()

                // Test 1: Check WiFi Direct connection
                channel?.let { ch ->
                    wifiP2pManager.requestConnectionInfo(ch) { info ->
                        testResults["wifiDirectConnected"] = info?.groupFormed ?: false
                        testResults["isGroupOwner"] = info?.isGroupOwner ?: false

                        // Test 2: Check socket connection
                        val socketConnected = when {
                            clientSocket?.isConnected == true -> "client_connected"
                            serverSocket?.isClosed == false -> "server_ready"
                            else -> "no_connection"
                        }
                        testResults["socketStatus"] = socketConnected
                        testResults["connectedClients"] = connectedClients.size

                        // Test 3: Send test ping
                        if (isSocketEstablished) {
                            try {
                                val pingMessage = "PING_${System.currentTimeMillis()}"
                                var pingSent = false

                                if (clientSocket?.isConnected == true) {
                                    PrintWriter(clientSocket!!.getOutputStream(), true).println(pingMessage)
                                    pingSent = true
                                }

                                synchronized(connectedClients) {
                                    connectedClients.forEach { client ->
                                        if (client.isConnected) {
                                            PrintWriter(client.getOutputStream(), true).println(pingMessage)
                                            pingSent = true
                                        }
                                    }
                                }

                                testResults["pingTest"] = if (pingSent) "sent" else "failed"
                            } catch (e: Exception) {
                                testResults["pingTest"] = "error: ${e.message}"
                            }
                        } else {
                            testResults["pingTest"] = "no_socket"
                        }

                        runOnUiThread {
                            result.success(testResults)
                        }
                    }
                } ?: run {
                    testResults["error"] = "WiFi P2P not initialized"
                    runOnUiThread {
                        result.success(testResults)
                    }
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("TEST_ERROR", "Failed to test connection: ${e.message}", null)
                }
            }
        }.start()
    }

    private fun detectSystemNetworks(result: MethodChannel.Result) {
        Thread {
            try {
                val networkData = mutableMapOf<String, Any>()

                // Check WiFi Direct connections created manually
                channel?.let { ch ->
                    // Check if we're part of a WiFi Direct group
                    wifiP2pManager.requestConnectionInfo(ch) { connectionInfo ->
                        if (connectionInfo?.groupFormed == true) {
                            networkData["wifiDirectActive"] = true
                            networkData["isGroupOwner"] = connectionInfo.isGroupOwner
                            networkData["groupOwnerAddress"] = connectionInfo.groupOwnerAddress?.hostAddress ?: ""

                            // Get group information
                            wifiP2pManager.requestGroupInfo(ch) { groupInfo ->
                                if (groupInfo != null) {
                                    networkData["networkName"] = groupInfo.networkName ?: "Unknown"
                                    networkData["passphrase"] = groupInfo.passphrase ?: ""

                                    // Get connected clients in the group
                                    val groupClients = groupInfo.clientList.map { client ->
                                        mapOf(
                                            "deviceName" to (client.deviceName ?: "Unknown"),
                                            "deviceAddress" to (client.deviceAddress ?: ""),
                                            "status" to when(client.status) {
                                                android.net.wifi.p2p.WifiP2pDevice.CONNECTED -> "connected"
                                                android.net.wifi.p2p.WifiP2pDevice.AVAILABLE -> "available"
                                                android.net.wifi.p2p.WifiP2pDevice.INVITED -> "invited"
                                                android.net.wifi.p2p.WifiP2pDevice.FAILED -> "failed"
                                                android.net.wifi.p2p.WifiP2pDevice.UNAVAILABLE -> "unavailable"
                                                else -> "unknown"
                                            }
                                        )
                                    }
                                    networkData["wifiDirectClients"] = groupClients

                                    android.util.Log.d("WiFiDirect", "Manual WiFi Direct group detected:")
                                    android.util.Log.d("WiFiDirect", "  Network: ${groupInfo.networkName}")
                                    android.util.Log.d("WiFiDirect", "  Clients: ${groupClients.size}")
                                }

                                // Check for hotspot information
                                hotspotManager.getHotspotInfo(object : MethodChannel.Result {
                                    override fun success(hotspotResult: Any?) {
                                        if (hotspotResult is Map<*, *>) {
                                            networkData["hotspotInfo"] = hotspotResult
                                            if (hotspotResult["isActive"] == true) {
                                                // Get connected hotspot clients
                                                hotspotManager.getConnectedClients(object : MethodChannel.Result {
                                                    override fun success(clientsResult: Any?) {
                                                        if (clientsResult is List<*>) {
                                                            networkData["hotspotClients"] = clientsResult
                                                            android.util.Log.d("WiFiDirect", "Manual hotspot detected with ${(clientsResult as List<*>).size} clients")
                                                        }

                                                        runOnUiThread {
                                                            result.success(networkData)
                                                        }
                                                    }
                                                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                                                        runOnUiThread {
                                                            result.success(networkData)
                                                        }
                                                    }
                                                    override fun notImplemented() {
                                                        runOnUiThread {
                                                            result.success(networkData)
                                                        }
                                                    }
                                                })
                                            } else {
                                                runOnUiThread {
                                                    result.success(networkData)
                                                }
                                            }
                                        } else {
                                            runOnUiThread {
                                                result.success(networkData)
                                            }
                                        }
                                    }
                                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                                        runOnUiThread {
                                            result.success(networkData)
                                        }
                                    }
                                    override fun notImplemented() {
                                        runOnUiThread {
                                            result.success(networkData)
                                        }
                                    }
                                })
                            }
                        } else {
                            networkData["wifiDirectActive"] = false

                            // Still check for hotspot even if no WiFi Direct
                            hotspotManager.getHotspotInfo(object : MethodChannel.Result {
                                override fun success(hotspotResult: Any?) {
                                    if (hotspotResult is Map<*, *>) {
                                        networkData["hotspotInfo"] = hotspotResult
                                        if (hotspotResult["isActive"] == true) {
                                            hotspotManager.getConnectedClients(object : MethodChannel.Result {
                                                override fun success(clientsResult: Any?) {
                                                    if (clientsResult is List<*>) {
                                                        networkData["hotspotClients"] = clientsResult
                                                    }
                                                    runOnUiThread {
                                                        result.success(networkData)
                                                    }
                                                }
                                                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                                                    runOnUiThread {
                                                        result.success(networkData)
                                                    }
                                                }
                                                override fun notImplemented() {
                                                    runOnUiThread {
                                                        result.success(networkData)
                                                    }
                                                }
                                            })
                                        } else {
                                            runOnUiThread {
                                                result.success(networkData)
                                            }
                                        }
                                    } else {
                                        runOnUiThread {
                                            result.success(networkData)
                                        }
                                    }
                                }
                                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                                    runOnUiThread {
                                        result.success(networkData)
                                    }
                                }
                                override fun notImplemented() {
                                    runOnUiThread {
                                        result.success(networkData)
                                    }
                                }
                            })
                        }
                    }
                } ?: run {
                    networkData["error"] = "WiFi P2P not initialized"
                    runOnUiThread {
                        result.success(networkData)
                    }
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("DETECT_ERROR", "Failed to detect networks: ${e.message}", null)
                }
            }
        }.start()
    }

    private fun cleanupSockets() {
        try {
            // Close all client connections
            synchronized(connectedClients) {
                connectedClients.forEach { client ->
                    try {
                        client.close()
                    } catch (e: Exception) {
                        android.util.Log.e("WiFiDirect", "Error closing client socket", e)
                    }
                }
                connectedClients.clear()
            }

            // Close server socket
            serverSocket?.close()
            serverSocket = null

            // Close client socket
            clientSocket?.close()
            clientSocket = null

            isSocketEstablished = false
            android.util.Log.d("WiFiDirect", "All sockets cleaned up")
        } catch (e: Exception) {
            android.util.Log.e("WiFiDirect", "Error during socket cleanup", e)
        }
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
