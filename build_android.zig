const std = @import("std");
const builtin = @import("builtin");

pub const ANDROID_PROJECT_PATH = "android-project";

pub const AndroidEnv = struct {
    jdk_path: []u8,
    sdk_path: []u8,
    platform_number: []u8,
    build_tools_path: []u8,
    ndk_path: []u8,
};

pub const AndroidTarget = enum {
    aarch64,
    arm,
    x86,
    x86_64,

    fn name(self: AndroidTarget) []const u8 {
        return switch (self) {
            .aarch64 => "arm64-v8a",
            .arm => "armeabi",
            .x86 => "x86",
            .x86_64 => "x86_64",
        };
    }
};

pub const AndroidMainLib = struct {
    target: AndroidTarget,
    step: *std.build.LibExeObjStep,
};

pub fn buildSdlForAndroidStep(builder: *std.build.Builder, env: *const AndroidEnv) *std.build.Step {
    // this step will build SDL for all enabled ABIs
    // it's best for this step remain separated in order to keep the output cached
    // since not only you rarely need to rebuild SDL
    // but also because your zig main android lib links agains this output

    const ndk_build_ext = switch(builtin.os.tag) {
        .windows => ".cmd",
        else => ".sh",
    };
    const ndk_build_exe = std.fs.path.resolve(
        builder.allocator,
        &[_][]const u8{ env.ndk_path, "ndk-build" ++ ndk_build_ext },
    ) catch unreachable;

    var ndk_build_command = builder.addSystemCommand(&[_][]const u8{
        ndk_build_exe,
        "NDK_LIBS_OUT=../ndk-out/lib",
        "NDK_OUT=../ndk-out/out",
    });
    // the process needs to execute from the jni folder in order to
    // correctly find the jni project files Application.mk and Android.mk
    ndk_build_command.cwd = builder.pathFromRoot(ANDROID_PROJECT_PATH ++ "/jni");

    return &ndk_build_command.step;
}

