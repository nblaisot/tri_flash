group = "com.triflash.on_device_ai"
version = "1.0-SNAPSHOT"

plugins {
    id("com.android.library")
    id("kotlin-android")
}

android {
    namespace = "com.triflash.on_device_ai"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
        }
    }

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }

    defaultConfig {
        minSdk = 26
    }
}

dependencies {
    implementation("com.google.mlkit:genai-prompt:1.0.0-beta4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}
