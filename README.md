# a zig sdl android app template

This is a tutorial that will guide you how to build an Android application 'by hand' using
- zig as the main programming language
- SDL as the platform abstraction
- zig build as automation

We also cover what is the process of creating an apk from scratch. No AndroidStudio required.
What you learn works for any language.

Tested on Windows.

# getting started

## requirements
- JDK
    - if you already have AndroidStudio installed, you can simply use the folder `<android-studio>/jre`
    - otherwise, it is recommended to install Java 8 (I could be wrong, though)
- Android SDK
    - `platforms` (min `16`, latest recommended)
    - `build-tools` with the same number as `platforms`
    - `ndk` (a version that has a `platforms` subfolder as newer versions don't seem to come with?)
    - `cmake` (needed to build SDL)

You can install these components with some commands that look like these (or else use Android Studio to install them):
```
sdkmanager --install "platforms;android-28"
sdkmanager --install "build-tools;28.0.2"
sdkmanager --install "ndk;21.4.7075529"
sdkmanager --install "cmake;3.18.1"

# if not on path, you can invoke sdkmanager as `<android-sdk>/tools/bin/sdkmanager`
```

## project structure
- `android-project`: where all android related files are. including build output
    - `AndroidManifest.xml`: your android app manifest (more info bellow)
    - `java`: java sources that interface with the android os. includes your app's MainActivity
    - `jni`: project files that help build your dependencies (only SDL in this template) for android
    - `keystore`: where you put your keystores. this template assumes that you'll generate a `debug.keystore` here (more info bellow)
    - `res`: your android app resources files
    - `out`: all intermediate and final apk build outputs. you'll find the final apk here (`app.apk`)
    - `ndk-out`: build cache of your dependencies (only SDL in this template)
- `assets`: home of all your game assets
- `src`: zig (game) sources
- `third-party`: your dependencies go here. in this template, there's only SDL2 there
- `zig-libc-configs`: when cross-compiling, zig needs a libc config file that tells it where to find libc related folders (more info bellow)
- `package.bat`: first version of the packaging pipeline. it's still there for easy reference of what's needed to generate an apk. however the real source of truth is `build.zig`
- `build.zig`: general build scripts for this template
- `build_android.zig`: android related build scripts for this template (used by `build.zig`)

## updating SDL
This repository contains the latest SDL release as of writing this, which is `2.0.16`.

Updating SDL is a matter of replacing the contents of the `third-party/SDL2` folder.

Then you have to update the SDL java sources in `android-project/java/org/libsdl/app/*.java`.
For that you can either:
- symlink it to point to `third-party/SDL2/android-project/app/src/main/java/org/libsdl/app`; or
- manually copy those java sources to the destination
    - this repository does the later as I've deleted some unecessary folders from the SDL installation (but you don't need to)

### SDL extensions
If you plan on using any SDL extension (SDL_image, SDL_mixer, etc), it'd be a matter of:
- putting them inside the `third-party` folder
- enabling their loading in your `MainActivity.java` (more info bellow)
- changing the build steps to also build them for android (TODO)
- link to them when building your zig main library (TODO)

## things to change/setup for your project
- `zig-libc-configs`
    - this folder contains libc configs for each android target
    - it's very important to change the `crt_dir` field for each of those targets as it's dependent on your ndk installation and androi platform number
    - in future versions of zig, it will be possible to auto-generate these from `build.zig`
- `android-project/AndroidManifest.xml`
    - package name in `manifest.package` (default: `com.gamemaker.game`)
    - any custom permission/user feature you'd like to add/remove (you can check out other manifests or even the one included with SDL)
    - main activity class name in `manifest/application/activity.android:name` (default: `MainActivity`)
- `android-project/res/values/strings.xml`
    - app name
- `android-project/java/com/gamemaker/game/MainActivity.java`
    - java package (default: `com.gamemaker.game`).
        - NOTE: do not forget to also rename the folder struct to reflect the package name!
    - change your zig main function name (default: `SDL_main`)
    - change loaded native libraries (mainly if you use any SDL extension or other native libs)
    - override any other default property from `android-project/java/org/libsdl/app/SDLActivity.java`
- `assets` folder
    - this template sets the `assets` folder up for any asset your project might use (images, audios, fonts, etc)
        - should be easy to change it to something else
        - but it's easier (only way?) to package the apk when everything is under a single folder

### generate keystore
Use `keytool` that comes in JDK to generate your keystores.
This template assumes the keystore file `android-project/keystore/debug.keystore` with `password` as its password.
You can generate this file yourself with these commands:

