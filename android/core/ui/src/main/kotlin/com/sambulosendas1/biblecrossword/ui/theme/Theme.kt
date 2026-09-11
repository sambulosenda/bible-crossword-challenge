package com.sambulosendas1.biblecrossword.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sambulosendas1.biblecrossword.domain.prefs.AppTheme

/*
 * The design system, ported from iOS `Theme/Theme.swift`: a warm paper canvas
 * with white cards, solid "ink" pill CTAs, serif type reserved for scripture
 * and hero titles, on the app's blue accent. Hierarchy, not colour, carries
 * emphasis. Never red for the accent.
 */

@Immutable
data class BccColors(
    /** iOS system blue — the brand colour. */
    val accent: Color,
    /** Warm paper canvas instead of the cool system grey. */
    val background: Color,
    /** Card surface: white on paper in light; a warm elevated grey in dark. */
    val surface: Color,
    /** "Ink" — the solid fill behind the one loud pill CTA per screen. */
    val ink: Color,
    /** Text/icon colour on an ink fill. */
    val onInk: Color,
    /** Rim on celebration badges. One token so the three badges can't drift. */
    val badgeRim: Color,
    /** Primary and secondary label colours (iOS `.primary` / `.secondary`). */
    val label: Color,
    val secondaryLabel: Color,
    val separator: Color,
    // Grid cells
    val cellEmpty: Color,
    val cellInWord: Color,
    val isDark: Boolean,
) {
    val cellSelected: Color get() = accent.copy(alpha = 0.85f)
    val cellError: Color get() = Color(0xFFFF3B30).copy(alpha = 0.28f)
    val cellCorrect: Color get() = Color(0xFF34C759).copy(alpha = 0.18f)

    fun cellFill(isSelected: Boolean, isInWord: Boolean, showError: Boolean, isCorrect: Boolean): Color = when {
        isSelected -> cellSelected
        showError -> cellError
        isCorrect -> cellCorrect
        isInWord -> cellInWord
        else -> cellEmpty
    }

    fun cellText(isSelected: Boolean, isPencil: Boolean = false): Color = when {
        isPencil -> if (isSelected) Color.White.copy(alpha = 0.8f) else secondaryLabel
        isSelected -> Color.White
        else -> label
    }
}

val LightColors = BccColors(
    accent = Color(0xFF007AFF),
    background = Color(0xFFF7F5F2),
    surface = Color.White,
    ink = Color(0xFF121212),
    onInk = Color.White,
    badgeRim = Color(0xFFCD981B),
    label = Color(0xFF000000),
    secondaryLabel = Color(0x993C3C43),
    separator = Color(0x4A3C3C43),
    cellEmpty = Color.White,
    cellInWord = Color(0xFF007AFF).copy(alpha = 0.18f),
    isDark = false,
)

val DarkColors = BccColors(
    accent = Color(0xFF0A84FF),
    background = Color(0xFF0E0D0C),
    surface = Color(0xFF1C1B1A),
    ink = Color.White,
    onInk = Color(0xFF121212),
    badgeRim = Color(0xFFF9CC4C),
    label = Color(0xFFFFFFFF),
    secondaryLabel = Color(0x99EBEBF5),
    separator = Color(0x99545458),
    cellEmpty = Color(0xFF1C1C1E),
    cellInWord = Color(0xFF0A84FF).copy(alpha = 0.30f),
    isDark = true,
)

object Spacing {
    val xs: Dp = 4.dp
    val s: Dp = 8.dp
    val m: Dp = 16.dp
    val l: Dp = 24.dp
    val xl: Dp = 32.dp
}

val CardCornerRadius: Dp = 20.dp

/**
 * Scripture and hero titles are set in a serif, matching how YouVersion renders
 * verse content; UI chrome stays on the default sans. One family token so the
 * face can be swapped (Literata / Source Serif 4 — still an open decision) in
 * exactly one place.
 */
val ScriptureFamily: FontFamily = FontFamily.Serif

fun scripture(size: Int, weight: FontWeight = FontWeight.Normal, lineHeight: Int = (size * 1.35).toInt()): TextStyle =
    TextStyle(fontFamily = ScriptureFamily, fontSize = size.sp, fontWeight = weight, lineHeight = lineHeight.sp)

val LocalBccColors = staticCompositionLocalOf { LightColors }

object BccTheme {
    val colors: BccColors
        @Composable get() = LocalBccColors.current
}

private fun BccColors.toMaterial(): ColorScheme = if (isDark) {
    darkColorScheme(
        primary = accent, onPrimary = Color.White,
        background = background, onBackground = label,
        surface = surface, onSurface = label,
        surfaceVariant = surface, onSurfaceVariant = secondaryLabel,
        outline = separator,
    )
} else {
    lightColorScheme(
        primary = accent, onPrimary = Color.White,
        background = background, onBackground = label,
        surface = surface, onSurface = label,
        surfaceVariant = surface, onSurfaceVariant = secondaryLabel,
        outline = separator,
    )
}

@Composable
fun BccTheme(appTheme: AppTheme = AppTheme.SYSTEM, content: @Composable () -> Unit) {
    val dark = when (appTheme) {
        AppTheme.SYSTEM -> isSystemInDarkTheme()
        AppTheme.LIGHT -> false
        AppTheme.DARK -> true
    }
    val colors = if (dark) DarkColors else LightColors
    CompositionLocalProvider(LocalBccColors provides colors) {
        MaterialTheme(colorScheme = colors.toMaterial(), content = content)
    }
}
