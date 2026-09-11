package com.sambulosendas1.biblecrossword.ui.haptics

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView

/**
 * The six haptic semantics the iOS app uses (`sensoryFeedback`), mapped onto
 * Android's two very different mechanisms.
 *
 * Why this exists rather than `LocalHapticFeedback`: `CONFIRM` and `REJECT` are
 * API 30, and `View.performHapticFeedback` with an unsupported constant is a
 * **no-op, not a crash** — so success/warning/error would silently vanish on a
 * large slice of the install base. That matters here because the locked-cell
 * haptic is a *correctness* requirement: typing into a revealed cell skips the
 * letter, and a silent skip reads as a broken keyboard.
 *
 * So: prefer `performHapticFeedback` (it respects the user's touch-feedback
 * setting) and fall back to hand-authored waveforms on 26–29, which check that
 * setting themselves because raw [Vibrator] bypasses it.
 */
interface Haptics {
    /** Cursor moved, key pressed, page turned. */
    fun selection()
    /** A key on the custom keyboard. */
    fun keyTap()
    /** A word solved — light, because it fires often. */
    fun impactLight()
    /** The puzzle completed, a verse saved. */
    fun success()
    /** Typing into a locked cell; the grid filled but wrong. */
    fun warning()
    /** A check found mistakes. */
    fun error()
}

object NoHaptics : Haptics {
    override fun selection() = Unit
    override fun keyTap() = Unit
    override fun impactLight() = Unit
    override fun success() = Unit
    override fun warning() = Unit
    override fun error() = Unit
}

val LocalHaptics = staticCompositionLocalOf<Haptics> { NoHaptics }

@Composable
fun rememberHaptics(): Haptics {
    val view = LocalView.current
    val context = LocalContext.current
    return remember(view, context) { AndroidHaptics(view, context) }
}

private class AndroidHaptics(private val view: View, context: Context) : Haptics {

    private val vibrator: Vibrator? = runCatching {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }.getOrNull()?.takeIf { it.hasVibrator() }

    private val resolver = context.contentResolver

    /** Raw [Vibrator] bypasses the system touch-feedback switch, so honour it here. */
    private val touchFeedbackEnabled: Boolean
        get() = runCatching {
            Settings.System.getInt(resolver, Settings.System.HAPTIC_FEEDBACK_ENABLED, 1) == 1
        }.getOrDefault(true)

    override fun selection() = perform(HapticFeedbackConstants.CLOCK_TICK)

    override fun keyTap() = perform(HapticFeedbackConstants.KEYBOARD_TAP)

    override fun impactLight() = perform(HapticFeedbackConstants.CONTEXT_CLICK)

    override fun success() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            perform(HapticFeedbackConstants.CONFIRM)
        } else {
            // Two pulses, rising — distinguishable by feel from warning and error.
            waveform(longArrayOf(0, 18, 60, 32))
        }
    }

    override fun warning() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            perform(HapticFeedbackConstants.REJECT)
        } else {
            waveform(longArrayOf(0, 14, 70, 14))
        }
    }

    override fun error() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            perform(HapticFeedbackConstants.REJECT)
        } else {
            waveform(longArrayOf(0, 22, 50, 22, 50, 22))
        }
    }

    private fun perform(constant: Int) {
        view.performHapticFeedback(constant)
    }

    private fun waveform(timings: LongArray) {
        val v = vibrator ?: return
        if (!touchFeedbackEnabled) return
        runCatching { v.vibrate(VibrationEffect.createWaveform(timings, -1)) }
    }
}
