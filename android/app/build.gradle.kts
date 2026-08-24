plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase configuration (reads google-services.json for Auth, etc.).
    id("com.google.gms.google-services")
}

android {
    namespace = "com.ziadelsewedy.zivo"
    // image_cropper's AndroidX deps (exifinterface, annotation-experimental)
    // require compiling against API 34+. compileSdk only enables newer APIs at
    // compile time; targetSdk/minSdk below are intentionally left as-is.
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.ziadelsewedy.zivo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // firebase_auth requires a minimum of API 23. spotify_sdk's own
        // plugin (android/build.gradle) only requires 21, already covered.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Required by com.spotify.android:auth (spotify_sdk's dependency)
        // for its internal redirect activity — see spotify_sdk's CHANGELOG
        // (3.0.0-dev.1) and lib/features/music/data/spotify_music_controller.dart.
        // Unrelated to our own zivo:// redirect scheme (Info.plist / this
        // app's own manifest below) — these are the library's fixed values.
        manifestPlaceholders["redirectSchemeName"] = "spotify-sdk"
        manifestPlaceholders["redirectHostName"] = "auth"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Flutter's release build type minifies/shrinks by default (R8) —
            // debug builds never exercise this, which is why the Spotify App
            // Remote AAR's missing-class references (proguard-rules.pro) only
            // broke `flutter build apk --release`, not the debug build.
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
