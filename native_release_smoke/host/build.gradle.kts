import java.util.Properties
plugins { id("com.android.application") }
val signingFile = file("G:/Projekty/FitterWelderPro-release-0.5.20/android/key.properties")
val signingValues = Properties().apply { signingFile.inputStream().use { load(it) } }
android {
 namespace = "com.startklaar.fitterwelder"
 compileSdk = 36
 defaultConfig {
  applicationId = "com.startklaar.fitterwelder"
  minSdk = 26
  targetSdk = 36
  versionCode = 1
  versionName = "TEST-HOST-NEVER-UPLOAD"
  testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
 }
 signingConfigs { create("release") {
  storeFile = signingFile.parentFile.resolve(signingValues.getProperty("storeFile"))
  storePassword = signingValues.getProperty("storePassword")
  keyAlias = signingValues.getProperty("keyAlias")
  keyPassword = signingValues.getProperty("keyPassword")
 } }
 buildTypes { getByName("release") {
  isMinifyEnabled = false
  signingConfig = signingConfigs.getByName("release")
 } }
 testBuildType = "release"
 compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}
tasks.withType<JavaCompile>().configureEach { options.encoding = "UTF-8" }
dependencies {
 androidTestImplementation("androidx.test:runner:1.6.2")
 androidTestImplementation("org.jetbrains.kotlin:kotlin-stdlib:2.4.0")
 androidTestImplementation("junit:junit:4.13.2")
}
