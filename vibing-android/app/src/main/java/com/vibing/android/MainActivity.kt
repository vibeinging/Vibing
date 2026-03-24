package com.vibing.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.windowsizeclass.ExperimentalMaterial3WindowSizeClassApi
import androidx.compose.material3.windowsizeclass.calculateWindowSizeClass
import com.vibing.android.data.AccountManager
import com.vibing.android.ui.VibingNavigation
import com.vibing.android.ui.theme.VibingTheme

class MainActivity : ComponentActivity() {

    private lateinit var accountManager: AccountManager

    @OptIn(ExperimentalMaterial3WindowSizeClassApi::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        accountManager = AccountManager(applicationContext)

        setContent {
            val windowSizeClass = calculateWindowSizeClass(this)

            VibingTheme {
                VibingNavigation(
                    accountManager = accountManager,
                    widthSizeClass = windowSizeClass.widthSizeClass
                )
            }
        }
    }
}
