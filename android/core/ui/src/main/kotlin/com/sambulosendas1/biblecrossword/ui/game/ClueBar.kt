package com.sambulosendas1.biblecrossword.ui.game

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sambulosendas1.biblecrossword.domain.engine.StallNudgeKind
import com.sambulosendas1.biblecrossword.ui.theme.BccTheme
import com.sambulosendas1.biblecrossword.ui.theme.Spacing

/**
 * The active clue above the keyboard, with previous/next navigation, the
 * rescue nudge, and a progress strip along the bottom edge.
 *
 * The nudge shares the clue-number line rather than claiming a row: as its own
 * row it grew the bar, and the grid takes whatever height is left — so every
 * cell resized the moment the nudge appeared, which is precisely the moment
 * the player was already stuck.
 */
@Composable
fun ClueBar(
    state: GameUiState,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onToggleDirection: () -> Unit,
    onStallTap: () -> Unit,
    onVerseTap: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = BccTheme.colors
    val progress by animateFloatAsState(state.progress, tween(350), label = "progress")

    Column(
        modifier
            .fillMaxWidth()
            .background(colors.surface)
            .drawBehind {
                // Thin strip along the bottom that fills as the grid does,
                // turning green at the solve.
                val h = 3.dp.toPx()
                val y = size.height - h
                drawRect(colors.label.copy(alpha = 0.08f), topLeft = androidx.compose.ui.geometry.Offset(0f, y), size = Size(size.width, h))
                drawRect(
                    if (state.isComplete) Color(0xFF34C759) else colors.accent,
                    topLeft = androidx.compose.ui.geometry.Offset(0f, y),
                    size = Size(size.width * progress, h),
                )
            }
            .padding(horizontal = Spacing.s)
            // Room to breathe: the bar sits between a grid and a keyboard with
            // no margin of its own, and the bottom must also clear the strip.
            .padding(top = Spacing.s, bottom = Spacing.s + Spacing.xs),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.s)) {
            IconButton(onClick = onPrevious, modifier = Modifier.size(44.dp).semantics { contentDescription = "Previous clue" }) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = null, tint = colors.label)
            }

            Column(
                Modifier
                    .weight(1f)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        onClick = onToggleDirection,
                    ),
                verticalArrangement = Arrangement.spacedBy(Spacing.s),
            ) {
                val clue = state.activeClue
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = clue?.let { "${it.number} ${it.direction.label}" } ?: "",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = colors.accent,
                    )
                    Box(Modifier.weight(1f))
                    Nudge(state, onStallTap)
                }
                Text(
                    text = clue?.text ?: "Select a cell to begin",
                    fontSize = 15.sp,
                    color = if (clue == null) colors.secondaryLabel else colors.label,
                    // Reserved, not just capped: without two lines always held,
                    // a one-line and a two-line clue give the bar different
                    // heights and the grid reflows on plain clue navigation.
                    minLines = 2,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }

            // Only on clues that have a passage: an always-present icon would
            // advertise a hint most clues can't offer, and a dimmed one is a
            // question the player can't answer.
            if (state.activeClue?.hasReference == true) {
                IconButton(onClick = onVerseTap, modifier = Modifier.size(44.dp).semantics { contentDescription = "Read the verse" }) {
                    Icon(Icons.AutoMirrored.Filled.MenuBook, contentDescription = null, tint = colors.accent)
                }
            }

            IconButton(onClick = onNext, modifier = Modifier.size(44.dp).semantics { contentDescription = "Next clue" }) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = colors.label)
            }
        }
    }
}

/**
 * The rescue offer, or the endgame countdown. Only the stall tier is tappable —
 * the endgame line is encouragement, with nothing to act on. The stall line
 * outranks it while active: a stuck player needs an action, not a cheer.
 */
@Composable
private fun Nudge(state: GameUiState, onStallTap: () -> Unit) {
    val colors = BccTheme.colors
    AnimatedVisibility(
        visible = state.isStallNudgeActive,
        enter = fadeIn(),
        exit = fadeOut(),
    ) {
        val (text, icon, hint) = when (state.stallNudgeKind) {
            StallNudgeKind.CHECK_ANSWERS -> Triple("Check answers", Icons.Filled.CheckCircle, "Checks the whole puzzle for mistakes")
            StallNudgeKind.READ_VERSE -> Triple("Read the verse", Icons.AutoMirrored.Filled.MenuBook, "Opens the passage this clue comes from, without using a hint")
            StallNudgeKind.FREE_LETTER -> Triple("Free letter", Icons.Filled.Lightbulb, "Reveals one letter without using a hint")
        }
        Row(
            Modifier
                .background(colors.accent.copy(alpha = 0.12f), CircleShape)
                .clickable(onClick = onStallTap)
                .padding(horizontal = Spacing.s, vertical = Spacing.xs)
                .semantics(mergeDescendants = true) { contentDescription = "$text. $hint" },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
        ) {
            Icon(icon, contentDescription = null, tint = colors.accent, modifier = Modifier.size(14.dp))
            Text(text, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = colors.accent, maxLines = 1)
        }
    }
    if (!state.isStallNudgeActive) {
        state.endgameNudge?.let { remaining ->
            Text(
                text = if (remaining == 1) "Last clue!" else "$remaining clues to go!",
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                color = colors.accent,
                maxLines = 1,
                modifier = Modifier.padding(vertical = Spacing.xs).clearAndSetSemantics { },
            )
        }
    }
}
