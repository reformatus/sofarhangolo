# Android Gradle Upgrade Notes

This project was updated on 2026-04-11 to the latest Flutter-safe Android build toolchain that could be validated locally:

- Android Gradle Plugin (AGP): `8.13.2`
- Gradle wrapper: `8.14`
- Kotlin Gradle plugin: `2.3.20`
- Java/Kotlin bytecode target: `17`

## Why not AGP 9 yet?

Flutter currently documents AGP 9 migration separately and warns that Flutter apps using plugins are still incompatible with AGP 9.x during the ongoing migration work:

- https://docs.flutter.dev/release/breaking-changes/migrate-to-agp-9
- https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers

Because this app depends on Flutter plugins, the upgrade stopped at AGP `8.13.2`, which is the newest AGP 8 release line documented by Android.

## Current version policy

Use these sources before changing versions:

- AGP release notes and Gradle compatibility:
  https://developer.android.com/studio/releases/gradle-plugin
- Gradle releases:
  https://docs.gradle.org/current/release-notes.html
- Kotlin releases:
  https://kotlinlang.org/docs/releases.html
- Flutter Android breaking changes:
  https://docs.flutter.dev/release/breaking-changes/

## Files to update

For normal Android toolchain upgrades, check these files:

- `android/settings.gradle`
- `android/app/build.gradle`
- `android/gradle/wrapper/gradle-wrapper.properties`
- `android/gradle.properties`

## Safe upgrade workflow

1. Check Flutter breaking-change docs first.
2. Check the AGP release notes page for the latest supported AGP line and its minimum Gradle version.
3. Check the Kotlin release page for the latest stable Kotlin version.
4. Update:
   - `android/settings.gradle`
   - `com.android.application`
   - `org.jetbrains.kotlin.android`
5. Update `android/gradle/wrapper/gradle-wrapper.properties` to a Gradle version supported by that AGP release.
6. If AGP or the Flutter template has moved the baseline, compare against a fresh template:
   - `flutter create --platforms=android /tmp/template_app`
7. Validate:
   - `flutter build apk --debug`
   - `flutter test`

## AGP 9 / built-in Kotlin migration checklist

Do this only after Flutter explicitly supports AGP 9 for plugin-based apps.

1. Read the AGP 9 Flutter migration guide.
2. Read the built-in Kotlin migration guide.
3. Add or confirm these flags in `android/gradle.properties` during migration:
   - `android.newDsl=false`
   - `android.builtInKotlin=false`
4. Remove the app module Kotlin plugin from `android/app/build.gradle`.
5. Remove the `kotlinOptions {}` block.
6. Replace it with:

```groovy
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
```

7. Re-test the Android build and verify all Flutter plugins are compatible.

## Notes from this upgrade

- The repo had already been changed to `gradle-9.4-bin.zip`, but that distribution does not exist and also does not match AGP `8.13.2` requirements.
- AGP `8.13.2` release notes document Kotlin `2.2.21` in examples and state that this AGP line supports Kotlin 2.3 via R8 `8.13.19`.
- Java/Kotlin compilation was moved from `1.8` to `17` to match current AGP requirements.
- Validation succeeded with the Android Studio bundled JDK `21`. The machine default JDK `25` failed during Gradle script analysis with `Unsupported class file major version 69`, so use the Android Studio JDK or another supported JDK when verifying Android upgrades.
