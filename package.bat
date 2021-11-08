rem THIS FILE IS ONLY KEPT AS A REFERENCE FOR PEOPLE NOT USED TO `build.zig`
rem THIS IS NOT EXPECTED TO KEEP WORKING AS THE SOURCE OF TRUTH IS `build.zig`
rem HOWEVER, FEEL FREE TO USE THIS AS A REFERENCE

@echo off

set APP_NAME=MyGame

set JAVA_HOME=D:\AndroidStudio\jre
set ANDROID_SDK=D:\AndroidSDK
set ANDROID_PLATFORM_NUMBER=26
set ANDROID_BUILDTOOLS_VERSION=28.0.2
set ANDROID_NDK_VERSION=21.4.7075529

set ANDROID_PLATFORM=%ANDROID_SDK%\platforms\android-%ANDROID_PLATFORM_NUMBER%
set ANDROID_BUILDTOOLS=%ANDROID_SDK%\build-tools\%ANDROID_BUILDTOOLS_VERSION%
set ANDROID_NDK=%ANDROID_SDK%\ndk\%ANDROID_NDK_VERSION%

pushd android-project

rem BUILD SDL FOR ANDROID
pushd jni
call "%ANDROID_NDK%\ndk-build" NDK_LIBS_OUT=../ndk-out/lib NDK_OUT=../ndk-out/out
popd

rem HERE YOU'D BUILD YOUR APPLICATION AS A `libmain.so` TO BE LOADED FROM YOUR MainActivity
rem I'VE PUT THIS `zig build` COMMAND HERE MERELY AS AN EXAMPLE SINCE WE'VE MOVED FROM THIS `package.bat`
rem TO FULLY BUILDING THE APK FROM `build.zig`
zig build android

rem BUILD APK
rmdir /s /q out
mkdir out

"%ANDROID_BUILDTOOLS%\aapt" package -m -J out -M AndroidManifest.xml -S res -I "%ANDROID_PLATFORM%\android.jar"

"%JAVA_HOME%\bin\javac" -d out -classpath "%ANDROID_PLATFORM%\android.jar" -target 1.7 -source 1.7 -sourcepath "java:out" java/org/libsdl/app/*.java java/com/gamemaker/game/*.java

call "%ANDROID_BUILDTOOLS%\dx" --dex --min-sdk-version=16 --output=out/classes.dex out

"%ANDROID_BUILDTOOLS%\aapt" package -f -M AndroidManifest.xml -S res -I "%ANDROID_PLATFORM%\android.jar" -A ../assets -F out/app.apk.unaligned

xcopy /e /i ndk-out\lib out\lib

rem SINCE WE MOVED TO CREATING THE APK FROM THE `build.zig`, `libmain.so` IS LOCATED INSIDE `zig-cache` WITH A NON STABLE PATH
rem HERE YOU'D FIND `libmain.so` AND COPY IT TO `android-project\out\lib\<target>\libmain.so`
copy ..\zig-out\lib\libmain.so out\lib\arm64-v8a\libmain.so

pushd out
"%ANDROID_BUILDTOOLS%\aapt" add -f app.apk.unaligned classes.dex

"%ANDROID_BUILDTOOLS%\aapt" add -f app.apk.unaligned lib/arm64-v8a/libhidapi.so
"%ANDROID_BUILDTOOLS%\aapt" add -f app.apk.unaligned lib/arm64-v8a/libSDL2.so
"%ANDROID_BUILDTOOLS%\aapt" add -f app.apk.unaligned lib/arm64-v8a/libmain.so

popd

"%JAVA_HOME%\bin\jarsigner" -keystore keystore/debug.keystore -storepass password -keypass password out\app.apk.unaligned debugkey

"%ANDROID_BUILDTOOLS%\zipalign" -f 4 out\app.apk.unaligned "out\%APP_NAME%.apk"

popd

exit /b %ERRORLEVEL%
