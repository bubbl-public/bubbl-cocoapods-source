import com.vanniktech.maven.publish.SonatypeHost

plugins {
    id("com.android.library") version "8.2.2"
    id("org.jetbrains.kotlin.android") version "1.9.22"
    id("com.google.devtools.ksp") version "1.9.22-1.0.17"
    id("signing")
    id("com.vanniktech.maven.publish") version "0.30.0"
}

group = providers.gradleProperty("GROUP").orElse("tech.bubbl.sdk").get()
version = providers.gradleProperty("VERSION_NAME").orElse("3.0.4").get()

android {
    namespace = "tech.bubbl.sdk"
    compileSdk = 35

    defaultConfig {
        minSdk = 27
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.datastore:datastore-preferences:1.1.1")
    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")
    implementation("androidx.work:work-runtime-ktx:2.9.1")
    implementation(platform("com.google.firebase:firebase-bom:34.7.0"))
    implementation("com.google.firebase:firebase-messaging")
    ksp("androidx.room:room-compiler:2.6.1")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")

    androidTestImplementation("androidx.test:core-ktx:1.6.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.work:work-testing:2.9.1")
    androidTestImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")
}

mavenPublishing {
    publishToMavenCentral(SonatypeHost.CENTRAL_PORTAL)

    val shouldSign =
        providers.gradleProperty("signingInMemoryKey").isPresent ||
            providers.gradleProperty("signing.keyId").isPresent ||
            providers.environmentVariable("SIGNING_PGP_KEY").isPresent
    if (shouldSign) {
        signAllPublications()
    }

    coordinates(
        providers.gradleProperty("GROUP").orElse("tech.bubbl.sdk").get(),
        "bubbl-sdk",
        providers.gradleProperty("VERSION_NAME").orElse(project.version.toString()).get(),
    )

    pom {
        name.set(providers.gradleProperty("POM_NAME").orElse("Bubbl Android SDK").get())
        description.set(
            providers.gradleProperty("POM_DESCRIPTION")
                .orElse("Native Android SDK for Bubbl v3 runtime, geofence, notification, and ingest flows.")
                .get(),
        )
        url.set(providers.gradleProperty("POM_URL").orElse("https://github.com/bubbl-platform/renewed-sdk").get())

        licenses {
            license {
                name.set(providers.gradleProperty("POM_LICENCE_NAME").orElse("Commercial").get())
                url.set(providers.gradleProperty("POM_LICENCE_URL").orElse("https://bubbl.tech").get())
            }
        }

        developers {
            developer {
                id.set(providers.gradleProperty("POM_DEVELOPER_ID").orElse("bubbl").get())
                name.set(providers.gradleProperty("POM_DEVELOPER_NAME").orElse("Bubbl").get())
                email.set(providers.gradleProperty("POM_DEVELOPER_EMAIL").orElse("engineering@bubbl.tech").get())
            }
        }

        scm {
            connection.set(
                providers.gradleProperty("POM_SCM_CONNECTION")
                    .orElse("scm:git:https://github.com/bubbl-platform/renewed-sdk.git")
                    .get(),
            )
            developerConnection.set(
                providers.gradleProperty("POM_SCM_DEV_CONNECTION")
                    .orElse("scm:git:ssh://git@github.com/bubbl-platform/renewed-sdk.git")
                    .get(),
            )
            url.set(providers.gradleProperty("POM_SCM_URL").orElse("https://github.com/bubbl-platform/renewed-sdk").get())
        }
    }
}
