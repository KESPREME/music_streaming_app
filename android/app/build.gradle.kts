import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

// RELEASE SIGNING
//
// Android only installs an update over an app signed with the SAME key, so the
// key CI signs with is the identity of the app for as long as it is installed.
// It is read from android/key.properties (local builds) or from environment
// variables (CI, which writes the keystore from a secret):
//
//   storeFile / ANDROID_KEYSTORE_PATH       path to the .jks
//   storePassword / ANDROID_KEYSTORE_PASSWORD
//   keyAlias / ANDROID_KEY_ALIAS
//   keyPassword / ANDROID_KEY_PASSWORD
//
// With none of them a local 'flutter build apk --release' still works, signed
// with the debug key. CI sets REQUIRE_RELEASE_SIGNING=true so that it can never
// publish an update signed with a key the installed app will reject.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) FileInputStream(file).use { load(it) }
}

fun signingValue(property: String, env: String): String? =
    (keyProperties.getProperty(property) ?: System.getenv(env))?.takeIf { it.isNotBlank() }

android {
    namespace = "com.example.music_streaming_app"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_1_8.toString()
    }

    defaultConfig {
        applicationId = "com.example.music_streaming_app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val path = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")
            if (path != null) {
                storeFile = file(path)
                storePassword = signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            val release = signingConfigs.getByName("release")
            signingConfig = if (release.storeFile != null) {
                release
            } else {
                if (System.getenv("REQUIRE_RELEASE_SIGNING") == "true") {
                    throw GradleException(
                        "Release signing is required but no keystore was provided. " +
                            "Set the ANDROID_KEYSTORE_* secrets (see docs/RELEASING.md)."
                    )
                }
                signingConfigs.getByName("debug")
            }
        }
    }

    lint {
        checkReleaseBuilds = false
        disable += "InvalidPackage"
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:33.11.0"))
    implementation("com.google.firebase:firebase-firestore")
}

