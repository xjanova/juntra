import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Load signing properties — present locally as `key.properties`, present
// in CI as the env vars decoded from ANDROID_KEYSTORE_BASE64.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// App Bundle (Google Play) builds must not carry the per-ABI APK splits below —
// Play cuts its own per-device APKs from the bundle.
val isBundleBuild = gradle.startParameter.taskNames.any { it.contains("bundle", ignoreCase = true) }

android {
    namespace = "com.xjanova.juntra"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.xjanova.juntra"
        minSdk = 26
        // Google Play requires the latest target API for new apps and updates —
        // Flutter's default tracks it (36 on Flutter 3.41).
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Two distribution channels built from the same code, same applicationId
    // and same signing key (so a phone can move from one to the other):
    //
    //   play   — Google Play (App Bundle). Updates come from Play, credits are
    //            bought through Google Play Billing. No self-update, no
    //            REQUEST_INSTALL_PACKAGES, no link to pay outside Google Play.
    //   direct — the APK on GitHub Releases for phones outside Play. Keeps the
    //            in-app self-updater and the PromptPay top-up.
    //
    // Dart reads the channel from `appFlavor` (lib/core/app_channel.dart).
    // `flutter run` without --flavor uses `default-flavor: play` in pubspec.yaml.
    flavorDimensions += "channel"
    productFlavors {
        create("play") {
            dimension = "channel"
        }
        create("direct") {
            dimension = "channel"
        }
    }

    signingConfigs {
        create("release") {
            if (keystoreProperties.isNotEmpty()) {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            // Use release signing if key.properties exists, otherwise fall
            // back to debug so `flutter run --release` works for devs.
            signingConfig = if (keystoreProperties.isNotEmpty()) {
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

    // Split per ABI for smaller sideload APKs. Universal APK is also produced
    // for the in-app updater. Off for App Bundles (see isBundleBuild).
    splits {
        abi {
            isEnable = !isBundleBuild
            reset()
            include("arm64-v8a", "armeabi-v7a", "x86_64")
            isUniversalApk = true
        }
    }
}

flutter {
    source = "../.."
}
