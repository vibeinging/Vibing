package com.vibing.android.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class RegisterRequest(
    val username: String,
    val password: String,
    @SerialName("device_name") val deviceName: String,
    @SerialName("device_type") val deviceType: String
)

@Serializable
data class LoginRequest(
    val username: String,
    val password: String,
    @SerialName("device_id") val deviceId: String? = null,
    @SerialName("device_name") val deviceName: String? = null,
    @SerialName("device_type") val deviceType: String? = null
)

@Serializable
data class QrLoginRequest(
    val code: String,
    @SerialName("device_id") val deviceId: String? = null,
    @SerialName("device_name") val deviceName: String? = null,
    @SerialName("device_type") val deviceType: String? = null
)

@Serializable
data class AuthResponse(
    val token: String,
    @SerialName("user_id") val userId: String,
    val username: String,
    @SerialName("device_id") val deviceId: String? = null
)

@Serializable
data class UserInfo(
    @SerialName("user_id") val userId: String,
    val username: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("last_login") val lastLogin: String? = null
)

@Serializable
data class ErrorResponse(
    val error: String
)
