package com.follow.flashco.models

import com.follow.flashco.service.models.VpnOptions
import com.google.gson.JsonObject

data class SharedState(
    val startTip: String = "Starting VPN...",
    val stopTip: String = "Stopping VPN...",
    val localNetworkTip: String =
        "Local network permission denied: using the gvisor stack, LAN is unreachable.",
    val currentProfileName: String = "Flashco",
    val stopText: String = "Stop",
    val onlyStatisticsProxy: Boolean = false,
    val showStopAction: Boolean = true,
    val vpnOptions: VpnOptions? = null,
    val setupParams: JsonObject? = null,
)
