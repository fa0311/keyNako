plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}

// The 500MB bundled dictionary makes build outputs heavy; keep them off the
// small D: drive.
allprojects {
    layout.buildDirectory.set(file("C:/Users/yuki/.warabi-poc-build/${project.name}"))
}
