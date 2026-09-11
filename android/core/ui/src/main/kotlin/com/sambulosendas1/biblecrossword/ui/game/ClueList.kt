package com.sambulosendas1.biblecrossword.ui.game

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sambulosendas1.biblecrossword.domain.engine.Slot
import com.sambulosendas1.biblecrossword.ui.theme.BccTheme
import com.sambulosendas1.biblecrossword.ui.theme.Kicker
import com.sambulosendas1.biblecrossword.ui.theme.Spacing

/**
 * The full Across/Down list. Tapping a clue selects it on the grid.
 *
 * This is also where a solved clue names the passage its answer comes from.
 * The clue bar and the grid deliberately don't: they are the solving surface,
 * and a reference there is a hint. Here, after the solve, the same line is a
 * reward.
 */
@Composable
fun ClueList(
    across: List<Slot>,
    down: List<Slot>,
    activeSlotId: String?,
    isSolved: (Slot) -> Boolean,
    onSelect: (Slot) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = BccTheme.colors
    val listState = rememberLazyListState()

    // Land on the clue you were working — the list can be long.
    LaunchedEffect(Unit) {
        val index = indexOf(activeSlotId, across, down)
        if (index >= 0) listState.scrollToItem(index)
    }

    LazyColumn(state = listState, modifier = modifier.background(colors.background)) {
        section("Across", across, activeSlotId, isSolved, onSelect)
        section("Down", down, activeSlotId, isSolved, onSelect)
    }
}

private fun LazyListScope.section(
    title: String,
    slots: List<Slot>,
    activeSlotId: String?,
    isSolved: (Slot) -> Boolean,
    onSelect: (Slot) -> Unit,
) {
    item(key = "header-$title") {
        Kicker(title, Modifier.padding(horizontal = Spacing.m, vertical = Spacing.s))
    }
    items(slots.size, key = { "$title-${slots[it].id}" }) { i ->
        val slot = slots[i]
        ClueRow(slot, slot.id == activeSlotId, isSolved(slot), onSelect)
        HorizontalDivider(thickness = 0.5.dp)
    }
}

@Composable
private fun ClueRow(slot: Slot, isActive: Boolean, solved: Boolean, onSelect: (Slot) -> Unit) {
    val colors = BccTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .background(if (isActive) colors.accent.copy(alpha = 0.10f) else colors.surface)
            .clickable { onSelect(slot) }
            .padding(horizontal = Spacing.m, vertical = Spacing.s),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(Spacing.s),
    ) {
        Text(
            text = "${slot.number}",
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (isActive) colors.accent else colors.secondaryLabel,
            modifier = Modifier.width(NUMBER_COLUMN),
        )
        Column(Modifier.weight(1f)) {
            Text(
                text = slot.clue,
                fontSize = 15.sp,
                color = if (solved) colors.secondaryLabel else colors.label,
            )
            // The reference is the reward, so it only appears once the answer
            // is in. Starts under the clue text, not under its number.
            if (solved) {
                slot.reference?.let { reference ->
                    Text(
                        text = reference,
                        fontSize = 12.sp,
                        color = colors.accent,
                        modifier = Modifier.padding(top = Spacing.xs),
                    )
                }
            }
        }
    }
}

private fun indexOf(activeSlotId: String?, across: List<Slot>, down: List<Slot>): Int {
    if (activeSlotId == null) return -1
    val a = across.indexOfFirst { it.id == activeSlotId }
    if (a >= 0) return a + 1 // the Across header
    val d = down.indexOfFirst { it.id == activeSlotId }
    if (d >= 0) return across.size + 2 + d // both headers
    return -1
}

private val NUMBER_COLUMN = 24.dp
