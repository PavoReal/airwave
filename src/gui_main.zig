const std = @import("std");
const zgui = @import("zgui");
const hackrf = @import("hackrf");
const airwave = @import("airwave");
const util = @import("util.zig");

const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

// ImGui backend entry points we compiled ourselves in build.zig.
// Declared here because zgui is built with .no_backend, so its Zig wrapper
// doesn't expose these.
extern fn ImGui_ImplSDL3_InitForSDLGPU(window: ?*c.SDL_Window) bool;
extern fn ImGui_ImplSDL3_Shutdown() void;
extern fn ImGui_ImplSDL3_NewFrame() void;
extern fn ImGui_ImplSDL3_ProcessEvent(event: *const c.SDL_Event) bool;

const ImGui_ImplSDLGPU3_InitInfo = extern struct {
    Device: ?*c.SDL_GPUDevice = null,
    ColorTargetFormat: c.SDL_GPUTextureFormat = c.SDL_GPU_TEXTUREFORMAT_INVALID,
    MSAASamples: c.SDL_GPUSampleCount = c.SDL_GPU_SAMPLECOUNT_1,
    SwapchainComposition: c.SDL_GPUSwapchainComposition = c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR,
    PresentMode: c.SDL_GPUPresentMode = c.SDL_GPU_PRESENTMODE_VSYNC,
};

extern fn ImGui_ImplSDLGPU3_Init(info: *ImGui_ImplSDLGPU3_InitInfo) bool;
extern fn ImGui_ImplSDLGPU3_Shutdown() void;
extern fn ImGui_ImplSDLGPU3_NewFrame() void;
extern fn ImGui_ImplSDLGPU3_PrepareDrawData(draw_data: *anyopaque, cmd_buf: ?*c.SDL_GPUCommandBuffer) void;
extern fn ImGui_ImplSDLGPU3_RenderDrawData(
    draw_data: *anyopaque,
    cmd_buf: ?*c.SDL_GPUCommandBuffer,
    render_pass: ?*c.SDL_GPURenderPass,
    pipeline: ?*c.SDL_GPUGraphicsPipeline,
) void;

fn sdlFail(comptime msg: []const u8) noreturn {
    const err = c.SDL_GetError();
    std.debug.panic(msg ++ ": {s}", .{err});
}

const HackRFConnectionState = enum {
    disconnected,
    should_connect,
    connected,
    should_disconnect,
};

