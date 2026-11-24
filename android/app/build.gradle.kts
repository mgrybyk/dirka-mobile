import javax.inject.Inject
import org.gradle.process.ExecOperations

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val unsignedRelease = providers.environmentVariable("DIRKA_UNSIGNED_RELEASE").orNull == "1"

android {
    namespace = "com.mgrybyk.dirka"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_25
        targetCompatibility = JavaVersion.VERSION_25
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mgrybyk.dirka"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 33
        targetSdk = 36
        ndk {
            abiFilters += "arm64-v8a"
        }
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Store keys stay out of Gradle. CI signs the unsigned APK with apksigner.
            if (!unsignedRelease) {
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_25
    }
}

flutter {
    source = "../.."
}

abstract class BuildDirkaNative : DefaultTask() {
    @get:InputFile
    abstract val buildScript: RegularFileProperty

    @get:Input
    abstract val ndkVersion: Property<String>

    @get:Input
    abstract val minSdk: Property<Int>

    @get:Internal
    abstract val ndkDirectory: DirectoryProperty

    @get:OutputDirectory
    abstract val libraries: DirectoryProperty

    @get:Inject
    abstract val execOperations: ExecOperations

    @TaskAction
    fun build() {
        execOperations.exec {
            commandLine(
                "bash",
                buildScript.get().asFile,
                ndkDirectory.get().asFile,
                libraries.get().asFile,
                minSdk.get(),
            )
        }
    }
}

val projectRoot = rootProject.layout.projectDirectory.dir("..")
val configuredNdkVersion = flutter.ndkVersion
val prepareDirkaUpstream by tasks.registering(Exec::class) {
    commandLine("bash", projectRoot.file("tool/fetch-upstream.sh").asFile)
}
androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        // Compress native libraries to reduce the size of the downloadable APK.
        variant.packaging.jniLibs.useLegacyPackaging.set(true)
    }
    val installedNdk = sdkComponents.ndkDirectory
    onVariants { variant ->
        val minAndroidSdk = variant.minSdk.apiLevel
        val taskName = "buildDirkaNative" + variant.name.replaceFirstChar { it.uppercaseChar() }
        val nativeBuild = tasks.register<BuildDirkaNative>(taskName) {
            dependsOn(prepareDirkaUpstream)
            buildScript.set(projectRoot.file("tool/build-android-native.sh"))
            ndkDirectory.set(installedNdk)
            ndkVersion.set(configuredNdkVersion)
            minSdk.set(minAndroidSdk)
            inputs.files(
                projectRoot.file("rust-toolchain.toml"),
                projectRoot.file("native/Cargo.toml"),
                projectRoot.file("native/Cargo.lock"),
                projectRoot.file("native/build.rs"),
                projectRoot.file("native/upstream.rev"),
                projectRoot.file("native/third_party_licenses.json"),
            )
            inputs.dir(projectRoot.dir("native/src"))
            inputs.dir(projectRoot.dir("native/include"))
            inputs.dir(projectRoot.dir("android/app/src/main/native"))
        }
        variant.sources.jniLibs?.addGeneratedSourceDirectory(nativeBuild, BuildDirkaNative::libraries)
    }
}
