# Enables shrinking/optimization in -c opt builds while keeping stack traces
# readable for apps distributed through internal testing channels.
-dontobfuscate

# AndroidX Window probes optional platform extension classes by reflection.
-dontwarn androidx.window.extensions.**
