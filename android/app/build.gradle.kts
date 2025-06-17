plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") version "4.4.2" apply false
}


android {
    ndkVersion = "27.0.12077973" // Ensure correct NDK version (You can update this if necessary)
    namespace = "com.example.resqlink"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        // Use Java 11 instead of Java 8
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    
    kotlinOptions {
        jvmTarget = "11" // Ensure Kotlin is compatible with Java 8
    }

   defaultConfig {
        applicationId = "com.example.resqlink"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Enable Java 8 desugaring
    compileOptions {
        isCoreLibraryDesugaringEnabled = true // Enable core library desugaring
    }
}

dependencies {
    // Update core library desugaring to version 2.1.4 or above
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation(platform("com.google.firebase:firebase-bom:33.15.0"))
    implementation("com.google.firebase:firebase-analytics")
}

flutter {
    source = "../.."
}
