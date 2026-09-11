package com.sambulosendas1.biblecrossword.data.di

import android.content.Context
import androidx.room.Room
import com.sambulosendas1.biblecrossword.data.db.AppDatabase
import com.sambulosendas1.biblecrossword.data.db.PlayerProfileDao
import com.sambulosendas1.biblecrossword.data.db.PuzzleRecordDao
import com.sambulosendas1.biblecrossword.data.prefs.AppPrefs
import com.sambulosendas1.biblecrossword.data.prefs.AppSignals
import com.sambulosendas1.biblecrossword.data.prefs.appPrefsDataStore
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import javax.inject.Qualifier
import javax.inject.Singleton

/** A scope that lives as long as the process — for eagerly-shared flows. */
@Qualifier
@Retention(AnnotationRetention.RUNTIME)
annotation class ApplicationScope

@Module
@InstallIn(SingletonComponent::class)
object DataModule {

    @Provides
    @Singleton
    @ApplicationScope
    fun applicationScope(): CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    @Provides
    @Singleton
    fun database(@ApplicationContext context: Context): AppDatabase =
        Room.databaseBuilder(context, AppDatabase::class.java, AppDatabase.NAME).build()

    @Provides
    fun playerProfileDao(db: AppDatabase): PlayerProfileDao = db.playerProfileDao()

    @Provides
    fun puzzleRecordDao(db: AppDatabase): PuzzleRecordDao = db.puzzleRecordDao()

    @Provides
    @Singleton
    fun appPrefs(@ApplicationContext context: Context, @ApplicationScope scope: CoroutineScope): AppPrefs =
        AppPrefs(context.appPrefsDataStore, scope)

    @Provides
    @Singleton
    fun appSignals(): AppSignals = AppSignals()
}