var hackrf_connection_state = HackRFConnectionState.disconnected;

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const transient_buffer = allocator.alloc(u8, 1024 * 1024) catch @panic("allocator.alloc failed");
    defer allocator.free(transient_buffer);

    var transient_allocator = std.heap.FixedBufferAllocator.init(transient_buffer);
    const trans_alloc = transient_allocator.allocator();

    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_GAMEPAD)) sdlFail("SDL_Init");
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow(
        "airwave",
        1280,
        720,
        c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_HIGH_PIXEL_DENSITY,
    ) orelse sdlFail("SDL_CreateWindow");
    defer c.SDL_DestroyWindow(window);

    const gpu_device = c.SDL_CreateGPUDevice(
        c.SDL_GPU_SHADERFORMAT_SPIRV | c.SDL_GPU_SHADERFORMAT_DXIL | c.SDL_GPU_SHADERFORMAT_METALLIB,
        true,
        null,
    ) orelse sdlFail("SDL_CreateGPUDevice");
    defer c.SDL_DestroyGPUDevice(gpu_device);

    if (!c.SDL_ClaimWindowForGPUDevice(gpu_device, window)) sdlFail("SDL_ClaimWindowForGPUDevice");
    _ = c.SDL_SetGPUSwapchainParameters(
        gpu_device,
        window,
        c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR,
        c.SDL_GPU_PRESENTMODE_VSYNC,
    );
    _ = c.SDL_ShowWindow(window);

    zgui.init(io, allocator);
    defer zgui.deinit();

    if (!ImGui_ImplSDL3_InitForSDLGPU(window)) @panic("ImGui_ImplSDL3_InitForSDLGPU failed");
    defer ImGui_ImplSDL3_Shutdown();

    var sdlgpu_info: ImGui_ImplSDLGPU3_InitInfo = .{
        .Device = gpu_device,
        .ColorTargetFormat = c.SDL_GetGPUSwapchainTextureFormat(gpu_device, window),
        .MSAASamples = c.SDL_GPU_SAMPLECOUNT_1,
    };
    if (!ImGui_ImplSDLGPU3_Init(&sdlgpu_info)) @panic("ImGui_ImplSDLGPU3_Init failed");
    defer ImGui_ImplSDLGPU3_Shutdown();

    var running = true;

    hackrf.init() catch @panic("hackrf.init failed");
    defer hackrf.deinit() catch @panic("hackrf.deinit failed");

    const devices = try hackrf.DeviceList.get();
    defer devices.deinit();

    var hackrf_device_idx: usize = 0;

    while (running) {
        //
        // Event handling
        //

        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            _ = ImGui_ImplSDL3_ProcessEvent(&event);

            switch (event.type) {
                c.SDL_EVENT_QUIT => running = false,
                c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                    if (event.window.windowID == c.SDL_GetWindowID(window)) running = false;
                    hackrf_connection_state = .should_disconnect;
                },
                else => {},
            }
        }

        //
        // Update state
        //

        switch (hackrf_connection_state) {
            .should_connect => {
                try airwave.start(allocator, io, hackrf_device_idx);
                hackrf_connection_state = .connected;
            },
            .should_disconnect => {
                try airwave.stop(allocator);
                hackrf_connection_state = .disconnected;
            },
            else => {},
        }

        ImGui_ImplSDLGPU3_NewFrame();
        ImGui_ImplSDL3_NewFrame();
        zgui.newFrame();

        //
        // GUI
        //

        if (zgui.begin("Devices", .{})) {
            zgui.text("HackRF One", .{});
            for (devices.serialNumbers(), 0..) |serial_number, i| {
                const label_buf: []u8 = try trans_alloc.alloc(u8, 1024);
                var label: [:0]const u8 = undefined;

                if (serial_number) |sn| {
                    label = try std.fmt.bufPrintZ(label_buf, "{d}: {s}", .{ i + 1, sn });
                } else {
                    label = try std.fmt.bufPrintZ(label_buf, "{d}: unknown", .{i + 1});
                }

                if (zgui.button(label, .{})) {
                    if (hackrf_connection_state == .disconnected) {
                        hackrf_device_idx = i;
                        hackrf_connection_state = .should_connect;
                    } else {
                        hackrf_connection_state = .should_disconnect;
                    }
                }
            }
        }
        zgui.end();

        if (hackrf_connection_state == .connected) {
            if (zgui.begin("HackRF One", .{})) {
                zgui.text("Sample Rate: {d} msps", .{airwave.sdr.getSampleRate() / util.MHz(1)});
                zgui.text("CF: {d} MHz", .{airwave.sdr.getFreq() / util.MHz(1)});
            }
            zgui.end();
        }

        //
        //
        //

        zgui.render();
        const draw_data = zgui.getDrawData();

        const cmd_buf = c.SDL_AcquireGPUCommandBuffer(gpu_device) orelse {
            sdlFail("SDL_AcquireGPUCommandBuffer");
        };

        var swapchain_tex: ?*c.SDL_GPUTexture = null;
        if (!c.SDL_WaitAndAcquireGPUSwapchainTexture(cmd_buf, window, &swapchain_tex, null, null)) {
            _ = c.SDL_SubmitGPUCommandBuffer(cmd_buf);
            continue;
        }

        if (swapchain_tex == null) {
            _ = c.SDL_SubmitGPUCommandBuffer(cmd_buf);
            continue;
        }

        ImGui_ImplSDLGPU3_PrepareDrawData(@ptrCast(draw_data), cmd_buf);

        const color_target: c.SDL_GPUColorTargetInfo = .{
            .texture = swapchain_tex,
            .clear_color = .{ .r = 0.05, .g = 0.05, .b = 0.08, .a = 1.0 },
            .load_op = c.SDL_GPU_LOADOP_CLEAR,
            .store_op = c.SDL_GPU_STOREOP_STORE,
            .mip_level = 0,
            .layer_or_depth_plane = 0,
            .cycle = false,
        };
        const render_pass = c.SDL_BeginGPURenderPass(cmd_buf, &color_target, 1, null) orelse {
            sdlFail("SDL_BeginGPURenderPass");
        };
        ImGui_ImplSDLGPU3_RenderDrawData(@ptrCast(draw_data), cmd_buf, render_pass, null);
        c.SDL_EndGPURenderPass(render_pass);

        _ = c.SDL_SubmitGPUCommandBuffer(cmd_buf);
    }

    _ = c.SDL_WaitForGPUIdle(gpu_device);
    _ = c.SDL_ReleaseWindowFromGPUDevice(gpu_device, window);
}