pub fn buildApkStep(builder: *std.build.Builder, env: *const AndroidEnv, main_libs: []const AndroidMainLib) *std.build.Step {
    // this step will create a signed and aligned apk from
    // - your android project
    // - your debug keystore
    // - SDL android libs
    // - zig main android lib
    // - your project asset folder

    // all executable paths needed to create an apk
    const exe_ext = switch(builtin.os.tag) {
        .windows => ".exe",
        else => "",
    };
    const javac_exe = std.fs.path.resolve(
        builder.allocator,
        &[_][]const u8{ env.jdk_path, "bin/javac" ++ exe_ext },
    ) catch unreachable;

    const jarsigner_exe = std.fs.path.resolve(
        builder.allocator,
        &[_][]const u8{ env.jdk_path, "bin/jarsigner" ++ exe_ext },
    ) catch unreachable;

    const aapt_exe = std.fs.path.resolve(
        builder.allocator,
        &[_][]const u8{ env.build_tools_path, "aapt" ++ exe_ext },
    ) catch unreachable;

    const dx_ext = switch(builtin.os.tag) {
        .windows => ".bat",
        else => ".sh",
    };
    const dx_exe = std.fs.path.resolve(
        builder.allocator,
        &[_][]const u8{ env.build_tools_path, "dx" ++ dx_ext },
    ) catch unreachable;

    const zipalign_exe = std.fs.path.resolve(
        builder.allocator,
        &[_][]const u8{ env.build_tools_path, "zipalign" ++ exe_ext },
    ) catch unreachable;

    // other paths
    const android_jar_path = std.fs.path.resolve(
        builder.allocator,
        &[_][]const u8{ env.sdk_path, "platforms", builder.fmt("android-{s}", .{env.platform_number}), "android.jar" },
    ) catch unreachable;

    const clean_step = builder.allocator.create(CleanStep) catch unreachable;
    clean_step.* = CleanStep.init(builder);

    var create_r_java_log = builder.addLog(
        "step 1: creating the R.java source from the resources inside the `res` folder\n",
        .{},
    );
    create_r_java_log.step.dependOn(&clean_step.step);
    var create_r_java_command = addCommand(builder, &[_][]const u8{
        aapt_exe,
        "package",
        "-m",
        "-J",
        "out",
        "-M",
        "AndroidManifest.xml",
        "-S",
        "res",
        "-I",
        android_jar_path,
    });
    create_r_java_command.step.dependOn(&create_r_java_log.step);

    var compile_java_log = builder.addLog(
        "step 2: compiling all java sources inside the `java` folder into the `out` folder\n",
        .{},
    );
    compile_java_log.step.dependOn(&create_r_java_command.step);
    var javac_argv = std.ArrayList([]const u8).initCapacity(builder.allocator, 32) catch unreachable;
    javac_argv.append(javac_exe) catch unreachable;
    javac_argv.append("-d") catch unreachable;
    javac_argv.append("out") catch unreachable;
    javac_argv.append("-classpath") catch unreachable;
    javac_argv.append(android_jar_path) catch unreachable;
    javac_argv.append("-target") catch unreachable;
    javac_argv.append("1.7") catch unreachable;
    javac_argv.append("-source") catch unreachable;
    javac_argv.append("1.7") catch unreachable;
    javac_argv.append("-sourcepath") catch unreachable;
    javac_argv.append("java:out") catch unreachable;
    {
        var it = std.fs.walkPath(builder.allocator, builder.pathFromRoot(ANDROID_PROJECT_PATH ++ "/java")) catch unreachable;
        defer it.deinit();
        while (it.next() catch unreachable) |entry| {
            if (entry.kind == .File and std.mem.endsWith(u8, entry.path, ".java")) {
                javac_argv.append(builder.dupe(entry.path)) catch unreachable;
            }
        }
    }
    var compile_java_command = addCommand(builder, javac_argv.items);
    compile_java_command.step.dependOn(&compile_java_log.step);

    var compile_classes_dex_log = builder.addLog(
        "step 3: converting all compiled java code into android vm compatible bytecode\n",
        .{},
    );
    compile_classes_dex_log.step.dependOn(&compile_java_command.step);
    var compile_classes_dex_command = addCommand(builder, &[_][]const u8 {
        dx_exe,
        "--dex",
        "--min-sdk-version=16",
        "--output=out/classes.dex",
        "out",
    });
    compile_classes_dex_command.step.dependOn(&compile_classes_dex_log.step);

    var create_apk_log = builder.addLog(
        "step 4: creating first version of the apk including all resources and asset files\n",
        .{},
    );
    create_apk_log.step.dependOn(&compile_classes_dex_command.step);
    var create_apk_command = addCommand(builder, &[_][]const u8 {
        aapt_exe,
        "package",
        "-f",
        "-M",
        "AndroidManifest.xml",
        "-S",
        "res",
        "-I",
        android_jar_path,
        "-A",
        "../assets",
        "-F",
        "out/app.apk.unaligned",
    });
    create_apk_command.step.dependOn(&create_apk_log.step);

    var copy_sdl_libs_log = builder.addLog(
        "step 5: copying all compiled SDL libraries to `out/lib/<target>`\n",
        .{},
    );
    copy_sdl_libs_log.step.dependOn(&create_apk_command.step);
    const copy_sdl_libs = builder.allocator.create(CopyDirStep) catch unreachable;
    copy_sdl_libs.* = CopyDirStep.init(
        builder,
        ANDROID_PROJECT_PATH ++ "/ndk-out/lib",
        ANDROID_PROJECT_PATH ++ "/out/lib",
    );
    copy_sdl_libs.step.dependOn(&copy_sdl_libs_log.step);

    var copy_main_libs_log = builder.addLog(
        "step 6: copying all compiled zig libraries found to `out/lib/<target>` for each `AndroidTarget`\n",
        .{},
    );
    copy_main_libs_log.step.dependOn(&copy_sdl_libs.step);

    const libs_dir = builder.pathFromRoot(ANDROID_PROJECT_PATH ++ "/out/lib");
    var last_copy_step = &copy_main_libs_log.step;
    for (main_libs) |main_lib| {
        const target_lib_path = std.fs.path.resolve(
            builder.allocator,
            &[_][]const u8{ libs_dir, main_lib.target.name(), "libmain.so" },
        ) catch unreachable;

        const copy_main_lib = builder.allocator.create(CopyLibStep) catch unreachable;
        copy_main_lib.* = CopyLibStep.init(
            builder,
            main_lib.step,
            target_lib_path,
        );
        copy_main_lib.step.dependOn(last_copy_step);
        last_copy_step = &copy_main_lib.step;
    }

    var add_classes_dex_to_apk_log = builder.addLog(
        "step 7: adding `classes.dex` to the apk\n",
        .{},
    );
    add_classes_dex_to_apk_log.step.dependOn(last_copy_step);
    var add_classes_dex_to_apk_command = builder.addSystemCommand(&[_][]const u8 {
        aapt_exe,
        "add",
        "-f",
        "app.apk.unaligned",
        "classes.dex",
    });
    add_classes_dex_to_apk_command.cwd = builder.pathFromRoot(ANDROID_PROJECT_PATH ++ "/out/lib");
    add_classes_dex_to_apk_command.step.dependOn(&add_classes_dex_to_apk_log.step);

    var add_libs_to_apk_log = builder.addLog(
        "step 8: adding all libs inside `out/lib` to the apk\n",
        .{},
    );
    add_libs_to_apk_log.step.dependOn(&add_classes_dex_to_apk_command.step);
    const add_libs_to_apk = builder.allocator.create(AddLibsToApkStep) catch unreachable;
    add_libs_to_apk.* = AddLibsToApkStep.init(builder, aapt_exe);
    add_libs_to_apk.step.dependOn(&add_libs_to_apk_log.step);

    var sign_apk_log = builder.addLog(
        "step 9: signing apk\n",
        .{},
    );
    sign_apk_log.step.dependOn(&add_libs_to_apk.step);
    var sign_apk_command = addCommand(builder, &[_][]const u8 {
        jarsigner_exe,
        "-keystore",
        "keystore/debug.keystore",
        "-storepass",
        "password",
        "-keypass",
        "password",
        "out/app.apk.unaligned",
        "debugkey",
    });
    sign_apk_command.step.dependOn(&sign_apk_log.step);

    var align_apk_log = builder.addLog(
        "step 10: aligning apk\n",
        .{},
    );
    align_apk_log.step.dependOn(&sign_apk_command.step);
    var align_apk_command = addCommand(builder, &[_][]const u8 {
        zipalign_exe,
        "-f",
        "4",
        "out/app.apk.unaligned",
        "out/app.apk",
    });
    align_apk_command.step.dependOn(&align_apk_log.step);

    return &align_apk_command.step;
}

