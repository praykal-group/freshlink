import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (Section 11): android/key.properties (gitignored) points to the upload keystore
// OUTSIDE the repo. CI writes it from ANDROID_KEYSTORE_* secrets. Without it, release builds are
// signed with the debug key and the build prints a warning: such APKs are for local testing only
// and can never update an installed production app.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = listOf("storeFile", "storePassword", "keyAlias", "keyPassword").all { !keyProps.getProperty(it).isNullOrBlank() }

android {
    namespace = "in.iccms.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications needs java.time on Android 8–13.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Android 8+ (DA-NFR / FO-NFR)
        minSdk = maxOf(26, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Package only the ABIs Flutter builds for (`flutter build/run --target-platform`, passed
        // as -Ptarget-platform). The Flutter plugin otherwise sets arm + arm64 + x86_64, so plugin
        // AARs ship x86_64 libraries in arm-only release APKs (ML Kit's barcode engine: 5.6 MB).
        // `flutter run` on an x86_64 emulator passes android-x64 and keeps working (D-140).
        val abiOf = mapOf("android-arm" to "armeabi-v7a", "android-arm64" to "arm64-v8a", "android-x64" to "x86_64")
        val targetAbis = (project.findProperty("target-platform") as String?)
            ?.split(",")?.mapNotNull { abiOf[it.trim()] }.orEmpty()
        if (targetAbis.isNotEmpty()) {
            ndk {
                abiFilters.clear()
                abiFilters.addAll(targetAbis)
            }
        }
    }

    // AGP 9 turns resValue() off by default; the flavors use it for their app_name.
    buildFeatures {
        resValues = true
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    // One codebase, three APKs (Section 11). Each flavor has its own id, name, icon and manifest.
    flavorDimensions += "app"
    productFlavors {
        create("driver") {
            dimension = "app"
            applicationId = "in.iccms.driver"
            resValue("string", "app_name", "I-CCMS Driver")
        }
        create("operator") {
            dimension = "app"
            applicationId = "in.iccms.operator"
            resValue("string", "app_name", "I-CCMS Operator")
        }
        create("manager") {
            dimension = "app"
            applicationId = "in.iccms.manager"
            resValue("string", "app_name", "I-CCMS Control Tower")
        }
    }

    buildTypes {
        release {
            if (hasReleaseKey) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                logger.warn("WARNING: android/key.properties not found - release APKs are signed with the DEBUG key (local testing only).")
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
