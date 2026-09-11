package com.sambulosendas1.biblecrossword.ui.game

import android.content.Context
import android.os.SystemClock
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.sambulosendas1.biblecrossword.domain.engine.GameEngine
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive

/**
 * Drives the engine's active-time clock, and nothing else.
 *
 * The contract, straight from iOS: time accrues **only** while the grid is
 * genuinely on screen. Time on another tab, under a sheet, or backgrounded must
 * never count, and the recorded solve time is the sum of every sitting.
 *
 * Three gates, because no single Android signal covers all three cases:
 *
 *  - **Backgrounded / another destination** → `repeatOnLifecycle(RESUMED)` on
 *    the `NavBackStackEntry`'s lifecycle. Cancelling the block *is* dropping
 *    the baseline. Picture-in-picture lands here correctly too.
 *  - **Composed but not shown** (a pager's off-screen page, an `AnimatedContent`
 *    still cross-fading out the old screen) → [VisibilityProbe], the direct
 *    analog of the UIKit window probe iOS needed because SwiftUI's lifecycle
 *    lied about exactly this.
 *  - **Occluded by a sheet** → explicit only, via `pushSuppression`. Nothing
 *    infers it, exactly as on iOS.
 *
 * Deliberately **not** `withInfiniteAnimationFrameNanos`: it honours
 * `LocalInfiniteAnimationPolicy`, which the Compose test harness installs to
 * cancel infinite animations so `waitForIdle` can settle — a clock built on it
 * is dead in the very tests that would verify it.
 *
 * Deliberately **not** `hasWindowFocus`: every `ModalBottomSheet` steals focus,
 * including the clue list, which on iOS deliberately does *not* suppress. Only
 * the verse sheet suppresses, because reading Scripture must cost no time while
 * browsing clues is solving.
 */
@Composable
fun SolveClock(
    engine: GameEngine,
    onTick: () -> Unit,
    lifecycleOwner: LifecycleOwner = LocalLifecycleOwner.current,
) {
    // Gate 2: composed-but-not-shown.
    VisibilityProbe { visible -> engine.isVisible = visible }

    // Gate 1: lifecycle. Cancels on pause, restarts on resume.
    LaunchedEffect(lifecycleOwner, engine) {
        lifecycleOwner.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (isActive) {
                delay(1_000)
                engine.tick(SystemClock.elapsedRealtime())
                onTick()
            }
        }
    }

    DisposableEffect(engine) {
        onDispose {
            engine.isVisible = false
            engine.pauseTimer()
        }
    }
}

/**
 * A zero-size View reporting whether it is actually attached, in a visible
 * window, and shown. Uses [View.onVisibilityAggregated] (API 24+), which is the
 * signal that accounts for an ancestor being hidden.
 */
@Composable
private fun VisibilityProbe(onChange: (Boolean) -> Unit) {
    val callback = remember { onChange }
    AndroidView(
        factory = { context -> ProbeView(context, callback) },
        modifier = Modifier,
        onRelease = { it.report(false) },
    )
}

private class ProbeView(context: Context, private val onChange: (Boolean) -> Unit) : View(context) {
    private var lastReported: Boolean? = null

    init {
        // Zero-size and never drawn; it exists purely for the callbacks.
        setWillNotDraw(true)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) = setMeasuredDimension(0, 0)

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        report(computeVisible())
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        report(false)
    }

    override fun onWindowVisibilityChanged(visibility: Int) {
        super.onWindowVisibilityChanged(visibility)
        report(computeVisible())
    }

    override fun onVisibilityAggregated(isVisible: Boolean) {
        super.onVisibilityAggregated(isVisible)
        report(isVisible && computeVisible())
    }

    private fun computeVisible(): Boolean = isAttachedToWindow && windowVisibility == VISIBLE

    fun report(visible: Boolean) {
        if (lastReported == visible) return
        lastReported = visible
        onChange(visible)
    }
}