fn addCommand(builder: *std.build.Builder, argv: []const []const u8) *std.build.RunStep {
    var command = builder.addSystemCommand(argv);
    command.cwd = builder.pathFromRoot(ANDROID_PROJECT_PATH);
    return command;
}

const CleanStep = struct {
    step: std.build.Step,
    builder: *std.build.Builder,

    pub fn init(builder: *std.build.Builder) CleanStep {
        return CleanStep{
            .step = std.build.Step.init(.Custom, "Cleaning " ++ ANDROID_PROJECT_PATH ++ "/out", builder.allocator, make),
            .builder = builder,
        };
    }

    fn make(step: *std.build.Step) !void {
        const self = @fieldParentPtr(CleanStep, "step", step);
        const out_dir = self.builder.pathFromRoot(ANDROID_PROJECT_PATH ++ "/out");
        std.fs.cwd().deleteTree(out_dir) catch |err| {
            std.log.warn("Unable to remove {s}: {s}\n", .{ out_dir, @errorName(err) });
            return err;
        };
        try std.fs.cwd().makeDir(out_dir);
    }
};

const CopyLibStep = struct {
    step: std.build.Step,
    builder: *std.build.Builder,
    lib: *std.build.LibExeObjStep,
    dest: []const u8,

    pub fn init(builder: *std.build.Builder, lib: *std.build.LibExeObjStep, dest: []const u8) CopyLibStep {
        var step = std.build.Step.init(.Custom, builder.fmt("copying to {s}", .{dest}), builder.allocator, make);
        step.dependOn(&lib.step);
        return CopyLibStep {
            .builder = builder,
            .step = step,
            .lib = lib,
            .dest = dest,
        };
    }

    fn make(step: *std.build.Step) !void {
        const self = @fieldParentPtr(CopyLibStep, "step", step);

        const cwd = std.fs.cwd();
        const source_path = self.lib.getOutputLibPath();
        _ = try std.fs.Dir.updateFile(cwd, source_path, cwd, self.dest, .{});
    }
};

