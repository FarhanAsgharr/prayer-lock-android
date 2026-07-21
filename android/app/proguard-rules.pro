# Release build shrinking rules.
#
# R8 removes anything it cannot prove is reachable. Several things in this app
# are reached only reflectively or from native code, so they must be kept
# explicitly — without these rules the release build compiles cleanly and then
# fails at runtime, which is the worst kind of failure to discover after
# shipping.

# Flutter engine and embedding.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# The lock screen's Dart entrypoint is looked up by name from native code, so
# nothing in the bytecode references it and R8 would otherwise strip it. The
# symptom is a blank white lock screen in release builds only.
-keepclassmembers class * {
    @io.flutter.embedding.engine.dart.DartExecutor$DartEntrypoint *;
}

# Our blocking service and lock activity are instantiated by the Android
# framework from the manifest, not by our own code.
-keep class com.prayerlock.prayer_lock.blocking.AppBlockerService { *; }
-keep class com.prayerlock.prayer_lock.blocking.LockScreenActivity { *; }
-keep class com.prayerlock.prayer_lock.MainActivity { *; }

# flutter_local_notifications deserialises scheduled notifications from disk
# via Gson after a reboot; obfuscating these classes breaks rescheduling.
-keep class com.dexterous.** { *; }
-keepattributes *Annotation*
-keepattributes Signature

# Desugared java.time, used for exact alarm scheduling.
-dontwarn java.time.**
-dontwarn sun.misc.**
