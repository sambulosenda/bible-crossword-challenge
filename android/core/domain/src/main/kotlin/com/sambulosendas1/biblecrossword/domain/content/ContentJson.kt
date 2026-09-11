package com.sambulosendas1.biblecrossword.domain.content

import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

/**
 * The one `Json` configuration every content file is decoded with.
 *
 * - `ignoreUnknownKeys`: the files are authored for iOS first; a new field
 *   there must never break the Android decode.
 * - `classDiscriminator = "kind"`: how [PackSeason] is tagged in `packs.json`.
 *
 * Callers hand in the file text; where it comes from (Android assets, a test
 * reading the shared `Resources/` directory) is not this module's concern.
 */
object ContentJson {
    val json: Json = Json {
        ignoreUnknownKeys = true
        classDiscriminator = "kind"
    }

    fun puzzles(text: String): List<Puzzle> =
        json.decodeFromString(ListSerializer(Puzzle.serializer()), text)

    fun packs(text: String): List<PuzzlePack> =
        json.decodeFromString(ListSerializer(PuzzlePack.serializer()), text)

    fun quests(text: String): List<QuestLine> =
        json.decodeFromString(ListSerializer(QuestLine.serializer()), text)

    /** 4.6 MB. Call off the main thread, once, and keep the result. */
    fun bible(text: String): Bible =
        json.decodeFromString(Bible.serializer(), text)
}
