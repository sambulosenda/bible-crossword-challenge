package com.sambulosendas1.biblecrossword.domain.engine

import com.google.common.truth.Truth.assertWithMessage
import com.sambulosendas1.biblecrossword.domain.content.ClueDirection
import com.sambulosendas1.biblecrossword.domain.content.GridPos
import com.sambulosendas1.biblecrossword.domain.spec.TestContent
import com.sambulosendas1.biblecrossword.domain.spec.Vectors
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory

/**
 * Replays every script in `spec/vectors/engine_traces.json` against
 * [GameEngine] and checks the observable state after every input, then the
 * final snapshot — so a port that diverges fails at the exact input.
 * `engine_timer.json` does the same for the clock.
 */
class EngineVectorsTest {

    private val catalogue by lazy { TestContent.catalogue }

    @TestFactory
    fun `engine traces`(): List<DynamicTest> = Vectors.cases("engine_traces").map { case ->
        val name = case["name"]!!.jsonPrimitive.content
        DynamicTest.dynamicTest(name) { replay(name, case) }
    }

    private fun replay(name: String, case: JsonObject) {
        val given = case["given"]!!.jsonObject
        val expect = case["expect"]!!.jsonObject
        val puzzleID = given["puzzleID"]!!.jsonPrimitive.content
        val puzzle = catalogue.puzzle(puzzleID) ?: error("puzzle $puzzleID not in catalogue")
        val engine = GameEngine(puzzle, isLearning = given["learning"]!!.jsonPrimitive.boolean)

        val completed = mutableListOf<String>()
        val checks = mutableListOf<Pair<List<GridPos>, Int>>()
        engine.onWordCompleted = { completed += it.id }
        engine.onCheckResult = { correct, wrong -> checks += correct to wrong }

        // Slots: order, ids, answers, starts, lengths.
        val expectedSlots = expect["slots"]!!.jsonArray.map { it.jsonObject }
        val actualSlots = engine.allSlots
        assertWithMessage("$name · slot count").that(actualSlots.size).isEqualTo(expectedSlots.size)
        for ((i, s) in expectedSlots.withIndex()) {
            val a = actualSlots[i]
            assertWithMessage("$name · slot $i id").that(a.id).isEqualTo(s["id"]!!.jsonPrimitive.content)
            assertWithMessage("$name · slot $i answer").that(a.answer).isEqualTo(s["answer"]!!.jsonPrimitive.content)
            assertWithMessage("$name · slot $i length").that(a.length).isEqualTo(s["length"]!!.jsonPrimitive.int)
            val start = s["start"]!!.jsonArray.map { it.jsonPrimitive.int }
            assertWithMessage("$name · slot $i start").that(listOf(a.positions[0].row, a.positions[0].col)).isEqualTo(start)
        }

        val steps = expect["steps"]!!.jsonArray.map { it.jsonObject }
        val script = given["script"]!!.jsonArray.map { it.jsonObject }
        assertState("$name · step 0 (init)", engine, steps[0]["state"]!!.jsonObject, result = null)

        for ((i, op) in script.withIndex()) {
            val result: Any? = apply(engine, op)
            val step = steps[i + 1]
            val label = "$name · step ${i + 1} ${op["op"]!!.jsonPrimitive.content}"
            assertState(label, engine, step["state"]!!.jsonObject, result)
        }

        val entries = expect["entries"]!!.jsonObject.mapValues { it.value.jsonPrimitive.content }
        val pencil = expect["pencil"]!!.jsonObject.mapValues { it.value.jsonPrimitive.content }
        assertWithMessage("$name · entries").that(engine.snapshot()).isEqualTo(entries)
        assertWithMessage("$name · pencil").that(engine.pencilSnapshot()).isEqualTo(pencil)
        assertWithMessage("$name · wordsCompleted").that(completed)
            .isEqualTo(expect["wordsCompleted"]!!.jsonArray.map { it.jsonPrimitive.content })
        val expectedChecks = expect["checks"]!!.jsonArray.map { c ->
            val o = c.jsonObject
            o["correct"]!!.jsonArray.map { p -> p.jsonArray.let { GridPos(it[0].jsonPrimitive.int, it[1].jsonPrimitive.int) } } to o["wrong"]!!.jsonPrimitive.int
        }
        assertWithMessage("$name · checks").that(checks).isEqualTo(expectedChecks)
        assertWithMessage("$name · cellTaps").that(engine.cellTaps).isEqualTo(expect["cellTaps"]!!.jsonPrimitive.int)
        assertWithMessage("$name · keyPresses").that(engine.keyPresses).isEqualTo(expect["keyPresses"]!!.jsonPrimitive.int)
    }

