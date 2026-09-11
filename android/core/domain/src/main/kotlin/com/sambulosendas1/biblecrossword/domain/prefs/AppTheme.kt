package com.sambulosendas1.biblecrossword.domain.prefs

/**
 * User-selectable appearance, persisted under the `appTheme` preference and
 * applied at the app root. Mirrors iOS `AppTheme` in `Theme/Theme.swift`.
 */
enum class AppTheme(val rawValue: String, val label: String) {
    SYSTEM("system", "System"),
    LIGHT("light", "Light"),
    DARK("dark", "Dark");

    companion object {
        fun fromRaw(raw: String?): AppTheme = entries.firstOrNull { it.rawValue == raw } ?: SYSTEM
    }
}
