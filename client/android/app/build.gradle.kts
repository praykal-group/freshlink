plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "in.iccms.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Android 8+ (DA-NFR / FO-NFR)
        minSdk = maxOf(26, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // One codebase, three APKs (Section 11). Each flavor has its own id, name and manifest.
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
            // Release signing (key.properties) is added in M10.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
