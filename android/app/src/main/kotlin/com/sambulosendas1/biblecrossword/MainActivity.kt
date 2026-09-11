package com.sambulosendas1.biblecrossword

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.sambulosendas1.biblecrossword.data.content.ContentRepository
import com.sambulosendas1.biblecrossword.data.prefs.AppPrefs
import com.sambulosendas1.biblecrossword.ui.theme.BccTheme
import com.sambulosendas1.biblecrossword.ui.theme.Kicker
import com.sambulosendas1.biblecrossword.ui.theme.Spacing
import com.sambulosendas1.biblecrossword.ui.theme.scripture
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    @Inject lateinit var prefs: AppPrefs
    @Inject lateinit var content: ContentRepository

    override fun onCreate(savedInstanceState: Bundle?) {
        // The splash is the hydration barrier: nothing below it renders until
        // DataStore has produced a real Prefs, so theme and first-destination
        // reads are synchronous and there is never a one-frame flicker.
        installSplashScreen().setKeepOnScreenCondition { !prefs.isReady }
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val current by prefs.state.collectAsStateWithLifecycle()
            // P1 proof: the catalogue and the 4.6 MB Bible decode off-main,
            // after first frame, and the UI stays responsive meanwhile.
            var summary by remember { mutableStateOf("") }
            LaunchedEffect(Unit) {
                val catalogue = content.catalogue()
                val bible = content.bible()
                val verses = bible.books.sumOf { b -> b.chapters.sumOf { it.verses.size } }
                summary = getString(R.string.content_summary, catalogue.totalPuzzleCount, bible.books.size, verses)
            }
            BccTheme(appTheme = current.appTheme) {
                val colors = BccTheme.colors
                Column(
                    modifier = Modifier.fillMaxSize().background(colors.background).padding(Spacing.l),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Kicker(getString(R.string.today_kicker))
                    Text(
                        text = getString(R.string.app_name),
                        style = scripture(34, FontWeight.SemiBold),
                        color = colors.label,
                    )
                    Text(
                        text = getString(R.string.placeholder_verse),
                        style = scripture(19),
                        color = colors.secondaryLabel,
                        modifier = Modifier.padding(top = Spacing.m),
                    )
                    Text(
                        text = summary.ifEmpty { getString(R.string.content_loading) },
                        color = colors.secondaryLabel,
                        modifier = Modifier.padding(top = Spacing.l),
                    )
                }
            }
        }
    }
}
