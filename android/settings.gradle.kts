pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "BibleCrossword"

include(":app")
// Plain JVM: the engine and every rule, testable against spec/vectors without
// an emulator. Android-facing modules (:core:data, :core:share, :feature:*)
// arrive in P1+.
include(":core:domain")
// Android-facing: Room + DataStore behind the domain types.
include(":core:data")
// Compose theme tokens and shared components.
include(":core:ui")
