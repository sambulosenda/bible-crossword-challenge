package com.sambulosendas1.biblecrossword.domain.content

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * When a pack is in season. A feast is a *rule*, not an event, so the
 * recurring cases store the rule and resolve a concrete window for whichever
 * year is being asked about. Mirrors iOS `PackSeason` in `Models/PuzzlePack.swift`.
 *
 * JSON shape: `{"kind": "annual", "from": "12-01", "to": "12-26"}` — the
 * `kind` discriminator is configured on [ContentJson], so a typo in an authored
 * pack fails loudly at decode instead of quietly never opening.
 *
 * Window arithmetic (Easter Sunday, wrap-around annual windows, `nextStart`)
 * is ported with the Packs feature and its `PacksTests`.
 */
@Serializable
sealed class PackSeason {
    /** A genuinely one-off window — ISO "yyyy-MM-dd", inclusive both ends. Expires for good. */
    @Serializable
    @SerialName("dates")
    data class Dates(val from: String, val to: String) : PackSeason()

    /** The same calendar days every year — "MM-dd", inclusive; may wrap the new year. */
    @Serializable
    @SerialName("annual")
    data class Annual(val from: String, val to: String) : PackSeason()

    /** Days relative to Easter Sunday. Lent is -46…-1, Holy Week -7…0, Eastertide 0…7. */
    @Serializable
    @SerialName("easter")
    data class Easter(val from: Int, val to: Int) : PackSeason()
}

/**
 * A curated collection, decoded from the shared `packs.json`. Mirrors iOS
 * `PuzzlePack`. Membership is `puzzleIDs`, in authored order.
 */
@Serializable
data class PuzzlePack(
    /** Stable slug, e.g. "life-of-david". Used for analytics and reverse lookup. */
    val id: String,
    val title: String,
    val blurb: String,
    /** SF Symbol name on iOS; mapped to a drawable on Android (requirements §4.5). */
    val coverSymbol: String,
    /** Optional per-pack tint, "#RRGGBB"; null falls back to the accent. */
    val accentHex: String? = null,
    /** Free "taster" packs are false; everything else unlocks with Premium. */
    val isPremium: Boolean,
    val puzzleIDs: List<String>,
    /** Null for an evergreen collection, which is always available. */
    val season: PackSeason? = null,
    /**
     * The day this collection first shipped, ISO "yyyy-MM-dd". Drives the
     * "New" badge for a fortnight and nothing else. Null = never new.
     */
    val addedOn: String? = null,
) {
    val isSeasonal: Boolean get() = season != null

    companion object {
        /** How long the "New" badge shows after [addedOn]. */
        const val NEW_DAYS = 14
    }
}
