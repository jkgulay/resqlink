package com.example.resqlink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.NetworkInfo
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.WifiP2pDeviceList
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pConfig
import android.util.Log

class WifiDirectBroadcastReceiver(
    private val manager: WifiP2pManager,
    private val channel: WifiP2pManager.Channel?,
    private val activity: MainActivity
) : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        // Add null check for intent
        intent ?: return
        
        val action = intent.action

        when (action) {
            WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                val isEnabled = state == WifiP2pManager.WIFI_P2P_STATE_ENABLED

                Log.d("WifiDirectReceiver", "📡 WiFi P2P state changed: enabled=$isEnabled, state=$state")

                // CRITICAL FIX: Request device info when WiFi Direct becomes enabled
                if (isEnabled) {
                    Log.d("WifiDirectReceiver", "🔍 WiFi Direct enabled - requesting device info...")
                    channel?.let { ch ->
                        manager.requestDeviceInfo(ch) { device ->
                            if (device != null) {
                                Log.d("WifiDirectReceiver", "📱 Device info from state change: ${device.deviceName} (${device.deviceAddress})")
                                sendDeviceInfo(device)
                            } else {
                                Log.w("WifiDirectReceiver", "⚠️ Device info is null after WiFi Direct enabled")
                            }
                        }
                    } ?: Log.w("WifiDirectReceiver", "⚠️ Channel is null, cannot request device info")
                }

                val stateMap = mapOf(
                    "isEnabled" to isEnabled,
                    "state" to state
                )
                activity.sendToFlutter("wifi_direct", "onStateChanged", stateMap)
            }

            WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                Log.d("WifiDirectReceiver", "Peers list changed - requesting peer list...")

                // CRITICAL FIX: Request peer list when peers change
                channel?.let { ch ->
                    manager.requestPeers(ch) { peers ->
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
                                "primaryDeviceType" to (device.primaryDeviceType ?: "Unknown Type")
                            )
                        }

                        Log.d("WifiDirectReceiver", "✅ Found ${peersList.size} peers:")
                        peersList.forEach { peer ->
                            Log.d("WifiDirectReceiver", "  📱 ${peer["deviceName"]} (${peer["deviceAddress"]}) - ${peer["status"]}")
                        }

                        // CRITICAL: Auto-accept invitation if we're the client (lower intent device)
                        // This fixes the "stuck at invited" issue when both devices connect simultaneously
                        peers.deviceList.forEach { device ->
                            if (device.status == WifiP2pDevice.INVITED) {
                                Log.d("WifiDirectReceiver", "📨 Received invitation from ${device.deviceName}")
                                
                                // Check if we should accept (we're the client, not the owner)
                                val myDeviceAddress = activity.getSharedPreferences("resqlink_prefs", android.content.Context.MODE_PRIVATE)
                                    .getString("wifi_direct_mac_address", "") ?: ""
                                val peerAddress = device.deviceAddress ?: ""
                                
                                if (myDeviceAddress.isNotEmpty() && peerAddress.isNotEmpty()) {
                                    val shouldBeClient = myDeviceAddress.hashCode() < peerAddress.hashCode()
                                    
                                    if (shouldBeClient) {
                                        Log.d("WifiDirectReceiver", "🤝 Auto-accepting invitation from ${device.deviceName} (we are client)")
                                        
                                        // Create connection config with low group owner intent (we want to be client)
                                        val config = WifiP2pConfig().apply {
                                            deviceAddress = device.deviceAddress
                                            groupOwnerIntent = 0 // We want to be client
                                        }
                                        
                                        // Connect to accept the invitation
                                        manager.connect(ch, config, object : WifiP2pManager.ActionListener {
                                            override fun onSuccess() {
                                                Log.d("WifiDirectReceiver", "✅ Successfully accepted invitation from ${device.deviceName}")
                                            }
                                            override fun onFailure(reason: Int) {
                                                Log.e("WifiDirectReceiver", "❌ Failed to accept invitation: $reason")
                                            }
                                        })
                                    } else {
                                        Log.d("WifiDirectReceiver", "👑 We are group owner, waiting for ${device.deviceName} to join")
                                    }
                                }
                            }
                        }

                        // Send peer list to Flutter
                        activity.sendToFlutter("wifi_direct", "onPeersUpdated", mapOf("peers" to peersList))

                        // Also send onPeersChanged for backward compatibility
                        activity.sendToFlutter("wifi_direct", "onPeersChanged", mapOf("peers" to peersList))
                    }
                } ?: run {
                    Log.e("WifiDirectReceiver", "❌ Channel is null, cannot request peers")
                }
            }

            WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                handleConnectionChanged(intent) // Now intent is guaranteed non-null
            }

            WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                Log.d("WifiDirectReceiver", "📱 WIFI_P2P_THIS_DEVICE_CHANGED_ACTION received!")
                val device = intent.getParcelableExtra<WifiP2pDevice>(WifiP2pManager.EXTRA_WIFI_P2P_DEVICE)
                if (device != null) {
                    Log.d("WifiDirectReceiver", "📱 Device changed: ${device.deviceName} (${device.deviceAddress})")
                    sendDeviceInfo(device)
                } else {
                    Log.w("WifiDirectReceiver", "⚠️ Device is null in WIFI_P2P_THIS_DEVICE_CHANGED_ACTION")
                }
            }
        }
    }

    private fun getWifiDirectMacFromInterface(): String? {
        try {
            val interfaces = java.net.NetworkInterface.getNetworkInterfaces()
            while (interfaces.hasMoreElements()) {
                val intf = interfaces.nextElement()
                val name = intf.name
                if (name.startsWith("p2p")) {
                    val mac = intf.hardwareAddress
                    if (mac != null && mac.size == 6) {
                        val macString = mac.joinToString(":") { String.format("%02X", it) }
                        Log.d("WifiDirectReceiver", "🔍 Found p2p interface '$name' with MAC: $macString")
                        if (macString != "02:00:00:00:00:00") {
                            return macString
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e("WifiDirectReceiver", "❌ Error getting MAC from interface: ${e.message}")
        }
        return null
    }

    private fun sendDeviceInfo(device: WifiP2pDevice) {
        Log.d("WifiDirectReceiver", "📤 sendDeviceInfo called")

        var macAddress = device.deviceAddress ?: ""
        val deviceName = device.deviceName ?: "Unknown Device"

        Log.d("WifiDirectReceiver", "📱 Device info from API: $deviceName ($macAddress)")

        // CRITICAL FIX: If API returns placeholder, try to get from network interface
        if (macAddress.isEmpty() || macAddress == "02:00:00:00:00:00") {
            Log.w("WifiDirectReceiver", "⚠️ API returned placeholder/empty MAC, trying network interface...")
            val interfaceMac = getWifiDirectMacFromInterface()
            if (interfaceMac != null) {
                Log.d("WifiDirectReceiver", "✅ Got real MAC from network interface: $interfaceMac")
                macAddress = interfaceMac
            } else {
                Log.w("WifiDirectReceiver", "⚠️ Could not get MAC from network interface either")
            }
        }

        val deviceMap = mutableMapOf<String, Any>()
        deviceMap["deviceName"] = deviceName
        deviceMap["deviceAddress"] = macAddress
        deviceMap["primaryDeviceType"] = device.primaryDeviceType ?: "Unknown Type"
        deviceMap["secondaryDeviceType"] = device.secondaryDeviceType ?: "Unknown Secondary Type"
        deviceMap["status"] = device.status
        deviceMap["supportsWps"] = true

        Log.d("WifiDirectReceiver", "📤 Device info map with MAC: $deviceMap")

        // Store MAC address if valid
        if (macAddress.isNotEmpty() && macAddress != "02:00:00:00:00:00") {
            try {
                val prefs = activity.getSharedPreferences("resqlink_prefs", android.content.Context.MODE_PRIVATE)
                prefs.edit().putString("wifi_direct_mac_address", macAddress).apply()
                Log.d("WifiDirectReceiver", "✅ Stored WiFi Direct MAC: $macAddress")
            } catch (e: Exception) {
                Log.e("WifiDirectReceiver", "❌ Failed to store MAC address: ${e.message}")
            }
        } else {
            Log.w("WifiDirectReceiver", "⚠️ Skipping placeholder MAC: $macAddress")
        }

        Log.d("WifiDirectReceiver", "📞 Sending onDeviceChanged to Flutter")
        activity.sendToFlutter("wifi_direct", "onDeviceChanged", deviceMap)
        Log.d("WifiDirectReceiver", "✅ sendToFlutter completed")
    }

 private fun handleConnectionChanged(intent: Intent) {
    val networkInfo = intent.getParcelableExtra<NetworkInfo>(WifiP2pManager.EXTRA_NETWORK_INFO)
    val wifiP2pInfo = intent.getParcelableExtra<WifiP2pInfo>(WifiP2pManager.EXTRA_WIFI_P2P_INFO)

    android.util.Log.d("WifiDirectReceiver", "Connection changed - Connected: ${networkInfo?.isConnected}")
    android.util.Log.d("WifiDirectReceiver", "Group formed: ${wifiP2pInfo?.groupFormed}")
    android.util.Log.d("WifiDirectReceiver", "Group owner: ${wifiP2pInfo?.isGroupOwner}")
    android.util.Log.d("WifiDirectReceiver", "Group owner address: ${wifiP2pInfo?.groupOwnerAddress?.hostAddress}")

    if (networkInfo?.isConnected == true && wifiP2pInfo != null) {
        // CRITICAL: Request device info AFTER connection to get real MAC address
        Log.d("WifiDirectReceiver", "🔍 Connection established - requesting device info...")
        channel?.let { ch ->
            manager.requestDeviceInfo(ch) { device ->
                if (device != null) {
                    Log.d("WifiDirectReceiver", "📱 Device info after connection: ${device.deviceName} (${device.deviceAddress})")
                    // Send to Flutter which will validate and store
                    sendDeviceInfo(device)
                } else {
                    Log.w("WifiDirectReceiver", "⚠️ Device info is null after connection")
                }
            }
        } ?: Log.w("WifiDirectReceiver", "⚠️ Channel is null after connection")
        val connectionInfo = mutableMapOf<String, Any>()
        connectionInfo["isConnected"] = true
        connectionInfo["isGroupOwner"] = wifiP2pInfo.isGroupOwner
        connectionInfo["groupOwnerAddress"] = wifiP2pInfo.groupOwnerAddress?.hostAddress ?: ""
        connectionInfo["groupFormed"] = wifiP2pInfo.groupFormed

        // Always request peer list when connection changes
        channel?.let { ch ->
            manager.requestPeers(ch) { peers ->
                // CRITICAL: Check if there's actually a connected peer (status: CONNECTED = 0)
                val hasConnectedPeer = peers.deviceList.any { it.status == WifiP2pDevice.CONNECTED }
                
                android.util.Log.d("WifiDirectReceiver", "Group formed: ${wifiP2pInfo.groupFormed}, Has connected peer: $hasConnectedPeer")
                
                // Update connection info with actual peer connection status
                connectionInfo["isConnected"] = wifiP2pInfo.groupFormed && hasConnectedPeer
                connectionInfo["hasConnectedPeer"] = hasConnectedPeer
                
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
                        }
                    )
                }

                android.util.Log.d("WifiDirectReceiver", "Found ${peersList.size} peers after connection")
                peersList.forEach { peer ->
                    android.util.Log.d("WifiDirectReceiver", "  - ${peer["deviceName"]} (${peer["deviceAddress"]}) - ${peer["status"]}")
                }

                // Send peer list update
                activity.sendToFlutter("wifi_direct", "onPeersUpdated", mapOf("peers" to peersList))

                // If this is a system-level connection WITH an actual connected peer, send special notification
                if (wifiP2pInfo.groupFormed && hasConnectedPeer) {
                    android.util.Log.d("WifiDirectReceiver", "✅ System-level WiFi Direct connection with connected peer!")

                    val systemConnectionData = mapOf(
                        "systemConnection" to true,
                        "connectionInfo" to connectionInfo,
                        "peers" to peersList
                    )

                    activity.sendToFlutter("wifi_direct", "onSystemConnectionDetected", systemConnectionData)
                } else if (wifiP2pInfo.groupFormed && !hasConnectedPeer) {
                    android.util.Log.d("WifiDirectReceiver", "⏳ Group formed but no peer connected yet (all peers are invited/available)")
                }
                
                // Send standard connection changed event with updated status
                activity.sendToFlutter("wifi_direct", "onConnectionChanged", connectionInfo)
            }
        }
    } else {
        // Handle disconnection
        val disconnectionInfo = mapOf<String, Any>(
            "isConnected" to false,
            "isGroupOwner" to false,
            "groupOwnerAddress" to "",
            "groupFormed" to false
        )
        activity.sendToFlutter("wifi_direct", "onConnectionChanged", disconnectionInfo)
        
        // Also update peer list on disconnection
        channel?.let { ch ->
            manager.requestPeers(ch) { peers ->
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
                        }
                    )
                }
                
                android.util.Log.d("WifiDirectReceiver", "Updated peers after disconnection: ${peersList.size}")
                activity.sendToFlutter("wifi_direct", "onPeersUpdated", mapOf("peers" to peersList))
            }
        }
    }
}

    fun onPeersAvailable(peers: WifiP2pDeviceList) {
    val peersList = mutableListOf<Map<String, Any>>()
    
    for (device in peers.deviceList) {
        val deviceInfo = createDeviceMap(device)
        peersList.add(deviceInfo)
        
        // CRITICAL FIX: Log connection status
        if (device.status == WifiP2pDevice.CONNECTED) {
            android.util.Log.d("WifiDirectReceiver", "CONNECTED PEER: ${device.deviceName} (${device.deviceAddress})")
        }
    }
    
    val peersMap = mapOf("peers" to peersList)
    activity.sendToFlutter("wifi_direct", "onPeersAvailable", peersMap)
    }

    private fun createDeviceMap(device: WifiP2pDevice): Map<String, Any> {
        return mapOf(
            "deviceName" to (device.deviceName ?: "Unknown Device"),
            "deviceAddress" to (device.deviceAddress ?: "Unknown Address"),
            "primaryDeviceType" to (device.primaryDeviceType ?: "Unknown Type"),
            "secondaryDeviceType" to (device.secondaryDeviceType ?: "Unknown Secondary Type"),
            "status" to device.status,
            "supportsWps" to true // Simplified assumption
        )
    }
}