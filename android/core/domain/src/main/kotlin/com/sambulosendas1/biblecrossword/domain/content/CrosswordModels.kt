package com.sambulosendas1.biblecrossword.domain.content

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/*
 * Value types describing a puzzle, decoded from the shared `puzzles.json`.
 * Mirrors iOS `Models/CrosswordModels.swift` field for field — the JSON is the
 * same physical file on both platforms, so the shapes must not diverge.
 */

@Serializable
enum class PuzzleDifficulty {
    @SerialName("easy") EASY,
    @SerialName("medium") MEDIUM,
    @SerialName("hard") HARD;

    val rawValue: String get() = name.lowercase()
    val label: String get() = rawValue.replaceFirstChar { it.uppercase() }
}

@Serializable
enum class ClueDirection {
    @SerialName("across") ACROSS,
    @SerialName("down") DOWN;

    val rawValue: String get() = name.lowercase()
    val label: String get() = if (this == ACROSS) "Across" else "Down"
    val toggled: ClueDirection get() = if (this == ACROSS) DOWN else ACROSS
}

/**
 * Full-size daily vs the quick 7×7 Mini vs the weekly 21×21 Sunday Special.
 * Absent in older JSON, so it decodes as nullable and reads as daily.
 */
@Serializable
enum class PuzzleKind {
    @SerialName("daily") DAILY,
    @SerialName("mini") MINI,
    @SerialName("sunday") SUNDAY;

    val rawValue: String get() = name.lowercase()
}

@Serializable
data class GridPos(val row: Int, val col: Int) {
    /** The persisted key for this cell — `"row,col"`, identical to iOS. */
    val storageKey: String get() = "$row,$col"

    companion object {
        /** Inverse of [storageKey]; null for anything malformed. */
        fun fromStorageKey(key: String): GridPos? {
            val parts = key.split(",")
            if (parts.size != 2) return null
            val r = parts[0].toIntOrNull() ?: return null
            val c = parts[1].toIntOrNull() ?: return null
            return GridPos(r, c)
        }
    }
}

@Serializable
data class ClueData(
    val number: Int,
    val direction: ClueDirection,
    val row: Int,
    val col: Int,
    val text: String,
    val answer: String,
    /**
     * Where this clue's answer comes from, e.g. "1 Samuel 9:1". Optional
     * because references land pack by pack. Shown only after the clue is
     * solved, never as a hint.
     */
    val reference: String? = null,
) {
    val start: GridPos get() = GridPos(row, col)

    /** Ordered cell positions this clue's answer occupies. */
    val positions: List<GridPos>
        get() = (0 until answer.length).map { i ->
            when (direction) {
                ClueDirection.ACROSS -> GridPos(row, col + i)
                ClueDirection.DOWN -> GridPos(row + i, col)
            }
        }
}

@Serializable
data class Puzzle(
    val id: String,
    val title: String,
    val difficulty: PuzzleDifficulty,
    val verse: String,
    val reference: String,
    val publishDate: String,
    val size: Int,
    /** `size` rows of `size` characters; `.` is a block. */
    val grid: List<String>,
    val clues: List<ClueData>,
    val kind: PuzzleKind? = null,
) {
    val clueCount: Int get() = clues.size
    val isMini: Boolean get() = kind == PuzzleKind.MINI
    val isSunday: Boolean get() = kind == PuzzleKind.SUNDAY

    /** Pack exclusives never enter a rotation — matches `PuzzleAccess`/`PuzzleProvider`. */
    val isPackExclusive: Boolean get() = id.startsWith(PACK_PREFIX)

    companion object {
        const val PACK_PREFIX = "pack-"
    }
}
