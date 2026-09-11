package com.sambulosendas1.biblecrossword.ui.game

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sambulosendas1.biblecrossword.domain.content.GridPos
import com.sambulosendas1.biblecrossword.ui.theme.BccTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.floor
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * The square grid. Up to 15×15 it is sized to fit its container — the shipped
 * feel. Beyond that (the 21×21 Sunday Special) cells fitted to a phone would be
 * unreadable and untappable, so the grid becomes a pinch-zoomable, pannable
 * viewport that keeps the selected cell in view.
 */
@Composable
fun CrosswordGrid(
    state: GameUiState,
    flashing: Set<GridPos>,
    onTapCell: (GridPos) -> Unit,
    modifier: Modifier = Modifier,
    /** Advances on each failed check — drives the shake. */
    shakeTick: Int = 0,
    reduceMotion: Boolean = false,
) {
    val shake = remember { Animatable(0f) }
    LaunchedEffect(shakeTick) {
        if (shakeTick == 0 || reduceMotion) return@LaunchedEffect
        shake.snapTo(0f)
        shake.animateTo(1f, tween(durationMillis = 450))
    }
    // Horizontal shake: a few oscillations as the value advances by one.
    val shakeOffset: (Density: Float) -> Float = { amountPx -> amountPx * sin(shake.value * Math.PI.toFloat() * 3f) }

    BoxWithConstraints(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        val density = LocalDensity.current
        val shortest = min(maxWidth.value, maxHeight.value)
        val fitSide = floor(shortest / state.size).dp

        if (state.size > ZOOM_THRESHOLD) {
            ZoomableGrid(state, flashing, onTapCell, fitSide, shakeOffset, reduceMotion)
        } else {
            val amountPx = with(density) { SHAKE_AMOUNT.toPx() }
            GridRows(
                state = state,
                flashing = flashing,
                side = fitSide,
                onTapCell = onTapCell,
                reduceMotion = reduceMotion,
                modifier = Modifier.graphicsLayer { translationX = shakeOffset(amountPx) },
            )
        }
    }
}

@Composable
private fun ZoomableGrid(
    state: GameUiState,
    flashing: Set<GridPos>,
    onTapCell: (GridPos) -> Unit,
    fitSide: Dp,
    shakeOffset: (Float) -> Float,
    reduceMotion: Boolean,
) {
    val density = LocalDensity.current
    // The default shows readable, tappable cells rather than the whole board —
    // the first act on a big grid is reading a clue, not surveying it.
    var side by remember { mutableFloatStateOf(maxOf(fitSide.value, COMFORTABLE_SIDE)) }
    val horizontal = rememberScrollState()
    val vertical = rememberScrollState()
    val scope = rememberCoroutineScope()

    // Typing along a word must never walk the cursor off-screen — including
    // under the keyboard, which is why it centres rather than scrolling to the
    // nearest edge.
    val selected = state.cells.firstOrNull { it.isSelected }
    LaunchedEffect(selected?.row, selected?.col, side) {
        val cell = selected ?: return@LaunchedEffect
        val sidePx = with(density) { side.dp.toPx() }
        fun centre(index: Int, viewport: Int, max: Int): Int =
            ((index + 0.5f) * sidePx - viewport / 2f).roundToInt().coerceIn(0, maxOf(max, 0))
        scope.launch {
            val x = centre(cell.col, horizontal.viewportSize, horizontal.maxValue)
            val y = centre(cell.row, vertical.viewportSize, vertical.maxValue)
            if (reduceMotion) {
                horizontal.scrollTo(x); vertical.scrollTo(y)
            } else {
                horizontal.animateScrollTo(x); vertical.animateScrollTo(y)
            }
        }
    }

    val amountPx = with(density) { SHAKE_AMOUNT.toPx() }
    Box(
        Modifier
            .fillMaxSize()
            .pointerInput(fitSide) {
                detectTransformGestures { _, _, zoom, _ ->
                    side = (side * zoom).coerceIn(fitSide.value, MAX_ZOOM_SIDE)
                }
            }
            .verticalScroll(vertical)
            .horizontalScroll(horizontal),
    ) {
        GridRows(
            state = state,
            flashing = flashing,
            side = side.dp,
            onTapCell = onTapCell,
            reduceMotion = reduceMotion,
            modifier = Modifier.graphicsLayer { translationX = shakeOffset(amountPx) },
        )
    }
}

