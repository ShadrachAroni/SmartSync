plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    kotlin("android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.smartsync.smartsync_app"

    // Use Flutter properties injected by the Flutter Gradle plugin
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.smartsync.smartsync_app"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        
        // Ensure Select TF Ops native libraries are packaged
        ndk {
            // No need to specify abiFilters - include all architectures
            // The Select TF Ops library will be included automatically
        }
    }
    
    packaging {
        // Ensure all native libraries are included, including Select TF Ops
        jniLibs {
            useLegacyPackaging = false
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false 
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    
    // TensorFlow Lite Select TF Ops - required for models using TensorFlow ops (e.g., FlexConv2D)
    // This must match the TensorFlow Lite version used by tflite_flutter (2.15.0)
    implementation("org.tensorflow:tensorflow-lite-select-tf-ops:2.15.0")
}
