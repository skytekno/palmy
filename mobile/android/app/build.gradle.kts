plugins { id("com.android.application"); id("org.jetbrains.kotlin.plugin.compose") }

android {
    namespace = "com.palmy.app"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.palmy.app"
        minSdk = 28
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "com.palmy.app.LifecycleTestRunner"
    }
    buildFeatures { compose = true; buildConfig = true }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    buildTypes {
        debug { buildConfigField("String", "DEFAULT_API_URL", "\"http://10.0.2.2:8100/api/v1\"") }
        release {
            isMinifyEnabled = false
            val endpoint = providers.gradleProperty("PALMY_API_URL").orElse("").get()
            require(endpoint.isEmpty() || endpoint.startsWith("https://") && !endpoint.contains('"') && !endpoint.contains('\\')) { "PALMY_API_URL must be HTTPS" }
            buildConfigField("String", "DEFAULT_API_URL", "\"$endpoint\"")
        }
    }
    testOptions { unitTests.all { it.systemProperty("palmy.repo", rootProject.projectDir.parentFile.parentFile.absolutePath) } }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.03.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.12.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("org.bouncycastle:bcprov-jdk18on:1.86")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.code.gson:gson:2.13.2")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")
    androidTestImplementation("androidx.test:core-ktx:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    debugImplementation("androidx.compose.ui:ui-tooling")
}
