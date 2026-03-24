package com.vibing.android.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class SessionInfo(
    val id: String,
    @SerialName("is_active") val isActive: Boolean = true
)

@Serializable
data class RelaySession(
    @SerialName("session_id") val sessionId: String,
    @SerialName("device_id") val deviceId: String,
    val role: String,
    @SerialName("created_at") val createdAt: String
)
