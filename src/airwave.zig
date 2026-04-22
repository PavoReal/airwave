const std = @import("std");
const hackrf = @import("hackrf");
const FixedSizeRingBuffer = @import("ring_buffer.zig").FixedSizeRingBuffer;

var sdr: hackrf.Device = undefined;

var sdr_rx_state = struct {
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

pub fn start(alloc: std.mem.Allocator, io: std.Io) !void {
    try hackrf.init();

    sdr = try hackrf.Device.open();

    sdr_rx_state.rx_ring_buffer = try FixedSizeRingBuffer(hackrf.IQSample).init(alloc, 1024 * 1024);
    sdr_rx_state.mutex = std.Io.Mutex.init;
    sdr_rx_state.io = io;

    try sdr.setSampleRate(2_000_000); // 2 msps
    try sdr.setFreq(1_090_00_00);

    try sdr.startRx(*@TypeOf(sdr_rx_state), sdrRxCallback, &sdr_rx_state);
    std.debug.print("SDR started\n", .{});
    sdr_rx_state.running = false;
}

pub fn stop() !void {
    sdr.close();
    hackrf.deinit() catch {};
}
