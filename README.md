# a zig sdl android app template

# getting started

## project structure

//

## updating SDL
This repository contains the latest SDL release as of writing this, which is 2.0.16.

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
- `android-project/AndroidManifest.xml`
    - package name in `manifest.package` (default: `com.gamemaker.game`)
    - any custom permission/user feature you'd like to add/remove (you can check out other manifests or even the one included with SDL)
    - main activity class name in `manifest/application/activity.android:name` (default: `MainActivity`)
- `android-project/res/values/strings.xml`
    - app name
- `android-project/jni/Application.mk`
    - supported ABIs (default: only `arm64-v8a`)
        - it seems there are some issues preventing zig to crosscompile to other ABIs. So we're only targeting `arm64-v8a` for now and should be easy to add them later by editing this file and our `build.zig`
            - https://github.com/ziglang/zig/issues/8885
            - https://github.com/ziglang/zig/issues/7935
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

----

## desktop

### compilar sdl
Em geral não necessário pois já estamos commitando os `SDL2.dll` e `SDL2.lib`.
De todo modo, basta executar o commando `zig build sdl` (precisa do compilador do visual studio `msbuild` instalado).


## android

### setup

#### se ligar
Tem application (package name) id em:
- `android-project/app/build.gradle`
- `android-project/app/src/main/AndroidManifest.xml`

Tem umas coisas de ABI em:
- `android-project/app/jni/Application.mk`
- `android-project/app/build.gradle`

Symlink da pasta do SDL
```
mklink /J android-project\app\jni\SDL third-party\SDL2
```

Buildar bibliotecas (mas melhor não usar)
```
cd android-project\app\jni
<android-sdk>\ndk\<ndk-version>\ndk-build
```

Gerar chave keystore
```
<java_home>\bin\keytool.exe -genkey -v -keystore debug.keystore -alias debugkey -keyalg RSA -keysize 2048 -validity 10000
```

Tem o arquivo `android-project/app/src/main/values/strings.xml` que contém o nome do jogo (e talvez deva conter mais coisa no futuro.

#### com android studio
- instala tudo que tá aí embaixo
- abre o projeto no android studio
- torce pra dar certo e 'make project'

#### sem android studio
NOTA: não funciona 100% infelizmente :(
```
scoop install android-sdk

# sdkmanager --list # lista as coisas com suas respectivas versões
# parece que não precisa sincronizar a versão do sdk com a do ndk
#
# mas se liga que a pasta do NDK *precisa* ter uma subpasta `platforms`

sdkmanager --install "platforms;android-28"
sdkmanager --install "build-tools;28.0.2"
sdkmanager --install "ndk;21.4.7075529"
```

### packaging
Antes de tudo, precisa compilar o projeto pra android (e depois empacotar tudo em apk).
Pra isso:
```
# vai gerar 'zig-out\lib\<nome-do-projeto>.so'
zig build android install
```

#### com android studio
```
set JAVA_HOME=<android-studio-install-path>\jre
cd android-project
gradlew assembleDebug

# posteriormente pra gerar o apk de release
android-project\gradlew assembleRelease
```

#### sem android studio
NOTA: não funciona 100% infelizmente :(
```
# empacotar o apk (como se adiciona as libs?)
<android-sdk>\build-tools\28.0.2\aapt package -f -F app.apk -I <android-sdk>\platforms\android-28\android.jar -M android-project\app\src\main\AndroidManifest.xml -S android-project\app\src\main\res -v --target-sdk-version 28 -A assets

# assinar o apk
# https://developer.android.com/studio/command-line/apksigner
<android-sdk>\build-tools\28.0.2\apksigner sign --ks <key> app.apk

# instalar o apk
<android-sdk>\platform-tools\adb install -r app.apk

# desinstalar o apk
<android-sdk>\platform-tools\adb uninstall <package-name>

# ver logs do dispositivo
<android-sdk>\platform-tools\adb logcat -s SDL/APP

# rodar o apk
<android-sdk>\platform-tools\adb shell am start -n org.libsdl.app/android.app.NativeActivity
```

Mais info: https://developer.android.com/studio/build/building-cmdline


## construir apk na unha
- https://stackoverflow.com/questions/41132753/how-can-i-build-an-android-apk-without-gradle-on-the-command-line
- https://spin.atomicobject.com/2011/08/22/building-android-application-bundles-apks-by-hand/
- https://github.com/WanghongLin/miscellaneous/blob/master/tools/build-apk-manually.sh
- https://github.com/skanti/Android-Manual-Build-Command-Line
- https://stackoverflow.com/questions/10199863/how-to-execute-the-dex-file-in-android-with-command
- https://www.apriorit.com/dev-blog/233-how-to-build-apk-file-from-command-line

