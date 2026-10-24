import org.gradle.api.tasks.Delete
import org.gradle.api.file.Directory
import org.gradle.kotlin.dsl.*

buildscript {
    val kotlin_version by extra("2.1.20")

    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://maven.google.com") }
    }
    dependencies {
        classpath("com.google.gms:google-services:4.4.2")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://maven.google.com") }
    }
}

// Custom build directory configuration for the root project
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.set(newBuildDir)

// Apply custom build directory only to the :app module
subprojects {
    if (project.name == "app") {
        val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
        project.layout.buildDirectory.set(newSubprojectBuildDir)
    }
}

// Add property to ignore JVM target validation issues
System.setProperty("kotlin.jvm.target.validation.mode", "IGNORE")

// Create a separate file for flutter_web_auth configuration
file("${rootProject.projectDir}/flutter_web_auth_fix.gradle").writeText("""
android {
    namespace "com.linusu.flutter_web_auth"
    
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }
}

tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile).configureEach {
    kotlinOptions {
        jvmTarget = "1.8"
    }
}
""")

// Apply the fix to the plugin
subprojects {
    afterEvaluate {
        if (project.name == "flutter_web_auth") {
            try {
                project.apply(from = "${rootProject.projectDir}/flutter_web_auth_fix.gradle")
            } catch (e: Exception) {
                println("Could not apply flutter_web_auth fix: ${e.message}")
            }
        }
    }

    project.evaluationDependsOn(":app")
}

// on_audio_query_android 1.1.0 predates AGP 8's mandatory namespace, so the CI
// release build stops while configuring that module:
//   "Namespace not specified. Specify a namespace in the module's build file"
// The patch is applied the moment com.android.library is added to THAT project
// only - before its own build file runs and long before AGP creates the library
// variant, which is where the check fires. No other module is touched.
subprojects {
    if (project.name == "on_audio_query_android") {
        project.pluginManager.withPlugin("com.android.library") {
            project.apply(from = "${rootProject.projectDir}/on_audio_query_android.gradle")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