@Composable
private fun GridRows(
    state: GameUiState,
    flashing: Set<GridPos>,
    side: Dp,
    onTapCell: (GridPos) -> Unit,
    reduceMotion: Boolean,
    modifier: Modifier = Modifier,
) {
    Column(modifier) {
        for (r in 0 until state.size) {
            Row {
                for (c in 0 until state.size) {
                    val cell = state.cell(r, c)
                    CrosswordCell(
                        cell = cell,
                        side = side,
                        flash = GridPos(r, c) in flashing,
                        reduceMotion = reduceMotion,
                        onTap = { onTapCell(GridPos(r, c)) },
                    )
                }
            }
        }
    }
}

/**
 * A single cell. Every parameter is stable, so Compose skips cells whose
 * visual inputs are unchanged — the keystroke-latency guarantee.
 */
@Composable
private fun CrosswordCell(
    cell: CellUi,
    side: Dp,
    flash: Boolean,
    reduceMotion: Boolean,
    onTap: () -> Unit,
) {
    val colors = BccTheme.colors
    if (cell.isBlock) {
        // Blocks are invisible: on these sparse criss-cross grids the word
        // slots float on the background instead of sitting in a black slab.
        Box(Modifier.size(side).clearAndSetSemantics { })
        return
    }

    val errorVisible = cell.showError && cell.letter != null && !cell.isCorrect
    val correctVisible = cell.showCorrect && cell.letter != null && cell.isCorrect
    val fill = colors.cellFill(cell.isSelected, cell.isInWord, errorVisible, correctVisible)
    val flashAlpha by animateFloatAsState(if (flash) 0.5f else 0f, tween(if (flash) 180 else 300), label = "flash")
    val letterScale by animateFloatAsState(
        targetValue = if (flash && !reduceMotion) 1.18f else 1f,
        animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMedium),
        label = "letterScale",
    )

    val label = buildString {
        append("Row ${cell.row + 1}, Column ${cell.col + 1}")
        val letter = cell.letter
        if (letter == null) append(", empty") else {
            append(", ")
            append(if (cell.isPencil) "$letter, pencilled in" else "$letter")
            if (errorVisible) append(", incorrect")
            if (correctVisible) append(", correct")
        }
    }

    Box(
        Modifier
            .size(side)
            .background(fill)
            .drawBehind {
                if (flashAlpha > 0f) drawRect(FLASH_GREEN.copy(alpha = flashAlpha), size = Size(size.width, size.height))
                val stroke = 0.5.dp.toPx()
                drawRect(color = colors.separator, topLeft = Offset.Zero, size = size, style = androidx.compose.ui.graphics.drawscope.Stroke(stroke))
            }
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onTap,
            )
            .semantics {
                contentDescription = label
                selected = cell.isSelected
            },
    ) {
        cell.number?.let { number ->
            Text(
                text = "$number",
                fontSize = (side.value * 0.26f).sp,
                fontWeight = FontWeight.Medium,
                color = if (cell.isSelected) Color.White.copy(alpha = 0.9f) else colors.secondaryLabel,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(start = side * 0.07f, top = side * 0.04f),
            )
        }
        cell.letter?.let { letter ->
            // A pencilled letter reads as handwriting-in-the-margin: smaller,
            // lighter and grey, so the eye keeps parsing pen letters as the grid.
            Text(
                text = letter.toString(),
                fontSize = (side.value * if (cell.isPencil) 0.42f else 0.5f).sp,
                fontWeight = if (cell.isPencil) FontWeight.Normal else FontWeight.SemiBold,
                color = colors.cellText(cell.isSelected, cell.isPencil),
                modifier = Modifier
                    .align(Alignment.Center)
                    .graphicsLayer { scaleX = letterScale; scaleY = letterScale },
            )
        }
    }
}

private const val ZOOM_THRESHOLD = 15
private const val MAX_ZOOM_SIDE = 44f
private const val COMFORTABLE_SIDE = 30f
private val SHAKE_AMOUNT = 5.dp
private val FLASH_GREEN = Color(0xFF34C759)
