package com.sambulosendas1.biblecrossword.domain.content

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/*
 * The bundled Bible (Berean Standard Bible, public domain), decoded from the
 * shared `bsb.json`. Mirrors iOS `Models/ScriptureModels.swift`. The file is
 * 4.6 MB: decode it lazily, off the main thread — never at launch.
 */

@Serializable
enum class Testament {
    @SerialName("old") OLD,
    @SerialName("new") NEW;

    val label: String get() = if (this == OLD) "Old Testament" else "New Testament"
}

@Serializable
data class Bible(
    val translation: String,
    val abbreviation: String,
    val books: List<BibleBook>,
)

@Serializable
data class BibleBook(
    val name: String,
    val testament: Testament,
    val chapters: List<BibleChapter>,
) {
    val id: String get() = name
    val chapterCount: Int get() = chapters.size
}

@Serializable
data class BibleChapter(
    val number: Int,
    val verses: List<BibleVerse>,
) {
    val id: Int get() = number
}

@Serializable
data class BibleVerse(
    val number: Int,
    val text: String,
) {
    val id: Int get() = number
}
