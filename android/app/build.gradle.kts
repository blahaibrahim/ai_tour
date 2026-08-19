plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Applied only when the Firebase config is actually present.
//
// The google-services plugin fails the build outright if google-services.json
// is missing, and that file is credentials — it is not in the repository, and
// it does not exist at all until someone runs `flutterfire configure`. Listing
// it in the `plugins` block above would therefore break `flutter build` for
// every checkout that has not done so, including CI. Applying it conditionally
// means the app builds either way and simply comes up with push disabled:
// `NotificationService._initFirebase` catches the missing configuration and
// falls back to local-only notifications.
//
// See docs/backend/15-notifications-and-fcm.md.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.massar.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications, which uses java.time APIs
        // the platform only provides from API 26. Without it the build fails
        // at dexing with an unresolved java.time reference, not at compile.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.massar.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // ar_flutter_plugin_2 (via sceneview/ARCore) requires API 28. That is
        // also roughly the floor for ARCore-capable devices, so nothing that
        // could run the mascot hunt is being excluded.
        minSdk = maxOf(flutter.minSdkVersion, 28)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("release") {
            // Change "release" to "debug" here:
            signingConfig = signingConfigs.getByName("debug")
            
            // Keep our ProGuard rule:
            proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

// google_mlkit_image_labeling pulls in com.google.mlkit:linkfirebase, which
// still depends on the legacy com.google.firebase:firebase-iid:20.1.5. That
// artifact's FirebaseInstanceIdReceiver was folded into firebase-messaging
// from v22, so having both on the classpath fails the build outright at
// :app:checkDebugDuplicateClasses with a duplicate class error.
//
// firebase-iid is dead code here either way: `linkfirebase` exists for ML Kit
// models hosted on Firebase, and this app only does on-device image labeling.
// firebase_messaging supplies the modern replacement (FirebaseMessaging.getToken).
configurations.all {
    exclude(group = "com.google.firebase", module = "firebase-iid")
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
