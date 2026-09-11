package com.sambulosendas1.biblecrossword.today

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sambulosendas1.biblecrossword.data.content.ContentRepository
import com.sambulosendas1.biblecrossword.data.prefs.AppPrefs
import com.sambulosendas1.biblecrossword.data.prefs.AppSignals
import com.sambulosendas1.biblecrossword.data.repo.ProgressRepository
import com.sambulosendas1.biblecrossword.domain.completion.LaunchNormalisation
import com.sambulosendas1.biblecrossword.domain.content.Puzzle
import com.sambulosendas1.biblecrossword.domain.profile.PlayerProfile
import com.sambulosendas1.biblecrossword.domain.today.DailyPresentation
import com.sambulosendas1.biblecrossword.domain.today.StreakWeek
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import javax.inject.Inject

@HiltViewModel
class TodayViewModel @Inject constructor(
    private val content: ContentRepository,
    private val progress: ProgressRepository,
    private val prefs: AppPrefs,
    private val signals: AppSignals,
) : ViewModel() {

    data class State(
        val loading: Boolean = true,
        val profile: PlayerProfile = PlayerProfile(),
        val daily: DailyPresentation? = null,
        val mini: DailyPresentation? = null,
        val sunday: DailyPresentation? = null,
        /** Today's verse — from the daily puzzle. It stays at the top of the screen. */
        val verse: String = "",
        val verseReference: String = "",
        val completedThisWeek: Set<DayOfWeek> = emptySet(),
        /** The streak length lost at launch, if the comeback card is owed. */
        val pendingStreakBreak: Int = 0,
        /** A freeze bridged a missed day since the last launch. */
        val freezeSavedToday: Boolean = false,
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    private var normalised = false

    fun load() {
        viewModelScope.launch {
            val catalogue = content.catalogue()
            val today = LocalDate.now()
            val now = Instant.now()
            var profile = progress.profile()
            val records = progress.observeRecordsSnapshot()

            var pending = prefs.awaitReady().pendingStreakBreak
            var freezeSaved = false

            // Once per process: settle the streak and reconcile pack/quest credit.
            if (!normalised) {
                normalised = true
                val result = LaunchNormalisation.run(
                    profile = profile,
                    solvedPuzzleIDs = records.values.filter { it.isCompleted }.map { it.puzzleID }.toSet(),
                    packs = catalogue.packs,
                    quests = catalogue.quests,
                    now = now,
                )
                profile = result.profile
                progress.saveProfile(profile)
                freezeSaved = result.outcome is com.sambulosendas1.biblecrossword.domain.profile.Streaks.Outcome.FreezeSaved
                // Persisted, not held in memory: normalize reports a break
                // exactly once, so a kill before the card is seen would lose it.
                if (result.pendingStreakBreak > 0) {
                    pending = result.pendingStreakBreak
                    prefs.setPendingStreakBreak(pending)
                }
            }

            fun present(p: Puzzle?) = p?.let { DailyPresentation.of(it, records[it.id], now) }
            val daily = catalogue.dailyPuzzle(today)

            _state.value = State(
                loading = false,
                profile = profile,
                daily = present(daily),
                mini = present(catalogue.dailyMini(today)),
                sunday = present(catalogue.sundaySpecial(today)),
                verse = daily?.verse.orEmpty(),
                verseReference = daily?.reference.orEmpty(),
                completedThisWeek = StreakWeek.completedWeekdays(
                    records.values.mapNotNull { it.completedAt }, now,
                ),
                pendingStreakBreak = pending,
                freezeSavedToday = freezeSaved,
            )
        }
    }

    /** Records which entry point started a solve, so the comeback can be attributed. */
    fun noteComebackStart() {
        signals.comebackSource.value = "comeback_card"
    }
}
