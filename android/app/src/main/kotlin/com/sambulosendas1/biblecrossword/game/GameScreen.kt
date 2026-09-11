package com.sambulosendas1.biblecrossword.game

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.sambulosendas1.biblecrossword.domain.content.GridPos
import com.sambulosendas1.biblecrossword.domain.content.Puzzle
import com.sambulosendas1.biblecrossword.domain.engine.CheckScope
import com.sambulosendas1.biblecrossword.domain.engine.GameEngine
import com.sambulosendas1.biblecrossword.domain.engine.HintType
import com.sambulosendas1.biblecrossword.domain.profile.clockText
import com.sambulosendas1.biblecrossword.ui.game.ClueBar
import com.sambulosendas1.biblecrossword.ui.game.CrosswordGrid
import com.sambulosendas1.biblecrossword.ui.game.GameStateHolder
import com.sambulosendas1.biblecrossword.ui.game.LetterKeyboard
import com.sambulosendas1.biblecrossword.ui.game.SolveClock
import com.sambulosendas1.biblecrossword.ui.haptics.LocalHaptics
import com.sambulosendas1.biblecrossword.ui.theme.BccTheme
import com.sambulosendas1.biblecrossword.ui.theme.Spacing
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The solve screen: grid, clue bar, keyboard, and the feedback that makes a
 * solved word feel solved.
 *
 * Persistence, analytics, hint quota and the completion screen land in P4 —
 * this is the loop itself. Hint *costs* are already enforced by the engine's
 * refusals; the quota that gates them needs the profile.
 */
