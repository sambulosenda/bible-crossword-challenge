package com.sambulosendas1.biblecrossword.today

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.sambulosendas1.biblecrossword.domain.content.Puzzle
import com.sambulosendas1.biblecrossword.domain.profile.clockText
import com.sambulosendas1.biblecrossword.domain.today.DailyPresentation
import com.sambulosendas1.biblecrossword.domain.today.PuzzleStatus
import com.sambulosendas1.biblecrossword.domain.today.StreakWeek
import com.sambulosendas1.biblecrossword.ui.theme.BccTheme
import com.sambulosendas1.biblecrossword.ui.theme.CardCornerRadius
import com.sambulosendas1.biblecrossword.ui.theme.Kicker
import com.sambulosendas1.biblecrossword.ui.theme.PillButton
import com.sambulosendas1.biblecrossword.ui.theme.PillEmphasis
import com.sambulosendas1.biblecrossword.ui.theme.Spacing
import com.sambulosendas1.biblecrossword.ui.theme.elevatedCard
import com.sambulosendas1.biblecrossword.ui.theme.scripture

/**
 * Today: the verse, then what there is to play.
 *
 * The verse stays at the top. That is positioning, not layout — if the screen
 * needs room, the greeting goes, never the verse.
 */
@Composable
fun TodayScreen(
    onPlay: (Puzzle) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: TodayViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val colors = BccTheme.colors
    LaunchedEffect(Unit) { viewModel.load() }

    if (state.loading) {
        Box(modifier.fillMaxSize().background(colors.background), Alignment.Center) {
            CircularProgressIndicator(color = colors.accent)
        }
        return
    }

    Column(
        modifier
            .fillMaxSize()
            .background(colors.background)
            .verticalScroll(rememberScrollState())
            .padding(Spacing.m),
        verticalArrangement = Arrangement.spacedBy(Spacing.m),
    ) {
        if (state.verse.isNotEmpty()) {
            Column(Modifier.padding(top = Spacing.l, bottom = Spacing.s)) {
                Kicker("Verse of the day")
                Text(
                    text = state.verse,
                    style = scripture(21),
                    color = colors.label,
                    modifier = Modifier.padding(top = Spacing.s),
                )
                Text(
                    text = state.verseReference,
                    fontSize = 13.sp,
                    color = colors.accent,
                    modifier = Modifier.padding(top = Spacing.s),
                )
            }
        }

        StreakCard(state)

        state.daily?.let { PuzzleCard("Today's puzzle", it, onPlay) }
        state.mini?.let { PuzzleCard("The Mini", it, onPlay) }
        state.sunday?.let { PuzzleCard("Sunday Special", it, onPlay) }

        Box(Modifier.padding(bottom = Spacing.xl))
    }
}

@Composable
private fun StreakCard(state: TodayViewModel.State) {
    val colors = BccTheme.colors
    Column(
        Modifier
            .fillMaxWidth()
            .elevatedCard(colors.surface)
            .padding(Spacing.m),
        verticalArrangement = Arrangement.spacedBy(Spacing.s),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = "${state.profile.currentStreak}",
                style = scripture(30, FontWeight.SemiBold),
                color = colors.label,
            )
            Text(
                text = if (state.profile.currentStreak == 1) " day streak" else " day streak",
                fontSize = 15.sp,
                color = colors.secondaryLabel,
            )
            Box(Modifier.weight(1f))
            if (state.profile.streakFreezes > 0) {
                Text(
                    text = "${state.profile.streakFreezes} freeze${if (state.profile.streakFreezes == 1) "" else "s"}",
                    fontSize = 12.sp,
                    color = colors.secondaryLabel,
                )
            }
        }

        // The week row: one dot per day, Sunday first.
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.s)) {
            for (day in StreakWeek.weekOrder) {
                val done = day in state.completedThisWeek
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(
                        Modifier
                            .size(10.dp)
                            .background(if (done) colors.accent else colors.label.copy(alpha = 0.12f), CircleShape)
                    )
                    Text(
                        text = day.name.take(1),
                        fontSize = 10.sp,
                        color = colors.secondaryLabel,
                        modifier = Modifier.padding(top = Spacing.xs),
                    )
                }
            }
        }

        if (state.freezeSavedToday) {
            Text("A freeze saved your streak.", fontSize = 12.sp, color = colors.secondaryLabel)
        }
        if (state.pendingStreakBreak > 0) {
            Text(
                text = "Your ${state.pendingStreakBreak}-day streak ended. Solve one to start again.",
                fontSize = 13.sp,
                color = colors.label,
            )
        }
    }
}

@Composable
private fun PuzzleCard(kicker: String, presentation: DailyPresentation, onPlay: (Puzzle) -> Unit) {
    val colors = BccTheme.colors
    val puzzle = presentation.puzzle
    Column(
        Modifier
            .fillMaxWidth()
            .elevatedCard(colors.surface)
            .clickable { onPlay(puzzle) }
            .padding(Spacing.m),
        verticalArrangement = Arrangement.spacedBy(Spacing.s),
    ) {
        Kicker(kicker)
        Text(puzzle.title, style = scripture(22, FontWeight.SemiBold), color = colors.label)
        Text(
            text = "${puzzle.size}×${puzzle.size} · ${puzzle.difficulty.label} · ${puzzle.clueCount} clues",
            fontSize = 13.sp,
            color = colors.secondaryLabel,
        )

        when (presentation.status) {
            PuzzleStatus.SOLVED_TODAY, PuzzleStatus.SOLVED_EARLIER -> {
                val time = presentation.solveSeconds?.let { " in ${clockText(it)}" } ?: ""
                Text("Solved$time", fontSize = 13.sp, color = colors.accent)
                PillButton(onClick = { onPlay(puzzle) }, emphasis = PillEmphasis.TONAL) { Text("Play again") }
            }
            PuzzleStatus.IN_PROGRESS -> {
                val percent = ((presentation.progress ?: 0f) * 100).toInt()
                Text("$percent% filled", fontSize = 13.sp, color = colors.secondaryLabel)
                PillButton(onClick = { onPlay(puzzle) }) { Text("Resume") }
            }
            PuzzleStatus.NOT_STARTED ->
                PillButton(onClick = { onPlay(puzzle) }) { Text("Play") }
        }
    }
}
