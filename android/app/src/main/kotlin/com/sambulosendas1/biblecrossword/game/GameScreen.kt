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
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.sambulosendas1.biblecrossword.domain.content.GridPos
import com.sambulosendas1.biblecrossword.domain.content.Puzzle
import com.sambulosendas1.biblecrossword.domain.engine.CheckScope
import com.sambulosendas1.biblecrossword.domain.engine.GameEngine
import com.sambulosendas1.biblecrossword.domain.engine.HintType
import com.sambulosendas1.biblecrossword.domain.engine.StallNudgeKind
import com.sambulosendas1.biblecrossword.domain.profile.PlayerProfile
import com.sambulosendas1.biblecrossword.domain.profile.clockText
import com.sambulosendas1.biblecrossword.ui.game.ClueBar
import com.sambulosendas1.biblecrossword.ui.game.ClueList
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
 * solved word feel solved. Progress is restored on open and written back as
 * you type.
 *
 * The completion screen, streaks and analytics land in P4.
 */
@Composable
fun GameScreen(
    puzzle: Puzzle,
    modifier: Modifier = Modifier,
    onClose: () -> Unit = {},
    viewModel: GameViewModel = hiltViewModel(),
) {
    val colors = BccTheme.colors
    DisposableEffect(puzzle.id) {
        viewModel.start(puzzle)
        onDispose { }
    }
    val load by viewModel.load.collectAsStateWithLifecycle()

    when (val current = load) {
        is GameViewModel.Load.Loading ->
            Box(modifier.fillMaxSize().background(colors.background), Alignment.Center) {
                Text("Loading…", color = colors.secondaryLabel)
            }
        is GameViewModel.Load.Ready ->
            SolveSurface(puzzle, current.holder, viewModel, modifier, onClose)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SolveSurface(
    puzzle: Puzzle,
    holder: GameStateHolder,
    viewModel: GameViewModel,
    modifier: Modifier,
    onClose: () -> Unit,
) {
    val engine = holder.engine
    val state = holder.state
    val colors = BccTheme.colors
    val haptics = LocalHaptics.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val hintsRemaining by viewModel.hintsRemaining.collectAsStateWithLifecycle()
    val hintWall by viewModel.hintWall.collectAsStateWithLifecycle()

    var shakeTick by remember { mutableIntStateOf(0) }
    var showHints by remember { mutableStateOf(false) }
    var showChecks by remember { mutableStateOf(false) }
    var showClues by remember { mutableStateOf(false) }
    var showComplete by remember { mutableStateOf(false) }
    var confirmReveal by remember { mutableStateOf(false) }

    /** Every mutation goes through here so nothing can change the grid without saving it. */
    fun <T> play(block: (GameEngine) -> T): T {
        val result = holder.mutate(block)
        viewModel.save(engine)
        return result
    }

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
                view.announceForAccessibility(if (wrong == 1) "1 letter incorrect" else "$wrong letters incorrect")
            } else if (correct.isNotEmpty()) {
                view.announceForAccessibility("All checked letters correct")
            }
            // Shown once, never stored, so repeated checking can't paint an answer key.
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
            viewModel.saveNow(engine)
        }
        onDispose {
            engine.onWordCompleted = null
            engine.onCheckResult = null
            engine.onComplete = null
            // Leaving may be the last chance to write; the debounce is not enough.
            viewModel.saveNow(engine)
        }
    }

    // Typing into a locked cell skips the letter. A silent skip reads as a
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

    // Backgrounding is the other way a solve ends. Progress is otherwise only
    // written when an input debounces, so a player who types and then thinks
    // for five minutes before the process is killed would lose those minutes.
    LifecycleEventEffect(Lifecycle.Event.ON_PAUSE) { viewModel.saveNow(engine) }

    SolveClock(engine = engine, onTick = { holder.refresh() })

    Column(modifier.fillMaxSize().background(colors.background)) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = Spacing.m, vertical = Spacing.s),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.s),
        ) {
            TextButton(onClick = { viewModel.saveNow(engine); onClose() }) { Text("Close") }
            Text(
                text = clockText(state.elapsedSeconds),
                fontWeight = FontWeight.Medium,
                color = colors.secondaryLabel,
                modifier = Modifier.weight(1f).semantics { contentDescription = "Elapsed time" },
            )
            IconButton(onClick = { showClues = true }, modifier = Modifier.semantics { contentDescription = "All clues" }) {
                Icon(Icons.AutoMirrored.Filled.List, contentDescription = null, tint = colors.label)
            }
            Box {
                IconButton(onClick = { showChecks = true }, modifier = Modifier.semantics { contentDescription = "Check" }) {
                    Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = colors.label)
                }
                DropdownMenu(expanded = showChecks, onDismissRequest = { showChecks = false }) {
                    for (scopeKind in CheckScope.entries) {
                        DropdownMenuItem(
                            text = { Text("Check ${scopeKind.rawValue}") },
                            onClick = { showChecks = false; play { it.check(scopeKind) } },
                        )
                    }
                }
            }
            Box {
                IconButton(onClick = { showHints = true }, modifier = Modifier.semantics { contentDescription = "Hints" }) {
                    Icon(Icons.Filled.Lightbulb, contentDescription = null, tint = colors.label)
                }
                DropdownMenu(expanded = showHints, onDismissRequest = { showHints = false }) {
                    if (hintsRemaining != PlayerProfile.UNLIMITED) {
                        DropdownMenuItem(
                            enabled = false,
                            text = { Text("$hintsRemaining left today", color = colors.secondaryLabel) },
                            onClick = {},
                        )
                    }
                    for (hint in listOf(HintType.VERSE, HintType.LETTER, HintType.WORD, HintType.PUZZLE)) {
                        DropdownMenuItem(
                            text = { Text(if (hint.cost == 0) hint.title else "${hint.title}  ·  ${hint.cost}") },
                            onClick = {
                                showHints = false
                                // The give-up fill is confirmed before it spends anything.
                                if (hint == HintType.PUZZLE) confirmReveal = true
                                else play { viewModel.useHint(hint, it) }
                            },
                        )
                    }
                }
            }
        }

        CrosswordGrid(
            state = state,
            flashing = holder.flashing,
            onTapCell = { pos: GridPos -> play { it.tapCell(pos) } },
            shakeTick = shakeTick,
            modifier = Modifier.weight(1f).padding(Spacing.s),
        )

        ClueBar(
            state = state,
            onPrevious = { play { it.advanceClue(-1) } },
            onNext = { play { it.advanceClue(1) } },
            onToggleDirection = { play { it.toggleDirection() } },
            onStallTap = {
                play { e ->
                    when (e.stallNudgeKind) {
                        StallNudgeKind.CHECK_ANSWERS -> e.check(CheckScope.PUZZLE)
                        StallNudgeKind.READ_VERSE -> e.noteVerseHint()
                        // Free of quota by design: it exists to unstick a player
                        // who was never going to ask.
                        StallNudgeKind.FREE_LETTER -> viewModel.freeLetter(e)
                    }
                    e.acknowledgeStallNudge()
                }
            },
            onVerseTap = { play { viewModel.useHint(HintType.VERSE, it) } },
        )

        LetterKeyboard(
            onLetter = { letter -> play { it.enter(letter) } },
            onDelete = { play { it.delete() } },
            isPencilMode = state.isPencilMode,
            onTogglePencil = { play { it.isPencilMode = !it.isPencilMode } },
            modifier = Modifier.background(colors.surface),
        )
    }

    if (showClues) {
        ModalBottomSheet(onDismissRequest = { showClues = false }, sheetState = rememberModalBottomSheetState()) {
            ClueList(
                across = engine.acrossSlots,
                down = engine.downSlots,
                activeSlotId = state.activeClue?.id,
                isSolved = { slot -> slot.positions.all { engine.cell(it).isCorrect } },
                onSelect = { slot -> showClues = false; play { it.select(slot) } },
            )
        }
    }

    hintWall?.let { type ->
        AlertDialog(
            onDismissRequest = { viewModel.dismissHintWall() },
            title = { Text("Out of hints for today") },
            text = { Text("${type.title} costs ${type.cost}. Your hints reset tomorrow.") },
            confirmButton = { TextButton(onClick = { viewModel.dismissHintWall() }) { Text("OK") } },
        )
    }

    if (confirmReveal) {
        AlertDialog(
            onDismissRequest = { confirmReveal = false },
            title = { Text("Reveal the whole puzzle?") },
            text = { Text("This fills every square and ends the solve.") },
            confirmButton = {
                TextButton(onClick = { confirmReveal = false; play { viewModel.useHint(HintType.PUZZLE, it) } }) { Text("Reveal") }
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
