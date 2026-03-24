package com.vibing.android.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.vibing.android.R

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    username: String,
    onSignOut: () -> Unit,
    onDismiss: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.settings_title)) },
                navigationIcon = {
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = null)
                    }
                }
            )
        }
    ) { padding ->
        Column(modifier = Modifier.padding(padding).padding(16.dp)) {
            // Account section
            Text(
                stringResource(R.string.settings_account),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.5f)
            )
            Spacer(Modifier.height(8.dp))

            ListItem(
                headlineContent = { Text(stringResource(R.string.settings_username)) },
                trailingContent = { Text(username, color = MaterialTheme.colorScheme.primary) }
            )

            Divider()

            ListItem(
                headlineContent = {
                    Text(stringResource(R.string.settings_sign_out), color = MaterialTheme.colorScheme.error)
                },
                modifier = Modifier.clickable { onSignOut() }
            )

            Spacer(Modifier.height(16.dp))

            Text(
                stringResource(R.string.settings_account_footer),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.4f)
            )
        }
    }
}