@Composable
fun GameScreen(
    puzzle: Puzzle,
    modifier: Modifier = Modifier,
    isLearning: Boolean = false,
    onClose: () -> Unit = {},
) {
    val holder = remember(puzzle.id) { GameStateHolder(GameEngine(puzzle, isLearning = isLearning)) }
    val engine = holder.engine
    val state = holder.state
    val colors = BccTheme.colors
    val haptics = LocalHaptics.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()

    var shakeTick by remember { mutableIntStateOf(0) }
    var showHints by remember { mutableStateOf(false) }
    var showChecks by remember { mutableStateOf(false) }
    var showComplete by remember { mutableStateOf(false) }
    var confirmReveal by remember { mutableStateOf(false) }

    // Wire the engine's callbacks to flash, shake, haptics and announcements.
    DisposableEffect(engine) {
        engine.onWordCompleted = { slot ->
            haptics.impactLight()
            view.announceForAccessibility("${slot.answer.lowercase().replaceFirstChar { it.uppercase() }} complete")
            // Pop the word's cells one after another along its length — a
            // rolling cascade rather than a block flash.
            slot.positions.forEachIndexed { i, pos ->
                scope.launch {
                    delay(i * 45L)
                    holder.flashing = holder.flashing + pos
                    delay(450)
                    holder.flashing = holder.flashing - pos
                }
            }
        }
        engine.onCheckResult = { correct, wrong ->
            if (wrong > 0) {
                haptics.error()
                shakeTick += 1
                view.announceForAccessibility(
                    if (wrong == 1) "1 letter incorrect" else "$wrong letters incorrect"
                )
            } else if (correct.isNotEmpty()) {
                view.announceForAccessibility("All checked letters correct")
            }
            // Brief pulse on what checked out — shown once, never stored, so
            // repeated checking can't paint a permanent answer key.
            if (correct.isNotEmpty()) {
                val positions = correct.toSet()
                scope.launch {
                    holder.flashing = holder.flashing + positions
                    delay(600)
                    holder.flashing = holder.flashing - positions
                }
            }
        }
        engine.onComplete = {
            haptics.success()
            showComplete = true
        }
        onDispose {
            engine.onWordCompleted = null
            engine.onCheckResult = null
            engine.onComplete = null
        }
    }

    // Typing into a locked cell skips the letter; a silent skip reads as a
    // broken keyboard, so pulse the cell and tap.
    var lastLockedTick by remember { mutableIntStateOf(0) }
    if (engine.lockedEntryTick != lastLockedTick) {
        lastLockedTick = engine.lockedEntryTick
        engine.lockedEntryPos?.let { pos ->
            haptics.warning()
            view.announceForAccessibility("Already revealed")
            scope.launch {
                holder.flashing = holder.flashing + pos
                delay(350)
                holder.flashing = holder.flashing - pos
            }
        }
    }

    SolveClock(engine = engine, onTick = { holder.refresh() })

    Column(modifier.fillMaxSize().background(colors.background)) {
        // Toolbar: title, clock, check and hint menus.
        Row(
            Modifier.fillMaxWidth().padding(horizontal = Spacing.m, vertical = Spacing.s),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.s),
        ) {
            TextButton(onClick = onClose) { Text("Close") }
            Text(
                text = clockText(state.elapsedSeconds),
                fontWeight = FontWeight.Medium,
                color = colors.secondaryLabel,
                modifier = Modifier.weight(1f).semantics { contentDescription = "Elapsed time" },
            )
            Box {
                IconButton(onClick = { showChecks = true }, modifier = Modifier.semantics { contentDescription = "Check" }) {
                    Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = colors.label)
                }
                DropdownMenu(expanded = showChecks, onDismissRequest = { showChecks = false }) {
                    for (scopeKind in CheckScope.entries) {
                        DropdownMenuItem(
                            text = { Text("Check ${scopeKind.rawValue}") },
                            onClick = { showChecks = false; holder.mutate { it.check(scopeKind) } },
                        )
                    }
                }
            }
            Box {
                IconButton(onClick = { showHints = true }, modifier = Modifier.semantics { contentDescription = "Hints" }) {
                    Icon(Icons.Filled.Lightbulb, contentDescription = null, tint = colors.label)
                }
                DropdownMenu(expanded = showHints, onDismissRequest = { showHints = false }) {
                    for (hint in listOf(HintType.VERSE, HintType.LETTER, HintType.WORD, HintType.PUZZLE)) {
                        DropdownMenuItem(
                            text = {
                                Text(if (hint.cost == 0) hint.title else "${hint.title}  ·  ${hint.cost}")
                            },
                            onClick = {
                                showHints = false
                                when (hint) {
                                    // The give-up fill is confirmed before use.
                                    HintType.PUZZLE -> confirmReveal = true
                                    HintType.LETTER -> holder.mutate { it.revealLetter() }
                                    HintType.WORD -> holder.mutate { it.revealWord() }
                                    HintType.VERSE -> holder.mutate { it.noteVerseHint() }
                                }
                            },
                        )
                    }
                }
            }
        }

        CrosswordGrid(
            state = state,
            flashing = holder.flashing,
            onTapCell = { pos: GridPos -> holder.mutate { it.tapCell(pos) } },
            shakeTick = shakeTick,
            modifier = Modifier.weight(1f).padding(Spacing.s),
        )

        ClueBar(
            state = state,
            onPrevious = { holder.mutate { it.advanceClue(-1) } },
            onNext = { holder.mutate { it.advanceClue(1) } },
            onToggleDirection = { holder.mutate { it.toggleDirection() } },
            onStallTap = { holder.mutate { runStallAction(it) } },
            onVerseTap = { holder.mutate { it.noteVerseHint() } },
        )

        LetterKeyboard(
            onLetter = { letter -> holder.mutate { it.enter(letter) } },
            onDelete = { holder.mutate { it.delete() } },
            isPencilMode = state.isPencilMode,
            onTogglePencil = { holder.mutate { it.isPencilMode = !it.isPencilMode } },
            modifier = Modifier.background(colors.surface),
        )
    }

    if (confirmReveal) {
        AlertDialog(
            onDismissRequest = { confirmReveal = false },
            title = { Text("Reveal the whole puzzle?") },
            text = { Text("This fills every square and ends the solve.") },
            confirmButton = {
                TextButton(onClick = { confirmReveal = false; holder.mutate { it.revealPuzzle() } }) { Text("Reveal") }
            },
            dismissButton = { TextButton(onClick = { confirmReveal = false }) { Text("Keep solving") } },
        )
    }

    if (showComplete) {
        AlertDialog(
            onDismissRequest = { showComplete = false },
            title = { Text("Solved") },
            text = { Text("${puzzle.title} in ${clockText(state.elapsedSeconds)}") },
            confirmButton = { TextButton(onClick = { showComplete = false; onClose() }) { Text("Done") } },
        )
    }
}

/**
 * What the rescue line does when tapped, chosen to match the copy it showed.
 * The free letter is free of quota by design — it exists to unstick a player
 * who was never going to ask.
 */
private fun runStallAction(engine: GameEngine) {
    when (engine.stallNudgeKind) {
        com.sambulosendas1.biblecrossword.domain.engine.StallNudgeKind.CHECK_ANSWERS -> engine.check(CheckScope.PUZZLE)
        com.sambulosendas1.biblecrossword.domain.engine.StallNudgeKind.READ_VERSE -> engine.noteVerseHint()
        com.sambulosendas1.biblecrossword.domain.engine.StallNudgeKind.FREE_LETTER -> engine.revealLetter()
    }
    engine.acknowledgeStallNudge()
}
