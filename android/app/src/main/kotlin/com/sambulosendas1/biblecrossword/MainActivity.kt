package com.sambulosendas1.biblecrossword

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.sambulosendas1.biblecrossword.data.content.ContentRepository
import com.sambulosendas1.biblecrossword.data.prefs.AppPrefs
import com.sambulosendas1.biblecrossword.domain.content.Puzzle
import com.sambulosendas1.biblecrossword.game.GameScreen
import com.sambulosendas1.biblecrossword.ui.haptics.LocalHaptics
import com.sambulosendas1.biblecrossword.ui.haptics.rememberHaptics
import com.sambulosendas1.biblecrossword.ui.theme.BccTheme
import dagger.hilt.android.AndroidEntryPoint
import java.time.LocalDate
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
            // P3 harness: today's Mini, straight into the solve loop. The tab
            // shell and Today screen arrive in P4.
            var puzzle by remember { mutableStateOf<Puzzle?>(null) }
            LaunchedEffect(Unit) {
                puzzle = content.catalogue().dailyMini(LocalDate.now())
            }
            BccTheme(appTheme = current.appTheme) {
                CompositionLocalProvider(LocalHaptics provides rememberHaptics()) {
                    val loaded = puzzle
                    if (loaded == null) {
                        Box(Modifier.fillMaxSize().background(BccTheme.colors.background), Alignment.Center) {
                            Text(getString(R.string.content_loading), color = BccTheme.colors.secondaryLabel)
                        }
                    } else {
                        GameScreen(puzzle = loaded)
                    }
                }
            }
        }
    }
}
