package com.sambulosendas1.biblecrossword.domain.spec

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import java.io.File

/**
 * Access to the shared `spec/vectors` corpus from tests. The directory comes
 * from the `spec.vectors.dir` system property set in the module's build file;
 * `content.dir` points at the iOS `Resources/` directory the same way.
 */
object Vectors {
    private val dir = File(System.getProperty("spec.vectors.dir") ?: error("spec.vectors.dir not set"))
    private val json = Json { ignoreUnknownKeys = true }

    fun family(name: String): JsonObject =
        json.parseToJsonElement(File(dir, "$name.json").readText()).jsonObject

    fun cases(name: String): List<JsonObject> = family(name)["cases"]!!.jsonArray.map { it.jsonObject }

    val files: List<File> get() = dir.listFiles { f -> f.extension == "json" }!!.sortedBy { it.name }
}

object Content {
    private val dir = File(System.getProperty("content.dir") ?: error("content.dir not set"))

    fun read(name: String): String = File(dir, name).readText()
}

/** The real shared content, decoded once per test JVM. */
object TestContent {
    val catalogue: com.sambulosendas1.biblecrossword.domain.content.PuzzleCatalogue by lazy {
        com.sambulosendas1.biblecrossword.domain.content.PuzzleCatalogue(
            allPuzzles = com.sambulosendas1.biblecrossword.domain.content.ContentJson.puzzles(Content.read("puzzles.json")),
            packs = com.sambulosendas1.biblecrossword.domain.content.ContentJson.packs(Content.read("packs.json")),
            quests = com.sambulosendas1.biblecrossword.domain.content.ContentJson.quests(Content.read("quests.json")),
        )
    }
}
