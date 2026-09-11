package com.sambulosendas1.biblecrossword.domain.completion

import com.sambulosendas1.biblecrossword.domain.content.PuzzlePack
import com.sambulosendas1.biblecrossword.domain.content.QuestLine
import com.sambulosendas1.biblecrossword.domain.profile.PlayerProfile
import com.sambulosendas1.biblecrossword.domain.profile.Streaks
import java.time.Instant
import java.time.ZoneId

/**
 * What has to happen once per launch, before anything is shown — the rule half
 * of iOS `RootView`'s bootstrap.
 *
 * Two jobs. First, settle the streak: a day may have been missed since the app
 * was last opened, and a freeze may be owed to bridge it. Second, reconcile
 * pack and quest credit, which catches collections finished before the feature
 * existed, or finished on another device.
 */
object LaunchNormalisation {

    data class Result(
        val profile: PlayerProfile,
        val outcome: Streaks.Outcome,
        /**
         * The streak length to owe the comeback card, or 0. Reported **only**
         * on the pass that actually breaks the streak — a second pass the same
         * day finds it already at zero and reports nothing, which is what stops
         * the card re-firing on every launch.
         */
        val pendingStreakBreak: Int,
        val reconciledPacks: List<PuzzlePack>,
        val reconciledQuests: List<QuestLine>,
    )

    fun run(
        profile: PlayerProfile,
        solvedPuzzleIDs: Set<String>,
        packs: List<PuzzlePack>,
        quests: List<QuestLine>,
        now: Instant,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Result {
        val normalized = Streaks.normalize(profile, now, zone)
        var updated = normalized.profile

        val isSolved: (String) -> Boolean = { it in solvedPuzzleIDs }

        val reconciledPacks = packs.filter { pack ->
            pack.id !in updated.completedPackIDs && pack.puzzleIDs.isNotEmpty() && pack.puzzleIDs.all(isSolved)
        }
        if (reconciledPacks.isNotEmpty()) {
            updated = updated.copy(completedPackIDs = updated.completedPackIDs + reconciledPacks.map { it.id })
        }

        val reconciledQuests = quests.filter { quest ->
            quest.id !in updated.completedQuestIDs && quest.puzzleIDs.isNotEmpty() && quest.puzzleIDs.all(isSolved)
        }
        if (reconciledQuests.isNotEmpty()) {
            updated = updated.copy(completedQuestIDs = updated.completedQuestIDs + reconciledQuests.map { it.id })
        }

        return Result(
            profile = updated,
            outcome = normalized.outcome,
            pendingStreakBreak = (normalized.outcome as? Streaks.Outcome.Broken)?.previous ?: 0,
            reconciledPacks = reconciledPacks,
            reconciledQuests = reconciledQuests,
        )
    }
}
