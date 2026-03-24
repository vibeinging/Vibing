package com.vibing.android.ui.terminal

import androidx.compose.animation.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vibing.android.R
import com.vibing.android.model.SessionInfo
import com.vibing.android.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TerminalScreen(
    sessions: List<SessionInfo>,
    selectedIndex: Int,
    outputText: String,
    onSelectSession: (Int) -> Unit,
    onSendInput: (String) -> Unit,
    onBack: () -> Unit
) {
    var inputValue by remember { mutableStateOf(TextFieldValue()) }
    val focusManager = LocalFocusManager.current
    val scrollState = rememberScrollState()

    // Auto-scroll to bottom when output changes
    LaunchedEffect(outputText) {
        scrollState.animateScrollTo(scrollState.maxValue)
    }

    val quickActions = listOf(
        "⌃C" to "\u0003", "⌃D" to "\u0004", "⌃Z" to "\u001A",
        "⌃L" to "\u000C", "Tab" to "\t", "↑" to "\u001B[A",
        "↓" to "\u001B[B", "Esc" to "\u001B"
    )

    Scaffold(
        containerColor = TerminalBg,
        topBar = {
            // Compact top bar: back + tabs + status dot
            Surface(color = SurfaceCardDark) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .statusBarsPadding()
                        .padding(horizontal = 4.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(onClick = onBack, modifier = Modifier.size(36.dp)) {
                        Icon(Icons.Default.ChevronLeft, contentDescription = null, tint = Color.White.copy(alpha = 0.6f))
                    }

                    // Session tabs
                    LazyRow(
                        modifier = Modifier.weight(1f),
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        contentPadding = PaddingValues(horizontal = 4.dp)
                    ) {
                        itemsIndexed(sessions) { index, _ ->
                            val isSelected = index == selectedIndex
                            Surface(
                                shape = RoundedCornerShape(8.dp),
                                color = if (isSelected) Color.White.copy(alpha = 0.1f) else Color.Transparent,
                                modifier = Modifier.clickable { onSelectSession(index) }
                            ) {
                                Text(
                                    stringResource(R.string.sessions_session_number, index + 1),
                                    style = MaterialTheme.typography.labelMedium,
                                    fontWeight = if (isSelected) androidx.compose.ui.text.font.FontWeight.Bold else null,
                                    color = if (isSelected) Color.White else Color.White.copy(alpha = 0.35f),
                                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp)
                                )
                            }
                        }
                    }

                    // Status dot
                    Surface(
                        shape = RoundedCornerShape(4.dp),
                        color = SpringGreen,
                        modifier = Modifier.padding(end = 16.dp).size(8.dp)
                    ) {}
                }
            }
        },
        bottomBar = {
            // Floating input bar
            Surface(
                modifier = Modifier.padding(horizontal = 8.dp, vertical = 6.dp).navigationBarsPadding(),
                shape = RoundedCornerShape(22.dp),
                color = SurfaceCardDark.copy(alpha = 0.95f),
                border = BorderStroke(0.5.dp, Color.White.copy(alpha = 0.1f))
            ) {
                Column(modifier = Modifier.padding(top = 8.dp, bottom = 8.dp)) {
                    // Quick actions
                    LazyRow(
                        contentPadding = PaddingValues(horizontal = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        items(quickActions.size) { i ->
                            val (label, seq) = quickActions[i]
                            Surface(
                                shape = RoundedCornerShape(7.dp),
                                color = Color.White.copy(alpha = 0.08f),
                                modifier = Modifier.clickable { onSendInput(seq) }
                            ) {
                                Text(
                                    label,
                                    fontFamily = FontFamily.Monospace,
                                    fontSize = 12.sp,
                                    color = Color.White.copy(alpha = 0.6f),
                                    modifier = Modifier.padding(horizontal = 11.dp, vertical = 5.dp)
                                )
                            }
                        }
                    }

                    Spacer(Modifier.height(6.dp))

                    // Input field + send
                    Row(
                        modifier = Modifier.padding(horizontal = 10.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        TextField(
                            value = inputValue,
                            onValueChange = { inputValue = it },
                            placeholder = {
                                Text(
                                    "$ command...",
                                    fontFamily = FontFamily.Monospace,
                                    fontSize = 14.sp,
                                    color = Color.White.copy(alpha = 0.25f)
                                )
                            },
                            singleLine = true,
                            colors = TextFieldDefaults.colors(
                                focusedContainerColor = Color.White.copy(alpha = 0.06f),
                                unfocusedContainerColor = Color.White.copy(alpha = 0.06f),
                                cursorColor = SpringGreen,
                                focusedIndicatorColor = Color.Transparent,
                                unfocusedIndicatorColor = Color.Transparent,
                                focusedTextColor = Color.White,
                                unfocusedTextColor = Color.White,
                            ),
                            textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace, fontSize = 14.sp),
                            shape = RoundedCornerShape(14.dp),
                            modifier = Modifier.weight(1f).height(42.dp)
                        )

                        // Voice input
                        VoiceInputButton(
                            onResult = { text -> inputValue = TextFieldValue(text) }
                        )

                        // Send
                        IconButton(
                            onClick = {
                                if (inputValue.text.isNotEmpty()) {
                                    onSendInput(inputValue.text + "\r")
                                    inputValue = TextFieldValue()
                                }
                            }
                        ) {
                            Icon(
                                Icons.Default.ArrowUpward,
                                contentDescription = null,
                                tint = SpringGreen,
                                modifier = Modifier.size(28.dp)
                            )
                        }
                    }
                }
            }
        }
    ) { padding ->
        // Terminal output
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(scrollState)
                .padding(horizontal = 12.dp, vertical = 8.dp)
        ) {
            Text(
                text = outputText,
                fontFamily = FontFamily.Monospace,
                fontSize = 13.sp,
                lineHeight = 18.sp,
                color = TerminalFg
            )
        }
    }
}
