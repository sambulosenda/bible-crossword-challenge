package com.sambulosendas1.biblecrossword

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
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
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.sambulosendas1.biblecrossword.data.content.ContentRepository
import com.sambulosendas1.biblecrossword.data.prefs.AppPrefs
import com.sambulosendas1.biblecrossword.domain.content.Puzzle
import com.sambulosendas1.biblecrossword.game.GameScreen
import com.sambulosendas1.biblecrossword.today.TodayScreen
import com.sambulosendas1.biblecrossword.ui.haptics.LocalHaptics
import com.sambulosendas1.biblecrossword.ui.haptics.rememberHaptics
import com.sambulosendas1.biblecrossword.ui.theme.BccTheme
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
            BccTheme(appTheme = current.appTheme) {
                CompositionLocalProvider(LocalHaptics provides rememberHaptics()) {
                    AppNavigation(content)
                }
            }
        }
    }
}

private object Routes {
    const val TODAY = "today"
    const val GAME = "game/{puzzleId}"
    fun game(puzzleId: String) = "game/$puzzleId"
}

/**
 * Today → Game. The tab shell (Packs, Library, Read, Profile) arrives with
 * those screens; routing them before they exist would be four empty tabs.
 */
@Composable
private fun AppNavigation(
    content: ContentRepository,
    navController: NavHostController = rememberNavController(),
) {
    NavHost(navController, startDestination = Routes.TODAY) {
        composable(Routes.TODAY) {
            TodayScreen(onPlay = { puzzle -> navController.navigate(Routes.game(puzzle.id)) })
        }
        composable(Routes.GAME) { entry ->
            val puzzleId = entry.arguments?.getString("puzzleId").orEmpty()
            var puzzle by remember(puzzleId) { mutableStateOf<Puzzle?>(null) }
            LaunchedEffect(puzzleId) { puzzle = content.catalogue().puzzle(puzzleId) }

            val loaded = puzzle
            if (loaded == null) {
                Box(Modifier.fillMaxSize().background(BccTheme.colors.background), Alignment.Center) {
                    CircularProgressIndicator(color = BccTheme.colors.accent)
                }
            } else {
                GameScreen(puzzle = loaded, onClose = { navController.popBackStack() })
            }
        }
    }
}
