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
subprojects {
    project.evaluationDependsOn(":app")
}

// Force every Android subproject (Flutter plugins included) to compile against
// at least API 36. A transitive plugin dependency
// (flutter_plugin_android_lifecycle) now requires compileSdk 36, but plugins
// inherit Flutter's lower default rather than the app module's own override in
// app/build.gradle.kts — so file_picker et al. fail the AAR metadata check.
// This only enables newer compile-time APIs; it does not touch any plugin's
// minSdk/targetSdk, i.e. no runtime behavior change. Done reflectively so it
// works whether the plugin uses the new AGP DSL (`compileSdk: Int`) or the
// legacy one (`compileSdkVersion(String)`), and only ever raises the level.
subprojects {
    val raiseCompileSdk = {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            val cls = androidExt.javaClass
            val getCompileSdk = runCatching { cls.getMethod("getCompileSdk") }.getOrNull()
            val setCompileSdk = runCatching {
                cls.getMethod("setCompileSdk", Integer::class.javaObjectType)
            }.getOrNull()
            if (getCompileSdk != null && setCompileSdk != null) {
                val current = getCompileSdk.invoke(androidExt) as? Int ?: 0
                if (current < 36) setCompileSdk.invoke(androidExt, 36)
            } else {
                // Legacy DSL fallback: `compileSdkVersion(String)`.
                runCatching { cls.getMethod("compileSdkVersion", String::class.java) }
                    .getOrNull()?.invoke(androidExt, "android-36")
            }
        }
    }
    // `:app` is force-evaluated early by the evaluationDependsOn above (and
    // already pins compileSdk 36 itself), so afterEvaluate would throw on it —
    // apply directly when a project is already evaluated, else defer.
    if (state.executed) raiseCompileSdk() else afterEvaluate { raiseCompileSdk() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
