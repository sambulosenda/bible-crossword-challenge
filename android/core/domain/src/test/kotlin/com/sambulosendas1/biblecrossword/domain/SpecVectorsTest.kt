package com.sambulosendas1.biblecrossword.domain

import com.google.common.truth.Truth.assertThat
import com.sambulosendas1.biblecrossword.domain.spec.Vectors
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Test
import java.io.File

/**
 * The Kotlin end of the cross-platform contract in `spec/vectors/`.
 *
 * P0 proves the plumbing: every family the iOS generator writes is found,
 * parses, and names itself correctly. Each family gains a real assertion
 * against the ported rule as that rule lands (P2 onwards), so that a change
 * to a rule on iOS — which regenerates the vector — turns this suite red.
 */
class SpecVectorsTest {

    private val dir = File(System.getProperty("spec.vectors.dir") ?: error("spec.vectors.dir not set"))
    private val json = Json { ignoreUnknownKeys = true }

    private fun family(name: String): JsonObject = Vectors.family(name)

    @Test
    fun `every family the iOS generator writes is present`() {
        assertThat(dir.isDirectory).isTrue()
        val files = dir.listFiles { f -> f.extension == "json" }!!.map { it.nameWithoutExtension }.sorted()
        assertThat(files).containsExactly(
            "achievements", "analytics", "challenge_links", "constants", "engine_timer",
            "engine_traces", "hint_quota", "puzzle_access", "reminder_ask",
            "review_ask", "rotation", "streaks", "sync_merge", "trial_reoffer",
        ).inOrder()
    }

    @Test
    fun `each file names its own family and carries cases`() {
        for (file in dir.listFiles { f -> f.extension == "json" }!!) {
            val root = json.parseToJsonElement(file.readText()).jsonObject
            assertThat(root["family"]!!.jsonPrimitive.content).isEqualTo(file.nameWithoutExtension)
            assertThat(root["source"]!!.jsonArray).isNotEmpty()
            // constants.json is a pin sheet, not a rule evaluation: it carries
            // `constants` and no cases. Every other family must have cases.
            if (file.nameWithoutExtension == "constants") {
                assertThat(root["constants"]!!.jsonObject).isNotEmpty()
            } else {
                assertThat(root["cases"]!!.jsonArray).isNotEmpty()
            }
        }
    }

    @Test
    fun `constants carry the numbers the port must match`() {
        val constants = family("constants")["constants"]!!.jsonObject
        val hints = constants["hints"]!!.jsonObject
        assertThat(hints["freeHintLimit"]!!.jsonPrimitive.content.toInt()).isEqualTo(3)
        assertThat(hints["reducedHintLimit"]!!.jsonPrimitive.content.toInt()).isEqualTo(1)
        assertThat(constants["streaks"]!!.jsonObject["maxStreakFreezes"]!!.jsonPrimitive.content.toInt()).isEqualTo(3)
        assertThat(constants["achievements"]!!.jsonArray).hasSize(14)
    }
}
