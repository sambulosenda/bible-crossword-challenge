package com.sambulosendas1.biblecrossword.game

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sambulosendas1.biblecrossword.data.content.ContentRepository
import com.sambulosendas1.biblecrossword.data.prefs.AppPrefs
import com.sambulosendas1.biblecrossword.data.prefs.AppSignals
import com.sambulosendas1.biblecrossword.data.repo.ProgressRepository
import com.sambulosendas1.biblecrossword.domain.completion.CompletionOutcome
import com.sambulosendas1.biblecrossword.domain.content.Puzzle
import com.sambulosendas1.biblecrossword.domain.engine.GameEngine
import com.sambulosendas1.biblecrossword.domain.engine.HintType
import com.sambulosendas1.biblecrossword.domain.profile.PlayerProfile
import com.sambulosendas1.biblecrossword.domain.progress.PuzzleRecord
import com.sambulosendas1.biblecrossword.ui.game.GameStateHolder
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import javax.inject.Inject

/**
 * Owns one solve: loads the saved record, seeds the engine from it, spends the
 * hint quota, and writes progress back.
 *
 * The engine itself is the ported [GameEngine] — nothing here re-implements a
 * rule. What lives here is the *orchestration* that on iOS sits inside
 * `CrosswordGameView`: which order things happen in, and what is persisted.
 */
