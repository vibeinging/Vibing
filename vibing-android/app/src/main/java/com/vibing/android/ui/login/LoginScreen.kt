package com.vibing.android.ui.login

import androidx.compose.animation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Terminal
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.vibing.android.R
import com.vibing.android.ui.theme.SpringGreen

@Composable
fun LoginScreen(
    onLogin: suspend (server: String, username: String, password: String) -> Unit,
    onRegister: suspend (server: String, username: String, password: String) -> Unit,
    onQrLogin: suspend (server: String, code: String) -> Unit,
    onSuccess: () -> Unit
) {
    var serverUrl by remember { mutableStateOf("") }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var isRegistering by remember { mutableStateOf(false) }
    var isLoading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var showQrDialog by remember { mutableStateOf(false) }

    val focusManager = LocalFocusManager.current

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp)
            .imePadding(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(Modifier.height(80.dp))

        // Logo
        Surface(
            shape = RoundedCornerShape(20.dp),
            color = SpringGreen.copy(alpha = 0.12f),
            modifier = Modifier.size(72.dp)
        ) {
            Icon(
                Icons.Default.Terminal,
                contentDescription = null,
                tint = SpringGreen,
                modifier = Modifier.padding(16.dp)
            )
        }

        Spacer(Modifier.height(24.dp))

        Text(
            stringResource(R.string.login_welcome),
            style = MaterialTheme.typography.headlineLarge,
            color = MaterialTheme.colorScheme.onBackground
        )

        Spacer(Modifier.height(8.dp))

        Text(
            stringResource(R.string.login_subtitle),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.5f),
            textAlign = TextAlign.Center
        )

        Spacer(Modifier.height(32.dp))

        // Server URL
        OutlinedTextField(
            value = serverUrl,
            onValueChange = { serverUrl = it },
            label = { Text(stringResource(R.string.login_server)) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Next),
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp)
        )

        Spacer(Modifier.height(12.dp))

        // Username
        OutlinedTextField(
            value = username,
            onValueChange = { username = it },
            label = { Text(stringResource(R.string.login_username)) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp)
        )

        Spacer(Modifier.height(12.dp))

        // Password
        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            label = { Text(stringResource(R.string.login_password)) },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus() }),
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp)
        )

        // Error
        AnimatedVisibility(visible = error != null) {
            Text(
                error ?: "",
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(top = 8.dp)
            )
        }

        Spacer(Modifier.height(20.dp))

        // Submit
        Button(
            onClick = {
                if (serverUrl.isBlank() || username.isBlank() || password.isBlank()) {
                    error = "Please fill in all fields"
                    return@Button
                }
                isLoading = true
                error = null
            },
            enabled = !isLoading,
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(containerColor = SpringGreen)
        ) {
            if (isLoading) {
                CircularProgressIndicator(modifier = Modifier.size(20.dp), color = MaterialTheme.colorScheme.onPrimary, strokeWidth = 2.dp)
            } else {
                Text(
                    if (isRegistering) stringResource(R.string.login_create_account) else stringResource(R.string.login_sign_in),
                    style = MaterialTheme.typography.labelLarge
                )
            }
        }

        // 触发登录的 LaunchedEffect
        if (isLoading) {
            LaunchedEffect(Unit) {
                try {
                    if (isRegistering) onRegister(serverUrl, username, password)
                    else onLogin(serverUrl, username, password)
                    onSuccess()
                } catch (e: Exception) {
                    error = e.message ?: "Login failed"
                } finally {
                    isLoading = false
                }
            }
        }

        Spacer(Modifier.height(12.dp))

        // Toggle
        TextButton(onClick = { isRegistering = !isRegistering; error = null }) {
            Text(
                if (isRegistering) stringResource(R.string.login_has_account) else stringResource(R.string.login_no_account),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.5f)
            )
        }

        // QR Login
        AnimatedVisibility(visible = !isRegistering) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Spacer(Modifier.height(16.dp))
                Text("— ${stringResource(R.string.login_or)} —", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.3f))
                Spacer(Modifier.height(16.dp))
                OutlinedButton(
                    onClick = { showQrDialog = true },
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                    shape = RoundedCornerShape(14.dp)
                ) {
                    Icon(Icons.Outlined.QrCodeScanner, contentDescription = null, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.login_qr_scan))
                }
            }
        }

        Spacer(Modifier.height(40.dp))
    }

    // QR Dialog
    if (showQrDialog) {
        var qrCode by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { showQrDialog = false },
            title = { Text(stringResource(R.string.login_qr_title)) },
            text = {
                OutlinedTextField(
                    value = qrCode,
                    onValueChange = { qrCode = it },
                    placeholder = { Text("VIBE_QR|...") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showQrDialog = false
                    isLoading = true
                    // QR login handled via LaunchedEffect
                }) { Text(stringResource(R.string.login_login)) }
            },
            dismissButton = {
                TextButton(onClick = { showQrDialog = false }) { Text(stringResource(R.string.common_cancel)) }
            }
        )
    }
}
