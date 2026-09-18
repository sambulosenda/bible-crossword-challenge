package com.sambulosendas1.biblecrossword.domain.progress

import com.google.common.truth.Truth.assertThat
import com.sambulosendas1.biblecrossword.domain.spec.Vectors
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Test

class EntriesCodecTest {

    @Test
    fun `round-trips every entries and pencil map the iOS engine traces emit`() {
        var seen = 0
        for (case in Vectors.cases("engine_traces")) {
            val expect = case["expect"]!!.jsonObject
            for (key in listOf("entries", "pencil")) {
                val map = expect[key]!!.jsonObject.mapValues { it.value.jsonPrimitive.content }
                assertThat(EntriesCodec.decode(EntriesCodec.encode(map))).isEqualTo(map)
                seen += map.size
            }
        }
        assertThat(seen).isGreaterThan(0)
    }

    @Test
    fun `encoding is compact, sorted, and empty maps store as null`() {
        assertThat(EntriesCodec.encode(emptyMap())).isNull()
        assertThat(EntriesCodec.encode(mapOf("1,4" to "W", "0,3" to "w"))).isEqualTo("""{"0,3":"w","1,4":"W"}""")
        assertThat(EntriesCodec.decode(null)).isEmpty()
        assertThat(EntriesCodec.decode("not json")).isEmpty()
    }

    @Test
    fun `lowercase is the lock, and player entries exclude revealed cells`() {
        assertThat(EntriesCodec.isLocked("w")).isTrue()
        assertThat(EntriesCodec.isLocked("W")).isFalse()
        assertThat(EntriesCodec.hasPlayerEntries(mapOf("0,0" to "w"), emptyMap())).isFalse()
        assertThat(EntriesCodec.hasPlayerEntries(mapOf("0,0" to "w", "0,1" to "E"), emptyMap())).isTrue()
        assertThat(EntriesCodec.hasPlayerEntries(emptyMap(), mapOf("0,0" to "Z"))).isTrue()
    }

    @Test
    fun `the gift marker rides on the lock without disturbing it`() {
        val gifted = "w" + EntriesCodec.GIFT_MARKER

        // Still locked, still not player progress, still decodes to the letter.
        assertThat(EntriesCodec.isLocked(gifted)).isTrue()
        assertThat(EntriesCodec.isGift(gifted)).isTrue()
        assertThat(EntriesCodec.hasPlayerEntries(mapOf("0,0" to gifted), emptyMap())).isFalse()
        assertThat(gifted.uppercase().first()).isEqualTo('W')

        // A hint the player asked for is locked but not gifted.
        assertThat(EntriesCodec.isGift("w")).isFalse()
        assertThat(EntriesCodec.isGift("W")).isFalse()

        assertThat(EntriesCodec.decode(EntriesCodec.encode(mapOf("0,0" to gifted))))
            .isEqualTo(mapOf("0,0" to gifted))
    }
}
