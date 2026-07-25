import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is configured entirely through android/key.properties, which
// is git-ignored and never committed. When that file is present the release
// build is signed with the real upload key; when it is absent — a fresh clone,
// CI without secrets, a developer running `flutter run --release` — the build
// falls back to the debug key so nothing breaks.
//
// Switching from debug to release signing therefore requires no code change:
// create the keystore, fill in the four values in key.properties, and rebuild.
// See docs/RELEASE_SIGNING.md for the exact commands.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
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

    signingConfigs {
        // Only declared when key.properties exists. Referencing a keystore that
        // is not there would fail every build, including debug builds and CI,
        // so the config is created conditionally and the release build picks it
        // up only when it is real.
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = keystoreProperties["KEYSTORE_FILE"]?.let { file(it) }
                storePassword = keystoreProperties["KEYSTORE_PASSWORD"] as String?
                keyAlias = keystoreProperties["KEY_ALIAS"] as String?
                keyPassword = keystoreProperties["KEY_PASSWORD"] as String?
            }
        }
    }

    buildTypes {
        release {
            // The real upload key when key.properties is present, the debug key
            // otherwise. The debug fallback keeps `flutter run --release` and
            // secret-less CI working; the release key is used the moment the
            // four values in key.properties are filled in — no code change.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

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
