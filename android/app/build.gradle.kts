import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter plugin must be applied last
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.yourdomain.stacktracker" // ✅ Your app's package name
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    // 🔐 Load keystore credentials
    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties().apply {
        if (keystorePropertiesFile.exists()) {
            load(FileInputStream(keystorePropertiesFile))
        } else {
            println("⚠️ Warning: key.properties file not found. Release build may fail without signing config.")
        }
    }

    signingConfigs {
        create("release") {
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
        }
    }

    defaultConfig {
    applicationId = "com.yourdomain.stacktracker"
    minSdk = flutter.minSdkVersion
    targetSdk = flutter.targetSdkVersion
    versionCode = 10 // 👈 Increment this!
    versionName = "1.0.10" // 👈 Optional, but good practice
}

    buildTypes {
        getByName("release") {
            isMinifyEnabled = true           // ✅ Enable to reduce size
            isShrinkResources = true         // ✅ Remove unused resources
            isDebuggable = false             // ✅ Ensure not debuggable in release
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // 🧩 Prevent install issues with AAB on Play
    bundle {
        density {
            enableSplit = false
        }
        abi {
            enableSplit = false
        }
        language {
            enableSplit = false
        }
    }
}

flutter {
    source = "../.."
}
