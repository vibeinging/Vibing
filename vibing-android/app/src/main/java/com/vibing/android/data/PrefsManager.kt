package com.vibing.android.data

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

class PrefsManager(context: Context) {

    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val securePrefs = EncryptedSharedPreferences.create(
        context, "vibing_secure", masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    private val prefs = context.getSharedPreferences("vibing_prefs", Context.MODE_PRIVATE)

    // Token (encrypted)
    var token: String?
        get() = securePrefs.getString("auth_token", null)
        set(value) = securePrefs.edit().apply {
            if (value != null) putString("auth_token", value) else remove("auth_token")
        }.apply()

    // Account info
    var accountId: String?
        get() = prefs.getString("account_id", null)
        set(value) = prefs.edit().putString("account_id", value).apply()

    var username: String?
        get() = prefs.getString("username", null)
        set(value) = prefs.edit().putString("username", value).apply()

    var serverUrl: String
        get() = prefs.getString("server_url", "") ?: ""
        set(value) = prefs.edit().putString("server_url", value).apply()

    fun clear() {
        securePrefs.edit().clear().apply()
        prefs.edit().remove("account_id").remove("username").apply()
    }
}
