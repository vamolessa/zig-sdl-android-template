const std = @import("std");
const android = @import("build_android.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    // DESKTOP STEPS
    {
        // BUILD DESKTOP
        const exe = b.addExecutable("main", "src/main.zig");
        exe.setTarget(target);
        exe.setBuildMode(mode);

        exe.linkLibC();

        exe.addIncludeDir("third-party/SDL2/include");
        exe.addLibPath("third-party/SDL2/VisualC/x64/Release");
        exe.linkSystemLibrary("SDL2");
        b.installBinFile("third-party/SDL2/VisualC/x64/Release/SDL2.dll", "SDL2.dll");

        exe.install();

        // RUN DESKTOP
        const run_cmd = exe.run();
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);

        // DIRTY BUILD SDL FOR DESKTOP (WINDOWS)
        const sdl_desktop = b.addSystemCommand(&[_][]const u8{
            "msbuild",
            "third-party/SDL2/VisualC/SDL.sln",
            "-t:Build",
            "-p:Configuration=Release",
            "-p:Platform=x64",
        });
        const build_sdl_desktop_step = b.step("sdl-desktop", "Build SDL for desktop using msbuild on path");
        build_sdl_desktop_step.dependOn(&sdl_desktop.step);
    }

    // ANDROID STEPS
    {
        const android_env = getAndroidEnvFromEnvVars(b);

        // BUILD SDL FOR ANDROID
        const sdl_android = android.buildSdlForAndroidStep(b, &android_env);
        const build_sdl_android = b.step("sdl-android", "Build SDL for android using the Android SDK");
        build_sdl_android.dependOn(sdl_android);

        // BUILD ANDROID
        const libs = buildAndroidMainLibraries(b, &android_env, mode);
        const build_libs = b.step("android", "Build the main android library");
        for (libs.items) |lib| {
            build_libs.dependOn(&lib.step.step);
        }

        // BUILD APK
        const apk = android.buildApkStep(b, &android_env, libs.items);
        const build_apk = b.step("apk", "Build the android apk (debug)");
        build_apk.dependOn(apk);

        // INSTALL AND RUN APK
        const run = android.installAndRunApkStep(b, &android_env, "com.gamemaker.game", "MainActivity");
        const run_cmd = b.step("run-apk", "Install and run the previously built android apk");
        run_cmd.dependOn(run);

        // OPEN ANDROID LOG
        const open_log = android.openAndroidLog(b, &android_env);
        const open_log_cmd = b.step("android-log", "Open the android device log filtered to our application");
        open_log_cmd.dependOn(open_log);
    }
}

fn getEnvVar(b: *std.build.Builder, name: []const u8) []u8 {
    return std.process.getEnvVarOwned(b.allocator, name) catch std.debug.panic("env var '{s}' not set", .{name});
}

fn getAndroidEnvFromEnvVars(b: *std.build.Builder) android.AndroidEnv {
    // this example gets the needed paths from environment variables
    // however it's really up to you from where to get them
    // even hardcoding is fair game
    return android.AndroidEnv{
        .jdk_path = getEnvVar(b, "JDK_PATH"),
        .sdk_path = getEnvVar(b, "ANDROID_SDK_PATH"),
        .platform_number = getEnvVar(b, "ANDROID_PLATFORM_NUMBER"),
        .build_tools_path = getEnvVar(b, "ANDROID_BUILD_TOOLS_PATH"),
        .ndk_path = getEnvVar(b, "ANDROID_NDK_PATH"),
    };
}

pub fn buildAndroidMainLibraries(
    builder: *std.build.Builder,
    android_env: *const android.AndroidEnv,
    mode: std.builtin.Mode,
) std.ArrayList(android.AndroidMainLib) {
    // steps to generate a libmain.so for all supported android platforms

    android.assertZigLibcConfigsDirExist(builder, android_env);

    comptime var all_targets: [@typeInfo(android.AndroidTarget).Enum.fields.len]android.AndroidTarget = undefined;
    inline for (@typeInfo(android.AndroidTarget).Enum.fields) |field, i| {
        all_targets[i] = @intToEnum(android.AndroidTarget, field.value);
    }

    var libs = std.ArrayList(android.AndroidMainLib).initCapacity(builder.allocator, 4) catch unreachable;
    for (all_targets) |target| {
        switch (target) {
            // compiling android apps to arm not supported right now. see: https://github.com/ziglang/zig/issues/8885
            .arm => continue,
            // compiling android apps to x86 not supported right now. see https://github.com/ziglang/zig/issues/7935
            .x86 => continue,
            else => {},
        }

        const step = buildAndroidMainLibrary(builder, android_env, mode, target);
        libs.append(.{
            .target = target,
            .step = step,
        }) catch unreachable;
    }

    return libs;
}

pub fn buildAndroidMainLibrary(
    builder: *std.build.Builder,
    android_env: *const android.AndroidEnv,
    mode: std.builtin.Mode,
    target: android.AndroidTarget,
) *std.build.LibExeObjStep {
    // steps to generate a libmain.so for a specific android platform

    const lib = builder.addSharedLibrary("main", "src/android_main.zig", .unversioned);

    lib.force_pic = true;
    lib.link_function_sections = true;
    lib.bundle_compiler_rt = true;
    lib.strip = (mode == .ReleaseSmall);

    lib.setBuildMode(mode);
    lib.defineCMacro("ANDROID");

    lib.linkLibC();
    const app_libs = [_][]const u8{
        "GLESv2", "EGL", "android", "log",
    };
    for (app_libs) |l| {
        lib.linkSystemLibraryName(l);
    }

    const config = target.config();
    lib.setTarget(config.target);

    const include_dir = std.fs.path.resolve(
        builder.allocator,
        &[_][]const u8{ android_env.ndk_path, "sysroot/usr/include" },
    ) catch unreachable;

    const lib_dir = std.fs.path.resolve(
        builder.allocator,
        &[_][]const u8{ android_env.ndk_path, builder.fmt("platforms/android-{s}", .{android_env.platform_number}) },
    ) catch unreachable;

    lib.addIncludeDir(include_dir);

    lib.addLibPath(std.fs.path.resolve(builder.allocator, &[_][]const u8{ lib_dir, config.lib_dir }) catch unreachable);
    lib.addIncludeDir(std.fs.path.resolve(builder.allocator, &[_][]const u8{ include_dir, config.include_dir }) catch unreachable);

    lib.addIncludeDir("third-party/SDL2/include");
    const android_lib_path = builder.pathFromRoot(
        builder.fmt(android.ANDROID_PROJECT_PATH ++ "/ndk-out/lib/{s}", .{config.out_dir}),
    );

    lib.addLibPath(android_lib_path);
    lib.linkSystemLibrary("SDL2");

    lib.setLibCFile(config.libc_file);

    return lib;
}

