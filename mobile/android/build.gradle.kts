allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// إصلاح توافق: بعض الإضافات تعلن compileSdk = 37 مجرداً، بينما
// جوجل لا تنشر منصة اسمها "android-37" إطلاقاً — تنشر android-37.0
// و37.1 بعد أن صارت الإصدارات تحمل رقماً فرعياً. فيفشل البناء بـ
// "Failed to find target with hash string 'android-37'" على جهاز
// عليه المنصة فعلاً.
//
// نضبط الرقم الفرعي صفراً لكل إضافة أعلنت 37، بدل إنزالها إلى 36:
// الإضافة اختارت 37 لسبب، وخفضها قد يمنعها من رؤية واجهات تستعملها.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { android ->
            val compileSdk = android.javaClass.methods
                .firstOrNull { it.name == "getCompileSdk" }
                ?.invoke(android) as? Int
            if (compileSdk == 37) {
                android.javaClass.methods
                    .firstOrNull { it.name == "setCompileSdkMinor" }
                    ?.invoke(android, 0)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}


tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
