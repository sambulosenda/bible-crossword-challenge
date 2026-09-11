package com.sambulosendas1.biblecrossword.data.content

import android.content.Context
import com.sambulosendas1.biblecrossword.data.di.ApplicationScope
import com.sambulosendas1.biblecrossword.domain.content.Bible
import com.sambulosendas1.biblecrossword.domain.content.ContentJson
import com.sambulosendas1.biblecrossword.domain.content.PuzzleCatalogue
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Loads the shared content files from assets — the iOS `Resources/` directory
 * mapped straight in, so there is one copy of every puzzle in the repo.
 *
 * The catalogue (puzzles, packs, quests; ~900 KB) is decoded once, eagerly,
 * off the main thread from process start. The Bible (4.6 MB) is decoded
 * **lazily** on first request, also off-main — never at launch. Mirrors iOS
 * `PuzzleProvider` + `ScriptureProvider.preload`.
 */
@Singleton
class ContentRepository @Inject constructor(
    @ApplicationContext private val context: Context,
    @ApplicationScope scope: CoroutineScope,
) {
    private val catalogueDeferred: Deferred<PuzzleCatalogue> = scope.async(Dispatchers.IO) {
        PuzzleCatalogue(
            allPuzzles = ContentJson.puzzles(read("puzzles.json")),
            packs = readOrNull("packs.json")?.let(ContentJson::packs) ?: emptyList(),
            quests = readOrNull("quests.json")?.let(ContentJson::quests) ?: emptyList(),
        )
    }

    private val bibleDeferred: Deferred<Bible> = scope.async(Dispatchers.IO, start = CoroutineStart.LAZY) {
        ContentJson.bible(read("bsb.json"))
    }

    suspend fun catalogue(): PuzzleCatalogue = catalogueDeferred.await()

    /** Kicks the decode off without waiting — call from a screen that will need it soon. */
    fun preloadBible() { bibleDeferred.start() }

    suspend fun bible(): Bible = bibleDeferred.await()

    private fun read(name: String): String =
        context.assets.open(name).bufferedReader().use { it.readText() }

    /** A missing optional file is not an error — the feature degrades to absent, as on iOS. */
    private fun readOrNull(name: String): String? = runCatching { read(name) }.getOrNull()
}
