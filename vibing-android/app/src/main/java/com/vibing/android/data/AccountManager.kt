package com.vibing.android.data

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.provider.Settings
import com.vibing.android.model.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext

class AccountManager(private val context: Context) {

    private val prefs = PrefsManager(context)

    private val _isSignedIn = MutableStateFlow(prefs.token != null && prefs.accountId != null)
    val isSignedIn: StateFlow<Boolean> = _isSignedIn

    private val _username = MutableStateFlow(prefs.username ?: "")
    val username: StateFlow<String> = _username

    private val _devices = MutableStateFlow<List<DeviceInfo>>(emptyList())
    val devices: StateFlow<List<DeviceInfo>> = _devices

    val token: String? get() = prefs.token
    val serverUrl: String get() = prefs.serverUrl

    private fun api(): RelayApi = RelayApi(prefs.serverUrl)

    private fun deviceId(): String {
        @SuppressLint("HardwareIds")
        val id = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
        return id.take(16).lowercase()
    }

    private fun deviceName(): String = "${Build.MANUFACTURER} ${Build.MODEL}"

    suspend fun register(serverUrl: String, username: String, password: String) = withContext(Dispatchers.IO) {
        prefs.serverUrl = serverUrl
        val resp = api().register(RegisterRequest(username, password, deviceName(), "android"))
        saveAuth(resp)
    }

    suspend fun login(serverUrl: String, username: String, password: String) = withContext(Dispatchers.IO) {
        prefs.serverUrl = serverUrl
        val resp = api().login(LoginRequest(username, password, deviceId(), deviceName(), "android"))
        saveAuth(resp)
    }

    suspend fun qrLogin(serverUrl: String, code: String) = withContext(Dispatchers.IO) {
        prefs.serverUrl = serverUrl
        val resp = api().qrLogin(QrLoginRequest(code, deviceId(), deviceName(), "android"))
        saveAuth(resp)
    }

    fun signOut() {
        prefs.clear()
        _isSignedIn.value = false
        _username.value = ""
        _devices.value = emptyList()
    }

    suspend fun fetchDevices() = withContext(Dispatchers.IO) {
        val t = prefs.token ?: return@withContext
        _devices.value = api().getDevices(t)
    }

    suspend fun fetchRelaySessions(): List<RelaySession> = withContext(Dispatchers.IO) {
        val t = prefs.token ?: return@withContext emptyList()
        api().getSessions(t)
    }

    private fun saveAuth(resp: AuthResponse) {
        prefs.token = resp.token
        prefs.accountId = resp.userId
        prefs.username = resp.username
        _username.value = resp.username
        _isSignedIn.value = true
    }
}
