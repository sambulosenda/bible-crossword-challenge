package com.sambulosendas1.biblecrossword.domain.content

import kotlinx.serialization.Serializable

/**
 * One Journey quest line, decoded from the shared `quests.json`. A quest is
 * packaging, not content: an *ordered* run of puzzles that already ship in
 * `puzzles.json`. Authored order in the file is display order; the first
 * quest is the free one. Mirrors iOS `Models/QuestLine.swift`.
 */
@Serializable
data class QuestLine(
    val id: String,
    val title: String,
    val blurb: String,
    val coverSymbol: String,
    val accentHex: String? = null,
    val isPremium: Boolean,
    /** Ordered — step N is `puzzleIDs[N]`. The single source of membership. */
    val puzzleIDs: List<String>,
)
