package com.sambulosendas1.biblecrossword.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/** `.primary` is the single loud action on a screen; `.tonal` its quiet sibling. */
enum class PillEmphasis { PRIMARY, TONAL }

/** YouVersion-style capsule CTA — iOS `PillButtonStyle`. */
@Composable
fun PillButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    emphasis: PillEmphasis = PillEmphasis.PRIMARY,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    val colors = BccTheme.colors
    val container = if (emphasis == PillEmphasis.PRIMARY) colors.ink else colors.label.copy(alpha = 0.08f)
    val label = if (emphasis == PillEmphasis.PRIMARY) colors.onInk else colors.label
    Button(
        onClick = onClick,
        modifier = modifier.fillMaxWidth(),
        enabled = enabled,
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(containerColor = container, contentColor = label),
        contentPadding = ButtonDefaults.ContentPadding.let { androidx.compose.foundation.layout.PaddingValues(horizontal = Spacing.l, vertical = 15.dp) },
        content = content,
    )
}

/** The standard card treatment: white on paper, lifted by a whisper of shadow. */
fun Modifier.elevatedCard(fill: Color? = null): Modifier = this
    .shadow(elevation = 3.dp, shape = RoundedCornerShape(CardCornerRadius), ambientColor = Color.Black.copy(alpha = 0.05f), spotColor = Color.Black.copy(alpha = 0.05f))
    .let { m -> if (fill != null) m.background(fill, RoundedCornerShape(CardCornerRadius)) else m }

/** The shared eyebrow/kicker above every card heading — muted, uppercase, tracked. */
@Composable
fun Kicker(text: String, modifier: Modifier = Modifier, color: Color = BccTheme.colors.secondaryLabel) {
    Text(
        text = text.uppercase(),
        modifier = modifier,
        color = color,
        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold, letterSpacing = 1.sp),
    )
}

private val Int.sp get() = androidx.compose.ui.unit.TextUnit(this.toFloat(), androidx.compose.ui.unit.TextUnitType.Sp)