const CopyDirStep = struct {
    step: std.build.Step,
    builder: *std.build.Builder,
    source: []const u8,
    dest: []const u8,

    pub fn init(builder: *std.build.Builder, source: []const u8, dest: []const u8) CopyDirStep {
        return CopyDirStep{
            .builder = builder,
            .step = std.build.Step.init(.Custom, builder.fmt("copying {s} to {s}", .{source, dest}), builder.allocator, make),
            .source = builder.dupe(source),
            .dest = builder.dupe(dest),
        };
    }

    fn make(step: *std.build.Step) !void {
        const self = @fieldParentPtr(CopyDirStep, "step", step);

        const source = self.builder.pathFromRoot(self.source);
        const dest = self.builder.pathFromRoot(self.dest);

        var it = try std.fs.walkPath(self.builder.allocator, source);
        defer it.deinit();
        while (try it.next()) |entry| {
            const rel_path = entry.path[source.len + 1 ..];
            const dest_path = try std.fs.path.join(self.builder.allocator, &[_][]const u8{dest, rel_path});

            switch (entry.kind) {
                .Directory => try std.fs.cwd().makePath(dest_path),
                .File => try self.builder.updateFile(entry.path, dest_path),
                else => {},
            }
        }
    }
};

const AddLibsToApkStep = struct {
    step: std.build.Step,
    builder: *std.build.Builder,
    aapt_exe: []const u8,

    fn init(builder: *std.build.Builder, aapt_exe: []const u8) AddLibsToApkStep {
        return AddLibsToApkStep {
            .step = std.build.Step.init(.InstallDir, "copying libs to apk", builder.allocator, make),
            .builder = builder,
            .aapt_exe = aapt_exe,
        };
    }

    fn make(step: *std.build.Step) !void {
        const self = @fieldParentPtr(AddLibsToApkStep, "step", step);

        const cwd = self.builder.pathFromRoot(ANDROID_PROJECT_PATH ++ "/out/lib");
        var it = try std.fs.walkPath(self.builder.allocator, cwd);
        defer it.deinit();
        while (try it.next()) |entry| {
            if (entry.kind == .File and std.mem.endsWith(u8, entry.path, ".so")) {
                var lib_path = self.builder.dupe(entry.path);
                for (lib_path) |*byte| {
                    if (byte.* == '\\') {
                        byte.* = '/';
                    }
                }

                const add_process = try std.ChildProcess.init(
                    &[_][]const u8{
                        self.aapt_exe,
                        "add",
                        "-f",
                        "app.apk.unaligned",
                        lib_path,
                    },
                    self.builder.allocator,
                );
                add_process.stdin_behavior = .Ignore;
                add_process.cwd = cwd;
                _ = try add_process.spawnAndWait();
            }
        }
    }
};

