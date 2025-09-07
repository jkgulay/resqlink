package com.example.resqlink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.NetworkInfo
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.WifiP2pDeviceList
import android.net.wifi.p2p.WifiP2pInfo
import android.util.Log

class WifiDirectBroadcastReceiver(
    private val manager: WifiP2pManager,
    private val channel: WifiP2pManager.Channel?,
    private val activity: MainActivity
) : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                handleWifiP2pStateChanged(intent)
            }

            WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                handlePeersChanged()
            }

            WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                handleConnectionChanged(intent)
            }

            WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                handleThisDeviceChanged(intent)
            }
        }
    }

    private fun handleWifiP2pStateChanged(intent: Intent) {
        val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
        val enabled = state == WifiP2pManager.WIFI_P2P_STATE_ENABLED
        
        Log.d("WifiDirectReceiver", "WiFi P2P state changed: $enabled")
        
        val data = mapOf(
            "enabled" to enabled,
            "state" to state
        )
        activity.sendToFlutter("wifi", "onWifiStateChanged", data)
    }

    private fun handlePeersChanged() {
        Log.d("WifiDirectReceiver", "WiFi P2P peers changed")
        
        channel?.let { channel ->
            manager.requestPeers(channel) { peers ->
                val peerList = peers.deviceList.map { device ->
                    mapOf(
                        "deviceName" to device.deviceName,
                        "deviceAddress" to device.deviceAddress,
                        "status" to device.status,
                        "primaryDeviceType" to device.primaryDeviceType,
                        "secondaryDeviceType" to device.secondaryDeviceType,
                        "isServiceDiscoveryCapable" to device.isServiceDiscoveryCapable,
                        "isGroupOwner" to device.isGroupOwner,
                        "wpsPbc" to device.wpsPbcConfigMethodSupported(),
                        "wpsKeypad" to device.wpsKeypadConfigMethodSupported(),
                        "wpsDisplay" to device.wpsDisplayConfigMethodSupported()
                    )
                }
                
                Log.d("WifiDirectReceiver", "Found ${peerList.size} peers")
                
                val data = mapOf(
                    "peers" to peerList,
                    "timestamp" to System.currentTimeMillis()
                )
                activity.sendToFlutter("wifi", "onWifiDirectPeersChanged", data)
            }
        }
    }

    private fun handleConnectionChanged(intent: Intent) {
        val networkInfo = intent.getParcelableExtra<NetworkInfo>(WifiP2pManager.EXTRA_NETWORK_INFO)
        val wifiP2pInfo = intent.getParcelableExtra<WifiP2pInfo>(WifiP2pManager.EXTRA_WIFI_P2P_INFO)
        
        Log.d("WifiDirectReceiver", "WiFi P2P connection changed - Connected: ${networkInfo?.isConnected}")
        
        if (networkInfo?.isConnected == true) {
            // Connection established
            channel?.let { channel ->
                manager.requestConnectionInfo(channel) { info ->
                    val connectionData = mapOf(
                        "isConnected" to info.groupFormed,
                        "isGroupOwner" to info.isGroupOwner,
                        "groupOwnerAddress" to (info.groupOwnerAddress?.hostAddress ?: ""),
                        "networkInfo" to mapOf(
                            "isConnected" to (networkInfo.isConnected),
                            "extraInfo" to (networkInfo.extraInfo ?: ""),
                            "reason" to (networkInfo.reason ?: ""),
                            "state" to networkInfo.state.name
                        )
                    )
                    
                    Log.d("WifiDirectReceiver", "Connection info - Group formed: ${info.groupFormed}, Group owner: ${info.isGroupOwner}")
                    
                    activity.sendToFlutter("wifi", "onConnectionChanged", connectionData)
                    
                    // Also request group info if we're connected
                    if (info.groupFormed) {
                        requestGroupInfo()
                    }
                }
            }
        } else {
            // Connection lost
            val connectionData = mapOf(
                "isConnected" to false,
                "isGroupOwner" to false,
                "groupOwnerAddress" to "",
                "networkInfo" to mapOf(
                    "isConnected" to false,
                    "extraInfo" to (networkInfo?.extraInfo ?: ""),
                    "reason" to (networkInfo?.reason ?: ""),
                    "state" to (networkInfo?.state?.name ?: "UNKNOWN")
                )
            )
            
            activity.sendToFlutter("wifi", "onConnectionChanged", connectionData)
        }
    }

    private fun handleThisDeviceChanged(intent: Intent) {
        val device = intent.getParcelableExtra<android.net.wifi.p2p.WifiP2pDevice>(WifiP2pManager.EXTRA_WIFI_P2P_DEVICE)
        
        device?.let {
            Log.d("WifiDirectReceiver", "This device changed: ${it.deviceName} (${it.deviceAddress})")
            
            val deviceData = mapOf(
                "deviceName" to it.deviceName,
                "deviceAddress" to it.deviceAddress,
                "status" to it.status,
                "primaryDeviceType" to it.primaryDeviceType,
                "secondaryDeviceType" to it.secondaryDeviceType,
                "isServiceDiscoveryCapable" to it.isServiceDiscoveryCapable,
                "isGroupOwner" to it.isGroupOwner
            )
            
            activity.sendToFlutter("wifi", "onThisDeviceChanged", deviceData)
        }
    }

    private fun requestGroupInfo() {
        channel?.let { channel ->
            manager.requestGroupInfo(channel) { group ->
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
                        "isGroupOwner" to group.isGroupOwner,
                        "clientCount" to clients.size
                    )
                    
                    Log.d("WifiDirectReceiver", "Group info - Network: ${group.networkName}, Clients: ${clients.size}")
                    
                    activity.sendToFlutter("wifi", "onGroupInfoChanged", groupInfo)
                } else {
                    Log.d("WifiDirectReceiver", "No group information available")
                    activity.sendToFlutter("wifi", "onGroupInfoChanged", null)
                }
            }
        }
    }
}