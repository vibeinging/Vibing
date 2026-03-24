package com.vibing.android.ui.terminal

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vibing.android.R
import com.vibing.android.model.SessionInfo
import com.vibing.android.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TerminalTabletScreen(
    sessions: List<SessionInfo>,
    selectedIndex: Int,
    outputText: String,
    onSelectSession: (Int) -> Unit,
    onSendInput: (String) -> Unit,
    onBack: () -> Unit
) {
    var inputValue by remember { mutableStateOf(TextFieldValue()) }
    val scrollState = rememberScrollState()

    LaunchedEffect(outputText) {
        scrollState.animateScrollTo(scrollState.maxValue)
    }

    val quickActions = listOf(
        "⌃C" to "\u0003", "⌃D" to "\u0004", "⌃Z" to "\u001A",
        "⌃L" to "\u000C", "Tab" to "\t", "↑" to "\u001B[A",
        "↓" to "\u001B[B", "Esc" to "\u001B"
    )

    Row(modifier = Modifier.fillMaxSize().background(TerminalBg)) {
        // Left sidebar — session list
        Surface(
            color = SurfaceCardDark,
            modifier = Modifier.width(240.dp).fillMaxHeight()
        ) {
            Column {
                // Header
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .statusBarsPadding()
                        .padding(horizontal = 12.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(onClick = onBack, modifier = Modifier.size(32.dp)) {
                        Icon(Icons.Default.ChevronLeft, contentDescription = null, tint = Color.White.copy(alpha = 0.6f))
                    }
                    Spacer(Modifier.width(8.dp))
                    Text(
                        stringResource(R.string.sessions_terminal_sessions),
                        style = MaterialTheme.typography.titleMedium,
                        color = Color.White.copy(alpha = 0.8f)
                    )
                    Spacer(Modifier.weight(1f))
                    Surface(
                        shape = RoundedCornerShape(4.dp),
                        color = SpringGreen,
                        modifier = Modifier.size(8.dp)
                    ) {}
                }

                Divider(color = Color.White.copy(alpha = 0.06f))

                // Session list
                LazyColumn(
                    contentPadding = PaddingValues(8.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    itemsIndexed(sessions) { index, session ->
                        val isSelected = index == selectedIndex
                        Surface(
                            shape = RoundedCornerShape(10.dp),
                            color = if (isSelected) SpringGreen.copy(alpha = 0.12f) else Color.Transparent,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onSelectSession(index) }
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    Icons.Default.Terminal,
                                    contentDescription = null,
                                    tint = if (isSelected) SpringGreen else Color.White.copy(alpha = 0.3f),
                                    modifier = Modifier.size(18.dp)
                                )
                                Spacer(Modifier.width(10.dp))
                                Column {
                                    Text(
                                        stringResource(R.string.sessions_session_number, index + 1),
                                        style = MaterialTheme.typography.bodyMedium,
                                        fontWeight = if (isSelected) FontWeight.SemiBold else null,
                                        color = if (isSelected) Color.White else Color.White.copy(alpha = 0.55f)
                                    )
                                    Text(
                                        session.id.take(12),
                                        fontFamily = FontFamily.Monospace,
                                        fontSize = 10.sp,
                                        color = Color.White.copy(alpha = 0.2f)
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        // Divider
        Spacer(modifier = Modifier.width(1.dp).fillMaxHeight().background(Color.White.copy(alpha = 0.06f)))

        // Right — terminal output + input
        Column(modifier = Modifier.weight(1f).fillMaxHeight()) {
            // Output
            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(scrollState)
                    .padding(horizontal = 16.dp, vertical = 12.dp)
            ) {
                Text(
                    text = outputText,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 13.sp,
                    lineHeight = 18.sp,
                    color = TerminalFg
                )
            }

            // Input bar
            Surface(
                color = SurfaceCardDark,
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(8.dp).navigationBarsPadding()) {
                    // Quick actions
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        modifier = Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 8.dp)
                    ) {
                        quickActions.forEach { (label, seq) ->
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

                    Row(
                        modifier = Modifier.padding(horizontal = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        TextField(
                            value = inputValue,
                            onValueChange = { inputValue = it },
                            placeholder = {
                                Text("$ command...", fontFamily = FontFamily.Monospace, fontSize = 14.sp, color = Color.White.copy(alpha = 0.25f))
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

                        VoiceInputButton(
                            onResult = { text -> inputValue = TextFieldValue(text) }
                        )

                        IconButton(onClick = {
                            if (inputValue.text.isNotEmpty()) {
                                onSendInput(inputValue.text + "\r")
                                inputValue = TextFieldValue()
                            }
                        }) {
                            Icon(Icons.Default.ArrowUpward, contentDescription = null, tint = SpringGreen, modifier = Modifier.size(28.dp))
                        }
                    }
                }
            }
        }
    }
}