@HiltViewModel
class GameViewModel @Inject constructor(
    private val progress: ProgressRepository,
    private val appPrefs: AppPrefs,
    private val content: ContentRepository,
    private val signals: AppSignals,
) : ViewModel() {

    sealed interface Load {
        data object Loading : Load
        data class Ready(val holder: GameStateHolder) : Load
    }

    private val _load = MutableStateFlow<Load>(Load.Loading)
    val load: StateFlow<Load> = _load.asStateFlow()

    /** Hints left today, as the wall sees it. -1 is unlimited. */
    private val _hintsRemaining = MutableStateFlow(PlayerProfile.UNLIMITED)
    val hintsRemaining: StateFlow<Int> = _hintsRemaining.asStateFlow()

    /** Set when a hint was refused for want of quota — the screen shows the wall. */
    private val _hintWall = MutableStateFlow<HintType?>(null)
    val hintWall: StateFlow<HintType?> = _hintWall.asStateFlow()

    /** The resolved completion, once the puzzle is solved — drives the payoff screen. */
    private val _completion = MutableStateFlow<CompletionOutcome.Result?>(null)
    val completion: StateFlow<CompletionOutcome.Result?> = _completion.asStateFlow()

    /** Durable preferences, for the comeback debt the completion has to clear. */
    val prefs: StateFlow<com.sambulosendas1.biblecrossword.data.prefs.Prefs> get() = appPrefs.state

    /**
     * Weekdays carrying a completion, for the scorecard row. Recomputed after
     * the solve is written — read at load time it would omit today's, which is
     * the one dot the player just earned and is looking for.
     */
    private val _completedThisWeek = MutableStateFlow<Set<java.time.DayOfWeek>>(emptySet())
    val completedThisWeek: StateFlow<Set<java.time.DayOfWeek>> = _completedThisWeek.asStateFlow()

    private var profile: PlayerProfile = PlayerProfile()
    private var record: PuzzleRecord? = null
    private var puzzleID: String? = null
    private var saveJob: Job? = null

    /**
     * The daily pool this player is being measured against. Constant until the
     * `hint-quota-one` flag is wired in P5 — the engine never reads a flag, the
     * limit is always handed to it.
     */
    private val hintLimit = PlayerProfile.FREE_HINT_LIMIT

    fun start(puzzle: Puzzle) {
        if (puzzleID == puzzle.id) return
        puzzleID = puzzle.id
        viewModelScope.launch {
            profile = progress.profile()
            record = progress.record(puzzle.id)

            // The auto-check default is seeded once, on first consult: ON for a
            // player inside the learning window, OFF for anyone who learned the
            // grid without it. Flipping a veteran's game under them is worse
            // than making a beginner find a toggle.
            val seeded = appPrefs.awaitReady().autoCheckErrors
                ?: GameEngine.seedAutoCheck(profile.totalPuzzlesCompleted).also { appPrefs.setAutoCheckErrors(it) }

            val engine = GameEngine(puzzle, isLearning = profile.isStillLearning)
            engine.autoCheck = seeded
            record?.let { saved ->
                // Order matters: seed the clock before restoring, so a resumed
                // puzzle carrying an hour of recorded time can't trip the stall
                // nudge on its first tick.
                engine.seedElapsed(saved.elapsedSeconds)
                engine.restore(saved.entries, saved.pencil)
            }
            refreshWeek()
            refreshQuota()
            _load.value = Load.Ready(GameStateHolder(engine))
        }
    }

    /**
     * Spend a hint, if the pool allows it.
     *
     * `usedHint` is set *before* the reveal and rolled back if the reveal
     * refuses, because a reveal can complete the puzzle synchronously — by the
     * time it returns, the completion has already read the flag.
     */
    fun useHint(type: HintType, engine: GameEngine): Boolean {
        if (!canAfford(type)) {
            _hintWall.value = type
            return false
        }
        val wasUsed = record?.usedHint ?: false
        markHintUsed(true)
        val revealed = when (type) {
            HintType.LETTER -> engine.revealLetter()
            HintType.WORD -> engine.revealWord()
            HintType.PUZZLE -> engine.revealPuzzle()
            HintType.VERSE -> { engine.noteVerseHint(); true }
        }
        if (!revealed) {
            markHintUsed(wasUsed)
            return false
        }
        if (type.cost > 0) {
            profile = profile.consumeHint(type.cost, Instant.now(), ZoneId.systemDefault())
            viewModelScope.launch { progress.saveProfile(profile) }
            refreshQuota()
        }
        return true
    }

    /**
     * The stall rescue's free letter. Deliberately outside the quota — it
     * exists to unstick a player who was never going to ask — but it still
     * marks the puzzle as hinted, so a "no hints" solve stays honest.
     */
    fun freeLetter(engine: GameEngine) {
        if (engine.revealLetter()) markHintUsed(true)
    }

    fun canAfford(type: HintType): Boolean {
        val remaining = _hintsRemaining.value
        return remaining == PlayerProfile.UNLIMITED || remaining >= type.cost
    }

    fun dismissHintWall() { _hintWall.value = null }

    /**
     * The solve landed. Resolves the whole outcome — streak, stats, pack and
     * quest credit, achievements — in one pure step, then persists it.
     *
     * Analytics and the leaderboard post are deliberately read off the result
     * rather than computed here, so the ordering lives in one tested place.
     */
    fun complete(engine: GameEngine, puzzle: Puzzle, pendingStreakBreak: Int) {
        if (_completion.value != null) return
        viewModelScope.launch {
            val catalogue = content.catalogue()
            val result = CompletionOutcome.resolve(
                CompletionOutcome.Context(
                    puzzle = puzzle,
                    seconds = engine.elapsed(),
                    profile = profile,
                    record = record,
                    solvedPuzzleIDs = progress.completedPuzzleIDs(),
                    packs = catalogue.packs,
                    quests = catalogue.quests,
                    pendingStreakBreak = pendingStreakBreak,
                    comebackSource = signals.consumeComebackSource().orEmpty(),
                    now = Instant.now(),
                )
            )
            profile = result.profile
            record = result.record.copy(entries = engine.snapshot(), pencil = emptyMap())
            progress.saveProfile(profile)
            progress.saveRecord(record!!)
            if (result.isComeback) appPrefs.setPendingStreakBreak(0)
            refreshWeek()
            _completion.value = result
        }
    }

    /** Debounced: typing fires this on every keystroke. */
    fun save(engine: GameEngine) {
        val id = puzzleID ?: return
        saveJob?.cancel()
        saveJob = viewModelScope.launch {
            delay(SAVE_DEBOUNCE_MS)
            writeRecord(engine, id)
        }
    }

    /** Immediate write, for leaving the screen — there may be no later chance. */
    fun saveNow(engine: GameEngine) {
        val id = puzzleID ?: return
        saveJob?.cancel()
        viewModelScope.launch { writeRecord(engine, id) }
    }

    private suspend fun writeRecord(engine: GameEngine, id: String) {
        val current = record ?: PuzzleRecord(puzzleID = id)
        val updated = current.copy(
            elapsedSeconds = engine.elapsed(),
            entries = engine.snapshot(),
            pencil = engine.pencilSnapshot(),
            isCompleted = current.isCompleted || engine.isComplete,
            completedAt = current.completedAt ?: if (engine.isComplete) Instant.now() else null,
        )
        record = updated
        progress.saveRecord(updated)
    }

    private fun markHintUsed(used: Boolean) {
        val id = puzzleID ?: return
        record = (record ?: PuzzleRecord(puzzleID = id)).copy(usedHint = used)
    }

    private suspend fun refreshWeek() {
        _completedThisWeek.value = com.sambulosendas1.biblecrossword.domain.today.StreakWeek.completedWeekdays(
            progress.observeRecordsSnapshot().values.mapNotNull { it.completedAt }, Instant.now(),
        )
    }

    private fun refreshQuota() {
        _hintsRemaining.value = profile.hintsRemaining(
            isPremium = false, // Entitlements land in P6; free is the honest default until then.
            limit = hintLimit,
            now = Instant.now(),
            zone = ZoneId.systemDefault(),
        )
    }

    private companion object {
        const val SAVE_DEBOUNCE_MS = 600L
    }
}
