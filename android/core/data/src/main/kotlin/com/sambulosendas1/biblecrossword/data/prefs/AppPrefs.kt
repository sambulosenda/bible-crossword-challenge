package com.sambulosendas1.biblecrossword.data.prefs

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.sambulosendas1.biblecrossword.domain.prefs.AppTheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

/** Stable from day one — Auto Backup keys on the file name (plan §5). */
private const val PREFS_NAME = "bible_crossword_prefs"

val Context.appPrefsDataStore: DataStore<Preferences> by preferencesDataStore(name = PREFS_NAME)

/**
 * Every durable preference, as one immutable value. Keys mirror the iOS
 * `@AppStorage` names so the two apps stay readable side by side.
 *
 * Grows with the features that read it; this is the P1 set. Timestamps are
 * epoch millis with 0 = never (iOS uses `timeIntervalSinceReferenceDate`).
 */
data class Prefs(
    val appTheme: AppTheme = AppTheme.SYSTEM,
    val hasOnboarded: Boolean = false,
    /**
     * Null until first consulted, then seeded ON for a player under three
     * completions and OFF for anyone else — see iOS
     * `GameViewModel.seedAutoCheckIfNeeded`. Never seeded here.
     */
    val autoCheckErrors: Boolean? = null,
    val showSolveTimer: Boolean = true,
    val remindersEnabled: Boolean = false,
    /** Minutes after midnight. 19:00 by default. */
    val reminderMinutes: Int = DEFAULT_REMINDER_MINUTES,
    val readFontSize: Float = 19f,
    val readLastBook: String = "",
    val readLastChapter: Int = 0,
    val reviewPromptMilestone: Int = 0,
    val streakReviewPromptShown: Boolean = false,
    val reviewPromptVersion: String = "",
    val reviewPromptLastAskAt: Long = 0,
    val challengeFreezeLastDay: Long = 0,
    val completionReminderAsksShown: Int = 0,
    val streakReminderAskShown: Boolean = false,
    val reminderAskLastDay: Long = 0,
    val didAskReminderAgain: Boolean = false,
    val pendingReminderOptIn: Boolean = false,
    /**
     * The streak length lost at the last launch-time break, for the comeback
     * card. **Persisted**, not in-memory: `Streaks.normalize` reports a break
     * exactly once, so a kill before the card is seen must not lose it.
     */
    val pendingStreakBreak: Int = 0,
    /**
     * False only on the pre-hydration sentinel. A field rather than an identity
     * check because `StateFlow` conflates by `==`: on a fresh install the
     * decoded prefs are all defaults, structurally equal to `Prefs()`, and an
     * identity sentinel was silently dropped — the splash never lifted.
     */
    val isLoaded: Boolean = true,
) {
    companion object {
        const val DEFAULT_REMINDER_MINUTES = 19 * 60

        val UNINITIALISED = Prefs(isLoaded = false)
    }
}

/**
 * One repository over one DataStore, exposing [Prefs] as a hot [StateFlow].
 *
 * The flow starts eagerly at process start; the splash screen holds until
 * [isReady] so every downstream reader gets a real synchronous `.value`.
 * There is deliberately no `runBlocking` read anywhere — it ANRs on a cold
 * start on a slow device (plan §6a).
 */
