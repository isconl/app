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
// BN26082504: file_picker 8.3.7's own android/build.gradle hardcodes
// compileSdk 34 INSIDE its `android {}` block, which runs after plugin
// application -- a plugins.withType hook fires too early and gets
// overwritten back to 34 by that later line. afterEvaluate runs after the
// module's own script finishes, so it wins -- but registering it on ":app"
// itself throws "already evaluated" (evaluationDependsOn below forces some
// other subproject to fully evaluate :app early, before root's own
// subprojects{} iteration reaches :app). ":app" already sets its own
// compileSdk directly in app/build.gradle.kts, so it's excluded here.
subprojects {
    if (project.name != "app") {
        afterEvaluate {
            extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.let { ext ->
                val current = ext.compileSdkVersion?.removePrefix("android-")?.toIntOrNull() ?: 0
                if (current in 1..35) {
                    ext.compileSdkVersion("android-36")
                }
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
