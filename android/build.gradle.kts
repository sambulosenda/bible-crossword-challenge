// AGP 9 compiles Kotlin itself (built-in Kotlin); org.jetbrains.kotlin.android
// must NOT be applied to Android modules. It is declared here, apply false, so
// the Kotlin version it names is on the classpath for AGP and the compose /
// serialization compiler plugins.
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.ksp) apply false
    alias(libs.plugins.hilt) apply false
}
