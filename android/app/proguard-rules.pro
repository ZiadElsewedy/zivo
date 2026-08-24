# Spotify App Remote (lib/features/music/data/spotify_music_controller.dart)
# — R8 fails release builds without these. The AAR references Jackson
# databind classes (com.spotify.protocol.mappers.jackson.ImageUriJson) and an
# internal annotation (com.spotify.base.annotations.NotNull) that aren't
# actually on the runtime classpath — flutter build's own generated
# missing_rules.txt confirms exactly these three.
#
# Keep (not just -dontwarn) the whole com.spotify.** tree, broader than the
# minimum needed: App Remote's protocol classes are (de)serialized via
# reflection (Jackson-style), and the manifest also declares
# com.spotify.sdk.android.authentication.LoginActivity (a different
# sub-package, com.spotify.android:auth, not just App Remote's
# com.spotify.protocol/com.spotify.android.appremote) — narrowing the keep to
# only the two App Remote packages would leave that one unprotected. The SDK
# itself is a small vendored AAR (~130KB), so the size cost of keeping its
# whole namespace is negligible next to the risk of a stripped/renamed class
# crashing at runtime on connect — a worse failure mode than a build-time one.
-keep class com.spotify.** { *; }
-dontwarn com.spotify.**

# Jackson databind — only referenced by the App Remote AAR above (this app
# never uses Jackson itself), so it's never actually on the classpath.
-keep class com.fasterxml.jackson.** { *; }
-dontwarn com.fasterxml.jackson.**
