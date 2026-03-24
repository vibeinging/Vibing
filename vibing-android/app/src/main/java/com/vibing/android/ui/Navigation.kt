package com.vibing.android.ui

import androidx.compose.material3.windowsizeclass.WindowWidthSizeClass
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.vibing.android.data.AccountManager
import com.vibing.android.model.SessionInfo
import com.vibing.android.ui.devices.DeviceListScreen
import com.vibing.android.ui.login.LoginScreen
import com.vibing.android.ui.settings.SettingsScreen
import com.vibing.android.ui.terminal.TerminalScreen
import com.vibing.android.ui.terminal.TerminalTabletScreen
import kotlinx.coroutines.launch

@Composable
fun VibingNavigation(
    accountManager: AccountManager,
    widthSizeClass: WindowWidthSizeClass
) {
    val navController = rememberNavController()
    val isSignedIn by accountManager.isSignedIn.collectAsState()
    val username by accountManager.username.collectAsState()
    val devices by accountManager.devices.collectAsState()
    val scope = rememberCoroutineScope()

    val startDest = if (isSignedIn) "devices" else "login"

    NavHost(navController, startDestination = startDest) {

        composable("login") {
            LoginScreen(
                onLogin = { server, user, pass -> accountManager.login(server, user, pass) },
                onRegister = { server, user, pass -> accountManager.register(server, user, pass) },
                onQrLogin = { server, code -> accountManager.qrLogin(server, code) },
                onSuccess = { navController.navigate("devices") { popUpTo("login") { inclusive = true } } }
            )
        }

        composable("devices") {
            DeviceListScreen(
                devices = devices,
                onRefresh = { scope.launch { accountManager.fetchDevices() } },
                onDeviceTap = { device ->
                    // 尝试自动查找 relay session
                    scope.launch {
                        val sessions = accountManager.fetchRelaySessions()
                        val match = sessions.find { it.deviceId == device.id && it.role == "host" }
                        if (match != null) {
                            navController.navigate("terminal/${match.sessionId}")
                        }
                    }
                },
                onSettingsTap = { navController.navigate("settings") }
            )
        }

        composable("settings") {
            SettingsScreen(
                username = username,
                onSignOut = {
                    accountManager.signOut()
                    navController.navigate("login") { popUpTo(0) { inclusive = true } }
                },
                onDismiss = { navController.popBackStack() }
            )
        }

        composable("terminal/{sessionCode}") { backStackEntry ->
            val sessionCode = backStackEntry.arguments?.getString("sessionCode") ?: return@composable

            // Mock sessions for now (real: fetch from WebSocket)
            val sessions = remember {
                listOf(
                    SessionInfo("sess_1", true),
                    SessionInfo("sess_2", true),
                    SessionInfo("sess_3", true)
                )
            }
            var selectedIndex by remember { mutableIntStateOf(0) }
            var outputText by remember { mutableStateOf("❯ Connected to session $sessionCode\n\n") }

            val isTablet = widthSizeClass == WindowWidthSizeClass.Expanded

            if (isTablet) {
                TerminalTabletScreen(
                    sessions = sessions,
                    selectedIndex = selectedIndex,
                    outputText = outputText,
                    onSelectSession = { selectedIndex = it },
                    onSendInput = { text -> outputText += "$ $text\n" },
                    onBack = { navController.popBackStack() }
                )
            } else {
                TerminalScreen(
                    sessions = sessions,
                    selectedIndex = selectedIndex,
                    outputText = outputText,
                    onSelectSession = { selectedIndex = it },
                    onSendInput = { text -> outputText += "$ $text\n" },
                    onBack = { navController.popBackStack() }
                )
            }
        }
    }
}
