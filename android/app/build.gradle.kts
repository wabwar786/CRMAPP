plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.smartcrm.smartcrm_project"

    compileSdk = 36  // ✅ Update to match plugin requirements
    ndkVersion = "28.2.13676358"  // ✅ Keep this or use 26.1.10909125 if needed

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
       applicationId = "com.smartcrm.smartcrm_project"

        minSdk = flutter.minSdkVersion
        targetSdk = 36  // ✅ Match compileSdk
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
    getByName("release") {
        signingConfig = signingConfigs.getByName("debug") // Or use your release keystore

        isMinifyEnabled = true
        isShrinkResources = true

        proguardFiles(
            getDefaultProguardFile("proguard-android-optimize.txt"),
            file("proguard-rules.pro")
        )
    }
}


}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.squareup.okhttp3:okhttp:4.12.0") // Add OkHttp
    // Add other dependencies if needed
}
