package com.sambulosendas1.biblecrossword.domain.progress

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * The persisted shape of a puzzle's letters — the one encoding that must stay
 * identical across platforms forever, because it is what a future
 * cross-platform sync would carry and what `spec/vectors/engine_traces.json`
 * emits as `entries` / `pencil`.
 *
 * Shape: a flat JSON object of `"row,col"` → single letter.
 * **A lowercase letter marks a hint-revealed (locked) cell**; the player's
 * own letters are uppercase. Pencil marks are a separate map of the same
 * shape (always uppercase), never mixed into entries — pencil is not progress.
 *
 * A revealed cell the player never asked for — the new-player starter gift —
 * carries [GIFT_MARKER] after the lowercase letter. It rides inside this map
 * rather than in its own record column because a new column means a CloudKit
 * schema deploy on the iOS side, and a missing one is what broke fleet sync
 * on 2026-08-29. Readers that only care about the lock are unaffected: the
 * marker is not a letter, so `first()` still yields the lock and `uppercase()`
 * still yields the entry.
 *
 * Mirrors iOS `PuzzleRecord.entries` / `.pencil` / `.hasPlayerEntries` in
 * `Models/Persistence.swift`. Keys are emitted sorted so the stored bytes are
 * deterministic on this platform (iOS's are dictionary-ordered; the contract
 * is the map, not the byte order).
 */
object EntriesCodec {
    /**
     * Suffix on a gifted cell's stored letter. Deliberately not a letter:
     * the entry is read back as `value.uppercase().first()`, so anything
     * alphabetic here would be mistaken for the letter itself.
     * Mirrors iOS `GameViewModel.giftMarker`.
     */
    const val GIFT_MARKER = "~"

    private val json = Json { ignoreUnknownKeys = true }

    fun encode(entries: Map<String, String>): String? {
        if (entries.isEmpty()) return null
        val obj = JsonObject(entries.toSortedMap().mapValues { JsonPrimitive(it.value) })
        return json.encodeToString(JsonObject.serializer(), obj)
    }

    /** Tolerant: anything that is not a flat string→string object decodes as empty. */
    fun decode(encoded: String?): Map<String, String> {
        if (encoded.isNullOrBlank()) return emptyMap()
        return runCatching {
            json.parseToJsonElement(encoded).jsonObject
                .mapValues { (_, v) -> v.jsonPrimitive.content }
        }.getOrDefault(emptyMap())
    }

    /** Revealed cells are stored lowercase, so the lock survives relaunch. */
    fun isLocked(letter: String): Boolean = letter.isNotEmpty() && letter[0].isLowerCase()

    /**
     * True for a cell the starter gift filled, as opposed to a hint the player
     * asked for. Both are locked; only this one is free.
     */
    fun isGift(letter: String): Boolean = letter.endsWith(GIFT_MARKER)

    /**
     * True once the player has typed or pencilled anything themselves.
     * Revealed cells (hints, the starter-word gift) don't count.
     */
    fun hasPlayerEntries(entries: Map<String, String>, pencil: Map<String, String>): Boolean =
        entries.values.any { it != it.lowercase() } || pencil.isNotEmpty()
}
