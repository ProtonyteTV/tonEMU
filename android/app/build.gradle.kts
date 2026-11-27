import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) FileInputStream(f).use { load(it) }
}

android {
    namespace = "com.jedplatforms.jedEmu"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.jedplatforms.jedEmu"
        minSdk = 26 
        targetSdk = 36 
        versionCode = flutter.versionCode
        versionName = flutter.versionName // comes from `version:` in pubspec.yaml

        // NOTE: most 3DS/PSP cores only exist as arm64-v8a. Make sure every core you ship
        // is present in jniLibs/arm64-v8a, otherwise it can't be loaded on 64-bit devices.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    // Ensures .so core libraries are extracted properly on modern Android versions
    packaging {
        jniLibs {
            useLegacyPackaging = true
            excludes += setOf(
                "**/armeabi/**",
                "**/armeabi-v7a/**",
                "**/x86/**",
                "**/x86_64/**"
            )
        }
    }

    signingConfigs {
        create("release") {
            if (keystoreProps.isNotEmpty()) {
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
                storeFile = file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // Play rejects debug-signed uploads. Without key.properties the build still runs
            // (debug-signed, for local testing only) but warns loudly.
            signingConfig = if (keystoreProps.isNotEmpty()) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("WARNING: android/key.properties not found - release is DEBUG-signed and Play will reject it.")
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation(project(":libretrodroid"))
    // GameSession uses LifecycleRegistry directly
    implementation("androidx.lifecycle:lifecycle-runtime:2.8.7")
}

flutter {
    source = "../.."
}