class AppPrefs(
    private val store: DataStore<Preferences>,
    scope: CoroutineScope,
) {
    val state: StateFlow<Prefs> = store.data
        .map(::toPrefs)
        // A corrupt prefs file must degrade to defaults, never crash the app.
        .catch { emit(Prefs()) }
        .stateIn(scope, SharingStarted.Eagerly, Prefs.UNINITIALISED)

    val isReady: Boolean get() = state.value.isLoaded

    suspend fun awaitReady(): Prefs = state.first { it.isLoaded }

    /** Low-level edit; prefer the typed setters. */
    suspend fun edit(block: (MutablePreferences) -> Unit) {
        store.edit(block)
    }

    suspend fun setAppTheme(theme: AppTheme) = edit { it[Keys.appTheme] = theme.rawValue }
    suspend fun setHasOnboarded(value: Boolean) = edit { it[Keys.hasOnboarded] = value }
    suspend fun setAutoCheckErrors(value: Boolean) = edit { it[Keys.autoCheckErrors] = value }
    suspend fun setShowSolveTimer(value: Boolean) = edit { it[Keys.showSolveTimer] = value }
    suspend fun setReminders(enabled: Boolean, minutes: Int) = edit {
        it[Keys.remindersEnabled] = enabled
        it[Keys.reminderMinutes] = minutes
    }
    suspend fun setPendingStreakBreak(previous: Int) = edit { it[Keys.pendingStreakBreak] = previous }

    object Keys {
        val appTheme = stringPreferencesKey("appTheme")
        val hasOnboarded = booleanPreferencesKey("hasOnboarded")
        val autoCheckErrors = booleanPreferencesKey("autoCheckErrors")
        val showSolveTimer = booleanPreferencesKey("showSolveTimer")
        val remindersEnabled = booleanPreferencesKey("remindersEnabled")
        val reminderMinutes = intPreferencesKey("reminderMinutes")
        val readFontSize = floatPreferencesKey("read.fontSize")
        val readLastBook = stringPreferencesKey("read.lastBook")
        val readLastChapter = intPreferencesKey("read.lastChapter")
        val reviewPromptMilestone = intPreferencesKey("reviewPromptMilestone")
        val streakReviewPromptShown = booleanPreferencesKey("streakReviewPromptShown")
        val reviewPromptVersion = stringPreferencesKey("reviewPromptVersion")
        val reviewPromptLastAskAt = longPreferencesKey("reviewPromptLastAsk")
        val challengeFreezeLastDay = longPreferencesKey("challengeFreezeLastDay")
        val completionReminderAsksShown = intPreferencesKey("completionReminderAsksShown")
        val streakReminderAskShown = booleanPreferencesKey("streakReminderAskShown")
        val reminderAskLastDay = longPreferencesKey("reminderAskLastDay")
        val didAskReminderAgain = booleanPreferencesKey("didAskReminderAgain")
        val pendingReminderOptIn = booleanPreferencesKey("pendingReminderOptIn")
        val pendingStreakBreak = intPreferencesKey("pendingStreakBreak")
    }

    private fun toPrefs(p: Preferences): Prefs = Prefs(
        appTheme = AppTheme.fromRaw(p[Keys.appTheme]),
        hasOnboarded = p[Keys.hasOnboarded] ?: false,
        autoCheckErrors = p[Keys.autoCheckErrors],
        showSolveTimer = p[Keys.showSolveTimer] ?: true,
        remindersEnabled = p[Keys.remindersEnabled] ?: false,
        reminderMinutes = p[Keys.reminderMinutes] ?: Prefs.DEFAULT_REMINDER_MINUTES,
        readFontSize = p[Keys.readFontSize] ?: 19f,
        readLastBook = p[Keys.readLastBook] ?: "",
        readLastChapter = p[Keys.readLastChapter] ?: 0,
        reviewPromptMilestone = p[Keys.reviewPromptMilestone] ?: 0,
        streakReviewPromptShown = p[Keys.streakReviewPromptShown] ?: false,
        reviewPromptVersion = p[Keys.reviewPromptVersion] ?: "",
        reviewPromptLastAskAt = p[Keys.reviewPromptLastAskAt] ?: 0,
        challengeFreezeLastDay = p[Keys.challengeFreezeLastDay] ?: 0,
        completionReminderAsksShown = p[Keys.completionReminderAsksShown] ?: 0,
        streakReminderAskShown = p[Keys.streakReminderAskShown] ?: false,
        reminderAskLastDay = p[Keys.reminderAskLastDay] ?: 0,
        didAskReminderAgain = p[Keys.didAskReminderAgain] ?: false,
        pendingReminderOptIn = p[Keys.pendingReminderOptIn] ?: false,
        pendingStreakBreak = p[Keys.pendingStreakBreak] ?: 0,
    )
}
