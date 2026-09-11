package com.sambulosendas1.biblecrossword.ui.game

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import com.google.common.truth.Truth.assertThat
import com.sambulosendas1.biblecrossword.domain.content.ClueData
import com.sambulosendas1.biblecrossword.domain.content.ClueDirection
import com.sambulosendas1.biblecrossword.domain.content.Puzzle
import com.sambulosendas1.biblecrossword.domain.content.PuzzleDifficulty
import com.sambulosendas1.biblecrossword.domain.engine.GameEngine
import org.junit.Rule
import org.junit.Test

/**
 * The timer contract on a real Compose host — the half the shared vectors
 * can't reach. `engine.tick` itself is pinned by `engine_timer.json`; what
 * these assert is that the *gates* open and close when they should.
 */
class SolveClockTest {

    @get:Rule val compose = createComposeRule()

    private fun puzzle() = Puzzle(
        id = "test-001", title = "Test", difficulty = PuzzleDifficulty.EASY,
        verse = "", reference = "", publishDate = "2026-01-01", size = 3,
        grid = listOf("CAT", "A.O", "TOP"),
        clues = listOf(
            ClueData(1, ClueDirection.ACROSS, 0, 0, "Feline", "CAT"),
            ClueData(1, ClueDirection.DOWN, 0, 0, "Feline", "CAT"),
        ),
    )

    private class TestOwner : LifecycleOwner {
        val registry = LifecycleRegistry(this)
        override val lifecycle: Lifecycle get() = registry
    }

    @Test
    fun clockAdvancesWhileResumedAndVisible() {
        val engine = GameEngine(puzzle())
        val owner = TestOwner()
        compose.setContent { SolveClock(engine = engine, onTick = {}, lifecycleOwner = owner) }
        compose.runOnUiThread { owner.registry.currentState = Lifecycle.State.RESUMED }
        compose.waitForIdle()

        // The ticker is real time, not the Compose clock: wait for the engine.
        compose.waitUntil(timeoutMillis = 6_000) { engine.elapsed() >= 2 }
        assertThat(engine.elapsed()).isAtLeast(2)
    }

    @Test
    fun pausingTheLifecycleFreezesTheClock() {
        val engine = GameEngine(puzzle())
        val owner = TestOwner()
        compose.setContent { SolveClock(engine = engine, onTick = {}, lifecycleOwner = owner) }
        compose.runOnUiThread { owner.registry.currentState = Lifecycle.State.RESUMED }
        compose.waitUntil(timeoutMillis = 6_000) { engine.elapsed() >= 1 }

        // Leaving the destination (a tab switch, a push) drops to STARTED.
        compose.runOnUiThread { owner.registry.currentState = Lifecycle.State.STARTED }
        compose.waitForIdle()
        val frozen = engine.elapsed()
        Thread.sleep(3_000)
        assertThat(engine.elapsed()).isEqualTo(frozen)

        // And it resumes — the first tick back only re-establishes the baseline.
        compose.runOnUiThread { owner.registry.currentState = Lifecycle.State.RESUMED }
        compose.waitUntil(timeoutMillis = 6_000) { engine.elapsed() > frozen }
        assertThat(engine.elapsed()).isGreaterThan(frozen)
    }

    @Test
    fun suppressionFreezesTheClockAndStacks() {
        val engine = GameEngine(puzzle())
        val owner = TestOwner()
        compose.setContent { SolveClock(engine = engine, onTick = {}, lifecycleOwner = owner) }
        compose.runOnUiThread { owner.registry.currentState = Lifecycle.State.RESUMED }
        compose.waitUntil(timeoutMillis = 6_000) { engine.elapsed() >= 1 }

        // The verse sheet opens; a paywall opens over it; the paywall closes.
        engine.pushSuppression()
        engine.pushSuppression()
        val frozen = engine.elapsed()
        Thread.sleep(2_500)
        assertThat(engine.elapsed()).isEqualTo(frozen)

        engine.popSuppression()
        Thread.sleep(2_500)
        // Still suppressed: the inner dismiss must not restart the outer's clock.
        assertThat(engine.elapsed()).isEqualTo(frozen)

        engine.popSuppression()
        compose.waitUntil(timeoutMillis = 6_000) { engine.elapsed() > frozen }
        assertThat(engine.elapsed()).isGreaterThan(frozen)
    }

    @Test
    fun leavingCompositionStopsTheClock() {
        val engine = GameEngine(puzzle())
        val owner = TestOwner()
        var present by mutableStateOf(true)
        compose.setContent {
            if (present) SolveClock(engine = engine, onTick = {}, lifecycleOwner = owner) else Box(Modifier)
        }
        compose.runOnUiThread { owner.registry.currentState = Lifecycle.State.RESUMED }
        compose.waitUntil(timeoutMillis = 6_000) { engine.elapsed() >= 1 }

        present = false
        compose.waitForIdle()
        assertThat(engine.isVisible).isFalse()
        val frozen = engine.elapsed()
        Thread.sleep(2_500)
        assertThat(engine.elapsed()).isEqualTo(frozen)
    }
}
