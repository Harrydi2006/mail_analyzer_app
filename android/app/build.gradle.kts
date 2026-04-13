import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

val localSecretProps = Properties().apply {
    val f = rootProject.file("gradle.local.properties")
    if (f.exists()) {
        f.inputStream().use { load(it) }
    }
}

fun secretProp(name: String): String {
    val fromProject = project.findProperty(name)?.toString()?.trim()
    if (!fromProject.isNullOrEmpty()) return fromProject
    val fromLocal = localSecretProps.getProperty(name)?.trim()
    if (!fromLocal.isNullOrEmpty()) return fromLocal
    return ""
}

android {
    namespace = "com.harrydi.mail_analyzer_app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.harrydi.mail_analyzer_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["PUSH_APPID"] = secretProp("GETUI_APP_ID")
        manifestPlaceholders["PUSH_APPKEY"] = secretProp("GETUI_APP_KEY")
        manifestPlaceholders["PUSH_APPSECRET"] = secretProp("GETUI_APP_SECRET")
    }

    buildTypes {
        debug {
            // Workaround for occasional symbol strip temp-file race on Windows.
            ndk {
                debugSymbolLevel = "NONE"
            }
        }
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("com.getui:gtsdk:3.3.13.0")
    implementation("com.getui:gtc:3.1.10.0")
}
