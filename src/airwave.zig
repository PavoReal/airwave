const std = @import("std");
const hackrf = @import("hackrf");
const FixedSizeRingBuffer = @import("ring_buffer.zig").FixedSizeRingBuffer;

pub var sdr: hackrf.Device = undefined;

pub var sdr_rx_state = struct {
    rx_ring_buffer: FixedSizeRingBuffer(hackrf.IQSample) = undefined,
    mutex: std.Io.Mutex = undefined,
    running: bool = false,

    io: std.Io = undefined,
}{};

fn sdrRxCallback(trans: hackrf.Transfer, state: *@TypeOf(sdr_rx_state)) hackrf.StreamAction {
    state.mutex.lock(state.io) catch return .stop;
    defer state.mutex.unlock(state.io);

    state.rx_ring_buffer.append(trans.iqSamples());

    if (!state.running) return .stop;
    return .@"continue";
}

pub fn init() !void {
    try hackrf.init();
}

pub fn deinit() !void {
    try hackrf.deinit();
}

pub fn start(alloc: std.mem.Allocator, io: std.Io, device_idx: usize) !void {
    const devices = try hackrf.DeviceList.get();
    defer devices.deinit();

    sdr = try devices.open(device_idx);

    sdr_rx_state.rx_ring_buffer = try FixedSizeRingBuffer(hackrf.IQSample).init(alloc, 1024 * 1024);
    sdr_rx_state.mutex = std.Io.Mutex.init;
    sdr_rx_state.io = io;

    try sdr.applyConfig();

    try sdr.startRx(*@TypeOf(sdr_rx_state), sdrRxCallback, &sdr_rx_state);
    std.debug.print("SDR started\n", .{});
    sdr_rx_state.running = false;
}

pub fn stop(alloc: std.mem.Allocator) !void {
    try sdr.stopRx();
    sdr_rx_state.rx_ring_buffer.deinit(alloc);
    std.debug.print("SDR stopped\n", .{});
    sdr.close();
}
