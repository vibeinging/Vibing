package com.vibing.android.ui.devices

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.vibing.android.R
import com.vibing.android.model.DeviceInfo
import com.vibing.android.ui.theme.SpringGreen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DeviceListScreen(
    devices: List<DeviceInfo>,
    onRefresh: () -> Unit,
    onDeviceTap: (DeviceInfo) -> Unit,
    onSettingsTap: () -> Unit
) {
    LaunchedEffect(Unit) { onRefresh() }

    Scaffold(
        topBar = {
            LargeTopAppBar(
                title = { Text(stringResource(R.string.devices_title)) },
                actions = {
                    IconButton(onClick = onSettingsTap) {
                        Icon(Icons.Default.Person, contentDescription = null, tint = SpringGreen)
                    }
                }
            )
        }
    ) { padding ->
        if (devices.isEmpty()) {
            Column(
                modifier = Modifier.fillMaxSize().padding(padding),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Icon(
                    Icons.Default.DevicesOther,
                    contentDescription = null,
                    modifier = Modifier.size(64.dp),
                    tint = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.2f)
                )
                Spacer(Modifier.height(16.dp))
                Text(
                    stringResource(R.string.devices_no_devices),
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.5f)
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    stringResource(R.string.devices_no_devices_hint),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.3f)
                )
            }
        } else {
            LazyColumn(
                modifier = Modifier.padding(padding),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                item {
                    Text(
                        stringResource(R.string.devices_your_devices),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.4f),
                        modifier = Modifier.padding(start = 4.dp, bottom = 8.dp, top = 4.dp)
                    )
                }
                items(devices) { device ->
                    DeviceCard(device = device, onClick = { onDeviceTap(device) })
                }
            }
        }
    }
}

@Composable
fun DeviceCard(device: DeviceInfo, onClick: () -> Unit) {
    val icon = when (device.deviceType) {
        "mac" -> Icons.Default.Computer
        "ios" -> Icons.Default.PhoneIphone
        "android" -> Icons.Default.PhoneAndroid
        "web" -> Icons.Default.Language
        else -> Icons.Default.Devices
    }

    Surface(
        shape = RoundedCornerShape(14.dp),
        color = MaterialTheme.colorScheme.surface,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = device.isOnline, onClick = onClick)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Surface(
                shape = RoundedCornerShape(12.dp),
                color = if (device.isOnline) SpringGreen.copy(alpha = 0.12f) else MaterialTheme.colorScheme.surfaceVariant,
                modifier = Modifier.size(44.dp)
            ) {
                Icon(
                    icon,
                    contentDescription = null,
                    modifier = Modifier.padding(10.dp),
                    tint = if (device.isOnline) SpringGreen else MaterialTheme.colorScheme.onBackground.copy(alpha = 0.3f)
                )
            }

            Spacer(Modifier.width(14.dp))

            Column(modifier = Modifier.weight(1f)) {
                Text(device.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Surface(
                        shape = RoundedCornerShape(4.dp),
                        color = if (device.isOnline) SpringGreen else MaterialTheme.colorScheme.onBackground.copy(alpha = 0.2f),
                        modifier = Modifier.size(7.dp)
                    ) {}
                    Spacer(Modifier.width(6.dp))
                    Text(
                        if (device.isOnline) stringResource(R.string.devices_online) else stringResource(R.string.devices_offline),
                        style = MaterialTheme.typography.labelSmall,
                        color = if (device.isOnline) SpringGreen else MaterialTheme.colorScheme.onBackground.copy(alpha = 0.35f)
                    )
                }
            }

            if (device.isOnline) {
                Icon(
                    Icons.Default.ChevronRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.2f)
                )
            }
        }
    }
}
