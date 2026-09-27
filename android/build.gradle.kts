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
// AGP 9 sprawdza metadane AAR także w modułach wtyczek: file_picker 8.x
// kompiluje się na android-34, a flutter_plugin_android_lifecycle wymaga 36.
// compileSdk wtyczki podnosimy do 36 (to tylko wersja API do kompilacji —
// minSdk i targetSdk wtyczki się nie zmieniają). Zdjąć po aktualizacji
// file_picker do wersji z compileSdk >= 36.
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android")
        if (android is com.android.build.api.dsl.LibraryExtension) {
            val current = android.compileSdk ?: 0
            if (current < 36) android.compileSdk = 36
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
