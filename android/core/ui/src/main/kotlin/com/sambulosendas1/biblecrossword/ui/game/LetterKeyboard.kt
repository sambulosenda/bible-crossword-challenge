package com.sambulosendas1.biblecrossword.ui.game

import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.clickable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Backspace
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sambulosendas1.biblecrossword.ui.haptics.LocalHaptics
import com.sambulosendas1.biblecrossword.ui.theme.BccTheme
import com.sambulosendas1.biblecrossword.ui.theme.Spacing

private val ROWS = listOf("QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM")

/**
 * Custom A–Z keypad. A dedicated keyboard avoids autocorrect and return-key
 * issues and gives precise control over crossword entry — and on Android it
 * also sidesteps the IME entirely, which is one of the three things most
 * likely to break a port.
 */
@Composable
fun LetterKeyboard(
    onLetter: (Char) -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
    isPencilMode: Boolean = false,
    /** Present only where pencil entry exists; onboarding keeps the plain pad. */
    onTogglePencil: (() -> Unit)? = null,
) {
    val haptics = LocalHaptics.current
    // Key height grows with the user's text-size setting so large glyphs
    // aren't clipped — Compose dp never scales on its own.
    val fontScale = LocalDensity.current.fontScale
    val keyHeight = (46 * fontScale.coerceIn(1f, 1.6f)).dp

    Column(
        modifier = modifier
            .fillMaxWidth()
            // On a tablet the keys stop growing at a hand's width — a Q
            // stretched to an eighth of a 13" screen stops reading as a key.
            .widthIn(max = 560.dp)
            .padding(horizontal = Spacing.s, vertical = Spacing.m),
        verticalArrangement = Arrangement.spacedBy(Spacing.s),
    ) {
        for (row in ROWS) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                val isLast = row == ROWS.last()
                if (row.length < 10) Box(Modifier.weight(0.5f))
                if (isLast && onTogglePencil != null) {
                    Key(
                        modifier = Modifier.weight(1.4f),
                        height = keyHeight,
                        onClick = { haptics.keyTap(); onTogglePencil() },
                        semantics = {
                            contentDescription = "Pencil mode"
                            stateDescription = if (isPencilMode) "on" else "off"
                        },
                    ) {
                        Icon(
                            Icons.Filled.Edit,
                            contentDescription = null,
                            tint = if (isPencilMode) BccTheme.colors.accent else BccTheme.colors.label,
                        )
                    }
                }
                for (letter in row) {
                    Key(
                        modifier = Modifier.weight(1f),
                        height = keyHeight,
                        onClick = { haptics.keyTap(); onLetter(letter) },
                        semantics = { contentDescription = letter.toString() },
                    ) {
                        Text(
                            text = letter.toString(),
                            fontSize = 20.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = BccTheme.colors.label,
                        )
                    }
                }
                if (isLast) {
                    Key(
                        modifier = Modifier.weight(1.4f),
                        height = keyHeight,
                        onClick = { haptics.keyTap(); onDelete() },
                        semantics = { contentDescription = "Delete" },
                    ) {
                        Icon(
                            Icons.AutoMirrored.Filled.Backspace,
                            contentDescription = null,
                            tint = BccTheme.colors.label,
                        )
                    }
                }
                if (row.length < 10) Box(Modifier.weight(0.5f))
            }
        }
    }
}

/**
 * A key with an instant pressed state. A real key highlights the moment a
 * finger touches it — respond on pointer-down, not on release. The depress
 * lands on the same event as the haptic.
 */
@Composable
private fun RowScope.Key(
    modifier: Modifier,
    height: androidx.compose.ui.unit.Dp,
    onClick: () -> Unit,
    semantics: androidx.compose.ui.semantics.SemanticsPropertyReceiver.() -> Unit,
    content: @Composable () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val colors = BccTheme.colors
    Box(
        modifier = modifier
            .heightIn(min = height)
            .graphicsLayer { val s = if (pressed) 0.96f else 1f; scaleX = s; scaleY = s }
            .background(
                color = if (pressed) colors.label.copy(alpha = 0.18f) else colors.label.copy(alpha = 0.07f),
                shape = RoundedCornerShape(8.dp),
            )
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .semantics(mergeDescendants = true, properties = semantics),
        contentAlignment = Alignment.Center,
        content = { content() },
    )
}
