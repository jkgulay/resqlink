package com.example.resqlink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.NetworkInfo
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.WifiP2pDeviceList
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pDevice
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
                
                Log.d("WifiDirectReceiver", "WiFi P2P state changed: $isEnabled")
                
                val stateMap = mapOf(
                    "isEnabled" to isEnabled,
                    "state" to state
                )
                activity.sendToFlutter("wifi_direct", "onStateChanged", stateMap)
            }

            WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                Log.d("WifiDirectReceiver", "Peers list changed")
                activity.sendToFlutter("wifi_direct", "onPeersChanged", emptyMap<String, Any>())
            }

            WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                handleConnectionChanged(intent) // Now intent is guaranteed non-null
            }

            WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                val device = intent.getParcelableExtra<WifiP2pDevice>(WifiP2pManager.EXTRA_WIFI_P2P_DEVICE)
                device?.let { sendDeviceInfo(it) }
            }
        }
    }

    private fun sendDeviceInfo(device: WifiP2pDevice) {
        val deviceMap = mutableMapOf<String, Any>()
        deviceMap["deviceName"] = device.deviceName ?: "Unknown Device"
        deviceMap["deviceAddress"] = device.deviceAddress ?: "Unknown Address"
        deviceMap["primaryDeviceType"] = device.primaryDeviceType ?: "Unknown Type"
        deviceMap["secondaryDeviceType"] = device.secondaryDeviceType ?: "Unknown Secondary Type"
        deviceMap["status"] = device.status

        // Remove deprecated WPS properties - use simpler approach
        deviceMap["supportsWps"] = true // Default assumption for modern devices

        // CRITICAL: Store WiFi Direct MAC address in SharedPreferences for native access
        device.deviceAddress?.let { macAddress ->
            try {
                val prefs = activity.getSharedPreferences("resqlink_prefs", android.content.Context.MODE_PRIVATE)
                prefs.edit().putString("wifi_direct_mac_address", macAddress).apply()
                android.util.Log.d("WifiDirectReceiver", "✅ Stored WiFi Direct MAC: $macAddress")
            } catch (e: Exception) {
                android.util.Log.e("WifiDirectReceiver", "Failed to store MAC address: ${e.message}")
            }
        }

        // Ensure we have a non-null map
        activity.sendToFlutter("wifi_direct", "onDeviceChanged", deviceMap)
    }

 private fun handleConnectionChanged(intent: Intent) {
    val networkInfo = intent.getParcelableExtra<NetworkInfo>(WifiP2pManager.EXTRA_NETWORK_INFO)
    val wifiP2pInfo = intent.getParcelableExtra<WifiP2pInfo>(WifiP2pManager.EXTRA_WIFI_P2P_INFO)

    android.util.Log.d("WifiDirectReceiver", "Connection changed - Connected: ${networkInfo?.isConnected}")
    android.util.Log.d("WifiDirectReceiver", "Group formed: ${wifiP2pInfo?.groupFormed}")
    android.util.Log.d("WifiDirectReceiver", "Group owner: ${wifiP2pInfo?.isGroupOwner}")
    android.util.Log.d("WifiDirectReceiver", "Group owner address: ${wifiP2pInfo?.groupOwnerAddress?.hostAddress}")

    if (networkInfo?.isConnected == true && wifiP2pInfo != null) {
        val connectionInfo = mutableMapOf<String, Any>()
        connectionInfo["isConnected"] = true
        connectionInfo["isGroupOwner"] = wifiP2pInfo.isGroupOwner
        connectionInfo["groupOwnerAddress"] = wifiP2pInfo.groupOwnerAddress?.hostAddress ?: ""
        connectionInfo["groupFormed"] = wifiP2pInfo.groupFormed

        // Always request peer list when connection changes
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

                android.util.Log.d("WifiDirectReceiver", "Found ${peersList.size} peers after connection")
                peersList.forEach { peer ->
                    android.util.Log.d("WifiDirectReceiver", "  - ${peer["deviceName"]} (${peer["deviceAddress"]}) - ${peer["status"]}")
                }

                // Send peer list update
                activity.sendToFlutter("wifi_direct", "onPeersUpdated", mapOf("peers" to peersList))

                // If this is a system-level connection, send special notification
                if (wifiP2pInfo.groupFormed) {
                    android.util.Log.d("WifiDirectReceiver", "System-level WiFi Direct connection detected!")

                    val systemConnectionData = mapOf(
                        "systemConnection" to true,
                        "connectionInfo" to connectionInfo,
                        "peers" to peersList
                    )

                    activity.sendToFlutter("wifi_direct", "onSystemConnectionDetected", systemConnectionData)
                }
            }
        }

        // Send standard connection changed event
        activity.sendToFlutter("wifi_direct", "onConnectionChanged", connectionInfo)
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