const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const resolved_target = target.result;
    const os_tag = resolved_target.os.tag;
    const is_darwin = (os_tag == .macos) or (os_tag == .ios) or (os_tag == .tvos) or (os_tag == .watchos);
    const is_posix = is_darwin or (os_tag == .linux) or (os_tag == .openbsd);

    //
    // Build libusb from source
    //
    const libusb_dep = b.dependency("libusb", .{});

    const libusb_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const libusb_cflags: []const []const u8 = &.{
        "-DDEFAULT_VISIBILITY=",
        "-DPRINTF_FORMAT(a,b)=",
        "-DENABLE_LOGGING=1",
    };

    libusb_mod.addCSourceFiles(.{
        .root = libusb_dep.path(""),
        .files = &.{
            "libusb/core.c",
            "libusb/descriptor.c",
            "libusb/hotplug.c",
            "libusb/io.c",
            "libusb/strerror.c",
            "libusb/sync.c",
        },
        .flags = libusb_cflags,
    });

    if (is_posix) {
        libusb_mod.addCSourceFiles(.{
            .root = libusb_dep.path(""),
            .files = &.{
                "libusb/os/events_posix.c",
                "libusb/os/threads_posix.c",
            },
            .flags = libusb_cflags,
        });
    }

    if (os_tag == .windows) {
        libusb_mod.addCSourceFiles(.{
            .root = libusb_dep.path(""),
            .files = &.{
                "libusb/os/events_windows.c",
                "libusb/os/threads_windows.c",
                "libusb/os/windows_common.c",
                "libusb/os/windows_usbdk.c",
                "libusb/os/windows_winusb.c",
            },
            .flags = libusb_cflags,
        });
    } else if (os_tag == .linux) {
        libusb_mod.addCSourceFiles(.{
            .root = libusb_dep.path(""),
            .files = &.{
                "libusb/os/linux_usbfs.c",
                "libusb/os/linux_netlink.c",
            },
            .flags = libusb_cflags,
        });
    } else if (is_darwin) {
        libusb_mod.addCSourceFiles(.{
            .root = libusb_dep.path(""),
            .files = &.{
                "libusb/os/darwin_usb.c",
            },
            .flags = libusb_cflags,
        });
        libusb_mod.linkFramework("CoreFoundation", .{});
        libusb_mod.linkFramework("IOKit", .{});
        libusb_mod.linkFramework("Security", .{});
    } else if (os_tag == .netbsd) {
        libusb_mod.addCSourceFiles(.{
            .root = libusb_dep.path(""),
            .files = &.{"libusb/os/netbsd_usb.c"},
            .flags = libusb_cflags,
        });
    } else if (os_tag == .openbsd) {
        libusb_mod.addCSourceFiles(.{
            .root = libusb_dep.path(""),
            .files = &.{"libusb/os/openbsd_usb.c"},
            .flags = libusb_cflags,
        });
    } else if (os_tag == .haiku) {
        libusb_mod.addCSourceFiles(.{
            .root = libusb_dep.path(""),
            .files = &.{
                "libusb/os/haiku_pollfs.cpp",
                "libusb/os/haiku_usb_backend.cpp",
                "libusb/os/haiku_usb_raw.cpp",
            },
            .flags = libusb_cflags,
        });
    }

    libusb_mod.addIncludePath(libusb_dep.path("libusb"));

    const config_h = b.addConfigHeader(.{ .style = .blank, .include_path = "config.h" }, .{
        .HAVE_CLOCK_GETTIME = if (os_tag != .windows) @as(i64, 1) else null,
        .HAVE_STRUCT_TIMESPEC = 1,
        .HAVE_SYS_TIME_H = if (os_tag != .windows) @as(i64, 1) else null,
        .PLATFORM_POSIX = if (is_posix) @as(i64, 1) else null,
        .PLATFORM_WINDOWS = if (os_tag == .windows) @as(i64, 1) else null,
    });
    libusb_mod.addConfigHeader(config_h);

    const libusb = b.addLibrary(.{
        .name = "usb-1.0",
        .linkage = .static,
        .root_module = libusb_mod,
    });

    //
    // Build libhackrf from source
    //
    const hackrf_dep = b.dependency("libhackrf", .{
        .target = target,
        .optimize = optimize,
    });

    const libhackrf_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    libhackrf_mod.addCSourceFiles(.{
        .root = hackrf_dep.path("host/libhackrf/src"),
        .files = &.{"hackrf.c"},
        .flags = &.{
            "-DLIBRARY_VERSION=\"2026.01.2\"",
            "-DLIBRARY_RELEASE=\"release\"",
        },
    });

    libhackrf_mod.addIncludePath(hackrf_dep.path("host/libhackrf/src"));
    libhackrf_mod.addIncludePath(libusb_dep.path("libusb"));
    libhackrf_mod.linkLibrary(libusb);

    const libhackrf = b.addLibrary(.{
        .name = "hackrf",
        .linkage = .static,
        .root_module = libhackrf_mod,
    });

    //
    // Translate libhackrf C headers into a Zig module
    //
    const hackrf_translate = b.addTranslateC(.{
        .root_source_file = b.path("src/hackrf_c.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    hackrf_translate.addIncludePath(hackrf_dep.path("host/libhackrf/src"));
    const hackrf_c_mod = hackrf_translate.createModule();

    //
    // hackrf module (libhackrf Zig wrapper)
    //
    const hackrf_mod = b.addModule("hackrf", .{
        .root_source_file = b.path("src/hackrf.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "c", .module = hackrf_c_mod },
        },
    });
    hackrf_mod.linkLibrary(libhackrf);

    //
    // airwave module (library root)
    //
    const mod = b.addModule("airwave", .{
        .root_source_file = b.path("src/airwave.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "hackrf", .module = hackrf_mod },
        },
    });

    //
    // airwave-server executable
    //
    const exe = b.addExecutable(.{
        .name = "airwave-server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "airwave", .module = mod },
                .{ .name = "hackrf", .module = hackrf_mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    //
    // zgui (Dear ImGui + ImPlot) — compiled with no backend so we can pair it
    // with SDL3 headers we control. When zig-gamedev/zgui PR #103 merges, swap
    // the .zgui URL in build.zig.zon back to canonical upstream.
    //
    const zgui_dep = b.dependency("zgui", .{
        .target = target,
        .optimize = optimize,
        .backend = .no_backend,
        .with_implot = true,
        .shared = false,
    });

    //
    // SDL3 from source via allyourcodebase/SDL3
    //
    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        .linkage = .static,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");

    //
    // airwave-gui executable (SDL3 + SDL_GPU + Dear ImGui)
    //
    const gui_mod = b.createModule(.{
        .root_source_file = b.path("src/gui_main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "airwave", .module = mod },
            .{ .name = "hackrf", .module = hackrf_mod },
            .{ .name = "zgui", .module = zgui_dep.module("root") },
        },
    });
    gui_mod.link_libcpp = true;

    // Compile the ImGui SDL3 + SDL_GPU backend glue against *our* SDL3 headers
    // so backend compile-time and link-time agree on the SDL3 version/ABI.
    gui_mod.addIncludePath(zgui_dep.path("libs/imgui"));
    gui_mod.addCSourceFiles(.{
        .root = zgui_dep.path("libs/imgui/backends"),
        .files = &.{
            "imgui_impl_sdl3.cpp",
            "imgui_impl_sdlgpu3.cpp",
        },
        .flags = &.{
            "-fno-sanitize=undefined",
            "-Wno-elaborated-enum-base",
            "-DIMGUI_IMPL_API=extern \"C\"",
            "-DIMGUI_DISABLE_OBSOLETE_FUNCTIONS",
        },
    });

    gui_mod.linkLibrary(zgui_dep.artifact("imgui"));
    gui_mod.linkLibrary(sdl_lib);

    const gui_exe = b.addExecutable(.{
        .name = "airwave-gui",
        .root_module = gui_mod,
    });
    b.installArtifact(gui_exe);

    const run_gui = b.addRunArtifact(gui_exe);
    run_gui.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_gui.addArgs(args);
    const run_gui_step = b.step("run-gui", "Run airwave-gui");
    run_gui_step.dependOn(&run_gui.step);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