    /** Applies one scripted input; returns what the iOS trace recorded as `result` for it, if any. */
    private fun apply(engine: GameEngine, op: JsonObject): Any? {
        fun int(k: String) = op[k]!!.jsonPrimitive.int
        fun str(k: String) = op[k]!!.jsonPrimitive.content
        return when (val kind = str("op")) {
            "tap" -> { engine.tapCell(GridPos(int("row"), int("col"))); null }
            "enter" -> { engine.enter(str("letter").first()); null }
            "delete" -> { engine.delete(); null }
            "toggleDirection" -> { engine.toggleDirection(); null }
            "pencilMode" -> { engine.isPencilMode = op["on"]!!.jsonPrimitive.boolean; null }
            "selectSlot" -> { engine.select(engine.allSlots.first { it.id == str("id") }); null }
            "advanceClue" -> { engine.advanceClue(int("by")); null }
            "revealLetter" -> engine.revealLetter()
            "revealWord" -> engine.revealWord()
            "revealPuzzle" -> engine.revealPuzzle()
            "check" -> engine.check(CheckScope.entries.first { it.rawValue == str("scope") })
            "giftStarterWord" -> engine.giftStarterWord()?.id
            "restore" -> {
                engine.restore(
                    op["entries"]!!.jsonObject.mapValues { it.value.jsonPrimitive.content },
                    op["pencil"]!!.jsonObject.mapValues { it.value.jsonPrimitive.content },
                )
                null
            }
            "moveSelection" -> { engine.moveSelection(int("rowDelta"), int("colDelta")); null }
            else -> error("unknown op $kind")
        }
    }

    private fun assertState(label: String, engine: GameEngine, state: JsonObject, result: Any?) {
        val sel = state["selected"]!!.jsonArray.map { it.jsonPrimitive.int }
        assertWithMessage("$label · selected").that(listOf(engine.selected.row, engine.selected.col)).isEqualTo(sel)
        assertWithMessage("$label · direction").that(engine.direction.rawValue).isEqualTo(state["direction"]!!.jsonPrimitive.content)
        val activeSlot = state["activeSlot"]!!.let { if (it is JsonNull) null else it.jsonPrimitive.content }
        assertWithMessage("$label · activeSlot").that(engine.activeSlot?.id).isEqualTo(activeSlot)
        assertWithMessage("$label · filled").that(engine.filledPlayableCount).isEqualTo(state["filled"]!!.jsonPrimitive.int)
        assertWithMessage("$label · remainingClues").that(engine.remainingClueCount).isEqualTo(state["remainingClues"]!!.jsonPrimitive.int)
        assertWithMessage("$label · hintsUsed").that(engine.hintsUsed).isEqualTo(state["hintsUsed"]!!.jsonPrimitive.int)
        assertWithMessage("$label · isComplete").that(engine.isComplete).isEqualTo(state["isComplete"]!!.jsonPrimitive.boolean)
        assertWithMessage("$label · wordSolveTick").that(engine.wordSolveTick).isEqualTo(state["wordSolveTick"]!!.jsonPrimitive.int)
        val expectedResult = state["result"]
        if (expectedResult != null) {
            val normalised: Any? = when (expectedResult) {
                is JsonNull -> null
                is JsonPrimitive -> expectedResult.booleanOrNull ?: expectedResult.intOrNull ?: expectedResult.content
                else -> expectedResult.toString()
            }
            assertWithMessage("$label · result").that(result).isEqualTo(normalised)
        }
    }

    @TestFactory
    fun `engine timer`(): List<DynamicTest> = Vectors.cases("engine_timer").map { case ->
        val name = case["name"]!!.jsonPrimitive.content
        DynamicTest.dynamicTest(name) {
            val given = case["given"]!!.jsonObject
            val engine = GameEngine(catalogue.minis.first())
            val seed = given["seedElapsed"]!!.jsonPrimitive.int
            if (seed > 0) engine.seedElapsed(seed)
            val base = 1_000_000_000L
            val out = mutableListOf<Int>()
            for (t in given["ticks"]!!.jsonArray.map { it.jsonObject }) {
                engine.isVisible = t["attached"]!!.jsonPrimitive.boolean
                val suppressed = t["suppressed"]!!.jsonPrimitive.boolean
                if (suppressed && !engine.isTimerSuppressed) engine.pushSuppression()
                if (!suppressed && engine.isTimerSuppressed) engine.popSuppression()
                val at = t["at"]!!.jsonPrimitive.content.toDouble()
                engine.tick(base + (at * 1000).toLong())
                out += engine.elapsed()
            }
            assertWithMessage(name).that(out)
                .isEqualTo(case["expect"]!!.jsonObject["elapsedAfterEach"]!!.jsonArray.map { it.jsonPrimitive.int })
        }
    }

    @Suppress("unused")
    private val directions = ClueDirection.entries
}
