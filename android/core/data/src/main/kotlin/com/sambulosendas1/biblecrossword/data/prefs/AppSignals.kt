package com.sambulosendas1.biblecrossword.data.prefs

import kotlinx.coroutines.flow.MutableStateFlow

/**
 * One-shot cross-screen signals that iOS routed through `@AppStorage` because
 * there was no call chain between the writer and the reader. Process-scoped
 * and **in-memory on purpose**: persisting `comebackSource` is what let a stale
 * value survive a kill on iOS and mislabel a later solve.
 *
 * (`pendingStreakBreak` is the opposite case and lives in [Prefs].)
 */
class AppSignals {
    /**
     * Set by Home when the comeback card starts a puzzle; read once by the
     * completion path to label the solve, then cleared.
     */
    val comebackSource = MutableStateFlow<String?>(null)

    fun consumeComebackSource(): String? {
        val value = comebackSource.value
        comebackSource.value = null
        return value
    }
}
