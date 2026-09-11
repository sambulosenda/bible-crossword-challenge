package com.sambulosendas1.biblecrossword.game

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sambulosendas1.biblecrossword.domain.completion.CompletionOutcome
import com.sambulosendas1.biblecrossword.domain.content.Puzzle
import com.sambulosendas1.biblecrossword.domain.profile.clockText
import com.sambulosendas1.biblecrossword.domain.today.StreakWeek
import com.sambulosendas1.biblecrossword.ui.theme.BccTheme
import com.sambulosendas1.biblecrossword.ui.theme.Kicker
import com.sambulosendas1.biblecrossword.ui.theme.PillButton
import com.sambulosendas1.biblecrossword.ui.theme.Spacing
import com.sambulosendas1.biblecrossword.ui.theme.elevatedCard
import com.sambulosendas1.biblecrossword.ui.theme.scripture
import java.time.DayOfWeek

/**
 * The payoff screen.
 *
 * Shape follows the shipped iOS one: the time lives in the header, the streak
 * and week dots are a scorecard row rather than a card, the verse sits on
 * paper, and a ✕ closes. **Nothing new goes above the verse** — the verse is
 * the reason the app exists, and every card added above it pushed it further
 * from the eye.
 */
@Composable
fun CompletionScreen(
    puzzle: Puzzle,
    result: CompletionOutcome.Result,
    completedThisWeek: Set<DayOfWeek>,
    onClose: () -> Unit,
    onChallenge: () -> Unit,
    onShare: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = BccTheme.colors

    Column(modifier.fillMaxSize().background(colors.background)) {
        // Header: the time, and the way out.
        Row(
            Modifier.fillMaxWidth().padding(horizontal = Spacing.m, vertical = Spacing.s),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onClose, modifier = Modifier.semantics { contentDescription = "Close" }) {
                Icon(Icons.Filled.Close, contentDescription = null, tint = colors.label)
            }
            Box(Modifier.weight(1f))
            Text(
                text = clockText(result.record.elapsedSeconds),
                style = scripture(20, FontWeight.SemiBold),
                color = colors.label,
            )
            Box(Modifier.weight(1f))
            Box(Modifier.size(48.dp))
        }

        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Spacing.m),
            verticalArrangement = Arrangement.spacedBy(Spacing.m),
        ) {
            Text(
                text = if (result.firstCompletion) "Solved" else "Solved again",
                style = scripture(32, FontWeight.SemiBold),
                color = colors.label,
            )

            // Scorecard: streak and the week, on one row rather than a card.
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Spacing.m),
            ) {
                Column {
                    Text(
                        "${result.profile.currentStreak}",
                        style = scripture(26, FontWeight.SemiBold),
                        color = colors.label,
                    )
                    Text("day streak", fontSize = 12.sp, color = colors.secondaryLabel)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.s)) {
                    for (day in StreakWeek.weekOrder) {
                        Box(
                            Modifier
                                .size(10.dp)
                                .background(
                                    if (day in completedThisWeek) colors.accent else colors.label.copy(alpha = 0.12f),
                                    CircleShape,
                                )
                        )
                    }
                }
            }

            // The verse, on paper.
            Column(
                Modifier.fillMaxWidth().elevatedCard(colors.surface).padding(Spacing.m),
                verticalArrangement = Arrangement.spacedBy(Spacing.s),
            ) {
                Kicker("The verse")
                Text(puzzle.verse, style = scripture(19), color = colors.label)
                Text(puzzle.reference, fontSize = 13.sp, color = colors.accent)
            }

            // Payoffs, below the verse, only when there is one.
            if (result.earnedFreeze) {
                Payoff("Streak freeze earned", "It will forgive one missed day.")
            }
            for (pack in result.completedPacks) {
                Payoff("Pack complete", pack.title)
            }
            for (quest in result.completedQuests) {
                Payoff("Journey complete", quest.title)
            }
            for (achievement in result.newAchievements) {
                Payoff(achievement.title, achievement.detail)
            }

            Box(Modifier.padding(bottom = Spacing.l))
        }

        // Pinned bar: the invite leads.
        Row(
            Modifier
                .fillMaxWidth()
                .background(colors.surface)
                .padding(horizontal = Spacing.m, vertical = Spacing.s),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.s),
        ) {
            Box(Modifier.weight(1f)) {
                PillButton(onClick = onChallenge) { Text("Challenge a friend") }
            }
            IconButton(onClick = onShare, modifier = Modifier.semantics { contentDescription = "Share" }) {
                Icon(Icons.Filled.Share, contentDescription = null, tint = colors.label)
            }
        }
    }
}

@Composable
private fun Payoff(title: String, detail: String) {
    val colors = BccTheme.colors
    Column(
        Modifier.fillMaxWidth().elevatedCard(colors.surface).padding(Spacing.m),
        verticalArrangement = Arrangement.spacedBy(Spacing.xs),
    ) {
        Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = colors.label)
        Text(detail, fontSize = 13.sp, color = colors.secondaryLabel)
    }
}
