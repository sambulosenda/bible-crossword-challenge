package com.sambulosendas1.biblecrossword.domain.progress

import java.time.Instant

/**
 * Per-puzzle progress, as a plain value. Mirrors iOS `PuzzleRecord` in
 * `Models/Persistence.swift`; `:core:data` maps this to and from the Room
 * entity.
 */
data class PuzzleRecord(
    val puzzleID: String,
    val isCompleted: Boolean = false,
    val completedAt: Instant? = null,
    val elapsedSeconds: Int = 0,
    /** Pen letters: `"row,col"` → letter, lowercase = hint-locked. */
    val entries: Map<String, String> = emptyMap(),
    /** Pencil letters, kept apart — pencil is not progress. */
    val pencil: Map<String, String> = emptyMap(),
    /** True once any hint was revealed — survives resume, so a "no hints" solve stays accurate. */
    val usedHint: Boolean = false,
    val updatedAt: Instant = Instant.EPOCH,
) {
    /** The player typed or pencilled something themselves; revealed cells don't count. */
    val hasPlayerEntries: Boolean get() = EntriesCodec.hasPlayerEntries(entries, pencil)
}
