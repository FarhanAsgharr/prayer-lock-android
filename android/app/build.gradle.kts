plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.prayerlock.prayer_lock"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications, which uses java.time to
        // schedule exact alarms. Desugaring back-ports those APIs to the older
        // Android versions we still support.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.prayerlock.prayer_lock"
        // API 24 (Android 7). Below this, the notification and exact-alarm
        // behaviour the product depends on is unavailable or unreliable.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signed with the debug key so `flutter run --release` works during
            // development. Replace with a real upload key before publishing:
            // see docs/RELEASE.md for the keystore setup.
            signingConfig = signingConfigs.getByName("debug")

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Back-ports java.time for flutter_local_notifications on older Android.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // WorkManager runs the periodic repair job that re-arms the prayer alarm
    // chain. It is the only scheduling primitive Android persists across
    // reboots, app updates and force-stops, which is exactly the set of events
    // that would otherwise leave blocking silently dead.
    implementation("androidx.work:work-runtime-ktx:2.9.1")

    // JVM unit tests for the blocking logic. These run without an emulator,
    // so the emergency-allowlist safety checks execute on every build rather
    // than only during instrumented test runs.
    testImplementation("junit:junit:4.13.2")
}
