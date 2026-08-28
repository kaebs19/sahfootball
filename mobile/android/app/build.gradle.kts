plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.sahfootball.app"
    // 37 لا flutter.compileSdkVersion (=36): إضافة flutter_secure_storage
    // تشترط على من يعتمد عليها الترجمة على 37 أو أحدث. والرقم الفرعي
    // صريح لأن جوجل تنشر android-37.0 لا "android-37"، فالرقم المجرد
    // يبحث عن منصة غير موجودة.
    //
    // هذا لا يغيّر أقل نسخة مدعومة ولا النسخة المستهدفة — الترجمة على
    // واجهات أحدث لا تعني اشتراطها على الأجهزة.
    compileSdk = 37
    compileSdkMinor = 0
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.sahfootball.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // BoM (Bill of Materials): نثبّت رقم إصدار واحداً وتشتق منه
    // بقية مكتبات Firebase نسخها المتوافقة. البديل — رقم لكل
    // مكتبة — يصنع تعارضات وقت التشغيل يصعب تتبعها.
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    // الرسائل وحدها. لا analytics ولا crashlytics: كل مكتبة تُضاف
    // هنا تكبّر حجم التطبيق وتوسّع ما نجمعه عن المستخدم، وسياسة
    // الخصوصية عندنا تقول صراحة "لا تتبّع إعلاني".
    implementation("com.google.firebase:firebase-messaging")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
