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

// tflite_flutter (and possibly other plugins) hardcode Java 11
// sourceCompatibility in their own build.gradle while Flutter's shared Kotlin
// support compiles Kotlin tasks against the toolchain JDK's version, causing
// a "Inconsistent JVM Target Compatibility Between Java and Kotlin Tasks"
// Gradle failure. Force every subproject's Java compile target to match, so
// this app can be built without patching third-party plugin sources.
project(":tflite_flutter") {
    val configureJvmTarget: () -> Unit = {
        tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
        }
    }
    if (state.executed) configureJvmTarget() else afterEvaluate { configureJvmTarget() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
