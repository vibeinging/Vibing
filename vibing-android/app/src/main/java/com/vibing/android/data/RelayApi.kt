package com.vibing.android.data

import com.vibing.android.model.*
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

class RelayApi(private val baseUrl: String) {

    private val json = Json { ignoreUnknownKeys = true }
    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    private val jsonMediaType = "application/json".toMediaType()

    suspend fun register(req: RegisterRequest): AuthResponse {
        val body = json.encodeToString(RegisterRequest.serializer(), req).toRequestBody(jsonMediaType)
        val request = Request.Builder().url("$baseUrl/auth/register").post(body).build()
        return execute(request)
    }

    suspend fun login(req: LoginRequest): AuthResponse {
        val body = json.encodeToString(LoginRequest.serializer(), req).toRequestBody(jsonMediaType)
        val request = Request.Builder().url("$baseUrl/auth/login").post(body).build()
        return execute(request)
    }

    suspend fun qrLogin(req: QrLoginRequest): AuthResponse {
        val body = json.encodeToString(QrLoginRequest.serializer(), req).toRequestBody(jsonMediaType)
        val request = Request.Builder().url("$baseUrl/auth/qr-login").post(body).build()
        return execute(request)
    }

    suspend fun getDevices(token: String): List<DeviceInfo> {
        val request = Request.Builder().url("$baseUrl/devices").authed(token).build()
        return executeList(request)
    }

    suspend fun getSessions(token: String): List<RelaySession> {
        val request = Request.Builder().url("$baseUrl/sessions").authed(token).build()
        return executeList(request)
    }

    suspend fun deleteDevice(deviceId: String, token: String) {
        val request = Request.Builder().url("$baseUrl/devices/$deviceId").authed(token).delete().build()
        client.newCall(request).execute().close()
    }

    private inline fun <reified T> execute(request: Request): T {
        val response = client.newCall(request).execute()
        val responseBody = response.body?.string() ?: throw Exception("Empty response")
        if (!response.isSuccessful) {
            val err = try { json.decodeFromString(ErrorResponse.serializer(), responseBody) } catch (_: Exception) { null }
            throw Exception(err?.error ?: "Request failed: ${response.code}")
        }
        return json.decodeFromString(responseBody)
    }

    private inline fun <reified T> executeList(request: Request): List<T> {
        val response = client.newCall(request).execute()
        val responseBody = response.body?.string() ?: throw Exception("Empty response")
        if (!response.isSuccessful) throw Exception("Request failed: ${response.code}")
        return json.decodeFromString(responseBody)
    }

    private fun Request.Builder.authed(token: String) = addHeader("Authorization", "Bearer $token")
}
