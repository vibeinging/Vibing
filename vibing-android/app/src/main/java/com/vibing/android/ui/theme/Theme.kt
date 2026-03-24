package com.vibing.android.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColorScheme = darkColorScheme(
    primary = SpringGreen,
    onPrimary = Color.White,
    primaryContainer = SpringGreenDark,
    secondary = SpringGreenLight,
    background = SurfaceDark,
    surface = SurfaceCardDark,
    onBackground = Color(0xFFE8E8E3),
    onSurface = Color(0xFFE8E8E3),
    surfaceVariant = Color(0xFF2A2C30),
    outline = Color(0xFF3A3C40),
)

private val LightColorScheme = lightColorScheme(
    primary = SpringGreen,
    onPrimary = Color.White,
    primaryContainer = SpringGreenContainer,
    secondary = SpringGreenDark,
    background = Color(0xFFF5F5F0),
    surface = Color.White,
    onBackground = Color(0xFF1C1C1A),
    onSurface = Color(0xFF1C1C1A),
)

@Composable
fun VibingTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme

    MaterialTheme(
        colorScheme = colorScheme,
        typography = VibingTypography,
        content = content
    )
}
