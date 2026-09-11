package com.sambulosendas1.biblecrossword.domain.content

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import com.sambulosendas1.biblecrossword.domain.spec.Content
import com.sambulosendas1.biblecrossword.domain.spec.Vectors
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Test
import java.time.LocalDate

/**
 * Decodes the real shared content — the same files the iOS app bundles — and
 * checks the rotation against `spec/vectors/rotation.json`.
 */
class ContentTest {

    private val catalogue: PuzzleCatalogue by lazy {
        PuzzleCatalogue(
            allPuzzles = ContentJson.puzzles(Content.read("puzzles.json")),
            packs = ContentJson.packs(Content.read("packs.json")),
            quests = ContentJson.quests(Content.read("quests.json")),
        )
    }

    @Test
    fun `puzzles decode with the counts the requirements record`() {
        assertThat(catalogue.allPuzzles).hasSize(241)
        assertThat(catalogue.puzzles.size + catalogue.minis.size + catalogue.sundays.size + catalogue.allPuzzles.count { it.isPackExclusive && !it.isMini && !it.isSunday }).isEqualTo(241)
        assertThat(catalogue.minis).hasSize(90)
        assertThat(catalogue.sundays).hasSize(13)
        assertThat(catalogue.allPuzzles.map { it.id }.toSet()).hasSize(241)
        // Grid rows are square and every clue's answer fits its grid.
        for (p in catalogue.allPuzzles) {
            assertThat(p.grid).hasSize(p.size)
            for (row in p.grid) assertThat(row).hasLength(p.size)
            for (c in p.clues) for (pos in c.positions) {
                assertThat(pos.row).isLessThan(p.size)
                assertThat(pos.col).isLessThan(p.size)
                assertThat(p.grid[pos.row][pos.col]).isNotEqualTo('.')
            }
        }
    }

    @Test
    fun `pool counts match what iOS pinned in constants`() {
        val pools = Vectors.family("constants")["constants"]!!.jsonObject["rotation"]!!.jsonObject["poolCounts"]!!.jsonObject
        assertThat(catalogue.puzzles.size).isEqualTo(pools["daily"]!!.jsonPrimitive.content.toInt())
        assertThat(catalogue.minis.size).isEqualTo(pools["mini"]!!.jsonPrimitive.content.toInt())
        assertThat(catalogue.sundays.size).isEqualTo(pools["sunday"]!!.jsonPrimitive.content.toInt())
        assertThat(catalogue.allPuzzles.size).isEqualTo(pools["all"]!!.jsonPrimitive.content.toInt())
    }

    @Test
    fun `packs and quests decode, including every season kind`() {
        assertThat(catalogue.packs).hasSize(10)
        assertThat(catalogue.quests).hasSize(3)
        val seasons = catalogue.packs.mapNotNull { it.season }
        assertThat(seasons.filterIsInstance<PackSeason.Easter>()).isNotEmpty()
        assertThat(seasons.filterIsInstance<PackSeason.Annual>()).isNotEmpty()
        // Every pack and quest member resolves to a real puzzle.
        for (pack in catalogue.packs) assertThat(catalogue.puzzlesIn(pack)).hasSize(pack.puzzleIDs.size)
        for (quest in catalogue.quests) assertThat(catalogue.puzzlesIn(quest)).hasSize(quest.puzzleIDs.size)
        // The first quest is the free one, by authoring convention.
        assertThat(catalogue.quests.first().isPremium).isFalse()
    }

    @Test
    fun `the Bible decodes`() {
        val bible = ContentJson.bible(Content.read("bsb.json"))
        assertThat(bible.abbreviation).isEqualTo("BSB")
        assertThat(bible.books).hasSize(66)
        assertThat(bible.books.count { it.testament == Testament.OLD }).isEqualTo(39)
        assertThat(bible.books.first().name).isEqualTo("Genesis")
        assertThat(bible.books.first().chapters.first().verses.first().number).isEqualTo(1)
    }

    @Test
    fun `rotation matches the iOS vectors on every date`() {
        for (case in Vectors.cases("rotation")) {
            val date = LocalDate.parse(case["given"]!!.jsonObject["date"]!!.jsonPrimitive.content)
            val expect = case["expect"]!!.jsonObject
            val name = case["name"]!!.jsonPrimitive.content
            assertWithMessage("dayIndex $name").that(catalogue.dayIndex(date)).isEqualTo(expect["dayIndex"]!!.jsonPrimitive.content.toInt())
            assertWithMessage("weekIndex $name").that(catalogue.weekIndex(date)).isEqualTo(expect["weekIndex"]!!.jsonPrimitive.content.toInt())
            assertWithMessage("daily $name").that(catalogue.dailyPuzzle(date)?.id).isEqualTo(expect["daily"]!!.jsonPrimitive.content)
            assertWithMessage("mini $name").that(catalogue.dailyMini(date)?.id).isEqualTo(expect["mini"]!!.jsonPrimitive.content)
            assertWithMessage("sunday $name").that(catalogue.sundaySpecial(date)?.id).isEqualTo(expect["sunday"]!!.jsonPrimitive.content)
            assertWithMessage("dailyWindow $name").that(catalogue.rotationWindow(catalogue.puzzles, date, 7).map { it.id })
                .isEqualTo(expect["dailyWindow"]!!.jsonArray.map { it.jsonPrimitive.content })
            assertWithMessage("miniWindow $name").that(catalogue.rotationWindow(catalogue.minis, date, 7).map { it.id })
                .isEqualTo(expect["miniWindow"]!!.jsonArray.map { it.jsonPrimitive.content })
        }
    }
}
