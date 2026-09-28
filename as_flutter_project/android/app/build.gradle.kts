import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Google Services plugin for Firebase
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

// Helper: prefer environment variables (set in CI or server) and fall back to key.properties values
fun envOrProp(envKey: String, propKey: String?): String? {
    val envVal = System.getenv(envKey)
    if (!envVal.isNullOrBlank()) return envVal
    return propKey?.let { keystoreProperties[it] as String? }
}

android {
    namespace = "com.astralminds"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
        // Create a release config that reads from environment variables first.
        // Set the following env vars in CI or on the signing machine:
        // KEY_ALIAS, KEY_PASSWORD, KEYSTORE_PATH, KEYSTORE_PASSWORD
        create("release") {
            keyAlias = envOrProp("KEY_ALIAS", "keyAlias")
            keyPassword = envOrProp("KEY_PASSWORD", "keyPassword")
            val storeFilePath = envOrProp("KEYSTORE_PATH", "storeFile")
            storeFile = storeFilePath?.let { file(it) }
            storePassword = envOrProp("KEYSTORE_PASSWORD", "storePassword")
        }
    }

    defaultConfig {
        // Unique Application ID for production
        applicationId = "com.astralminds"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion  // Required for Firebase plugins
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true  // Required for Firebase
    }

    buildTypes {
        release {
            signingConfig = if (signingConfigs.findByName("release") != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Firebase dependencies
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.android.gms:play-services-auth:20.7.0")
    
    // MultiDex support
    implementation("androidx.multidex:multidex:2.0.1")
}