```
cd android-project
mkdir keystore
cd keystore
<JDK_PATH>/bin/keytool -genkey -v -keystore debug.keystore -alias debugkey -keyalg RSA -keysize 2048 -validity 10000
```

When submitting your app to a store, you'll want to also generate (and backup!) a `release.keystore`.

### first build
When doing the first apk build, you'll want to do things in this order:
- generate debug keystore
- `zig build sdl-android`
- `zig build apk`

That is because generating the keystore is an interactive process.
Also, the `apk` step does not depend on `sdl-android` because even with caching, running `zig build sdl-android` takes
a few seconds. Since it's a step that you'd re-run very rarely, I think it's fine to keep it separated.

The following apk builds should be just a matter of repeating `zig build apk`
and then testing the generated apk on a device or emulator.

# steps to create an apk
Here is an overview of all the steps needed to create a working apk that uses native code:

- compile all dependencies targeting android
    - for SDL this means invoking `ndk-build` that uses the `Application.mk` and `Android.mk` to generate its native libs
- compile your code targeting android linking against those dependencies artifacts
    - for zig, we do this inside `build.zig`
- generate `R.java` inside the `out` folder by invoking `aapt` found in Android SDK build-tools folder
- compile any java code using `javac` that comes with the JDK
    - using the `android.jar` found in the Android SDK as `-classpath`;
    - targeting java `7` by passing `1.7` to both `-target` and `-source`; and
    - passing the `java:out` argument kinda means that we're taking java source from the `java` folder and outputing the compiled code to the `out` folder
- convert the compiled java code to Android VM compatible bytecode by using `dx` also in the Android SDK build-tools folder
    - we pass it `--min-sdk-version=16` which is the minimum required for an application to load native code (from what I understand)
    - it will generate a `classes.dex` in the `out` folder
- create the first version of out apk by calling `aapt` again
    - we actually generate a `app.apk.unaligned` to make it clear that it is not final
    - it's also here where we push the `assets` folder into the apk
- call `aapt add` to add the `classes.dex` converted previously into the apk
    - as a quirk, the path inside the apk an added file has is *exactly* the same as the argument passed to the command
    - because of this, we must invoke the tool from a folder where it lets us pass the file as an argument with the correct path
        - that is, in the case of `classes.dex`, we must change to the folder containing the file since `classes.dex` must reside in the root of the apk
- call `aapt add` for every native library we previously built for android
    - all lib files must be inside a `lib` folder
    - even further, it must be inside a `lib/<target>` folder where `<target>` means the target the lib was compiled against
    - for example, if you build your `libmain.so` for `arm64-v8a` which is a pretty common android target, the final path inside the apk must be `lib\arm64-v8a\libmain.so`
- sign the apk using `jarsigner` found in the JDK
    - NOTE: you must provide a previously created keystore and its password for it to work
    - please refer to the previous `### generate keystore` section
- align the apk using `zipalign` found in the Android SDK build-tools folder
    - note that we pass the final file name to the command which is finally `app.apk`, our ready to be installed apk!
- finally you can send it to your device using `adb install` found in the Android SDK `platform-tools` folder
    - please refer to the `## installing` section bellow

# testing the app
## installing
```
<android-sdk>/platform-tools/adb install -r android-project/out/app.apk
```

## uninstalling
```
<android-sdk>/platform-tools/adb uninstall com.gamemaker.game
```
NOTE: change `com.gamemaker.game` with your app package name.

## device logs
```
<android-sdk>/platform-tools/adb logcat -s SDL/APP
```
NOTE: it's also possible to filter logs by doing something like this:
```
<android-sdk>/platform-tools/adb logcat | grep com.gamemaker.game
```

## running
```
<android-sdk>/platform-tools/adb shell am start -n com.gamemaker.game/android.app.GameActivity
```
Where `com.gamemaker.game` should be your app's package name and `GameActivity` should be the name
of the MainActivity class of your app.

# references
- https://developer.android.com/studio/build/building-cmdline
- https://github.com/MasterQ32/ZigAndroidTemplate
- https://www.apriorit.com/dev-blog/233-how-to-build-apk-file-from-command-line
- https://spin.atomicobject.com/2011/08/22/building-android-application-bundles-apks-by-hand/
- https://github.com/skanti/Android-Manual-Build-Command-Line
- https://github.com/WanghongLin/miscellaneous/blob/master/tools/build-apk-manually.sh

# support
If you found this tutorial/template useful, please consider donating to help me create further tutorials :)
I'll be forever grateful :)

<a href="https://liberapay.com/lessa/donate"><img alt="Donate using Liberapay" src="https://liberapay.com/assets/widgets/donate.svg"></a>
