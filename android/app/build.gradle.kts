plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.matrimpathak.ledger"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.matrimpathak.ledger"
        minSdk = 21
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.multidex:multidex:2.0.1")
    implementation("androidx.work:work-runtime-ktx:2.9.1")

    // Android-Keystore-backed encrypted storage for the Claude API key/uid
    // mirror the background SMS worker reads (see SecurePrefsStore.kt).
    implementation("androidx.security:security-crypto:1.1.0")

    // Firebase deps are declared 'implementation' in the Flutter plugins so they
    // are not transitively visible to the app module. Declare them here explicitly
    // so SmsProcessingWorker can compile against the Firestore and Firebase APIs.
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-firestore-ktx")
    implementation("com.google.firebase:firebase-common-ktx")

    // Provides kotlinx.coroutines.tasks.await() for Firebase Task<T> suspension.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.9.0")

    // JVM unit tests (android/app/src/test) for pure-Kotlin classes like
    // LocalSmsParser that don't touch the Android framework. org.json is
    // part of the Android platform at runtime (its real implementation is
    // provided by the OS, not this artifact) — the standalone "org.json:json"
    // artifact is API-compatible and needed so JSONObject/JSONArray actually
    // work under a plain JVM test runner instead of throwing "not mocked".
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
