package com.vibing.android.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class DeviceInfo(
    val id: String,
    val name: String,
    @SerialName("device_type") val deviceType: String,
    val platform: String? = null,
    @SerialName("registered_at") val registeredAt: String? = null,
    @SerialName("last_seen") val lastSeen: String? = null,
    @SerialName("is_online") val isOnline: Boolean = false
) {
    val displayType: String
        get() = when (deviceType) {
            "mac" -> "Mac"
            "ios" -> "iPhone/iPad"
            "android" -> "Android"
            "web" -> "Web"
            else -> deviceType
        }

    val typeIcon: String
        get() = when (deviceType) {
            "mac" -> "computer"
            "ios" -> "phone_iphone"
            "android" -> "phone_android"
            "web" -> "language"
            else -> "devices"
        }
}
