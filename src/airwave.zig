const std = @import("std");
const hackrf = @import("hackrf");
const Io = std.Io;

var sdr: hackrf.Device = undefined;

pub fn start(alloc: std.mem.Allocator, io: std.Io) !void {
    _ = alloc;
    _ = io;
    try hackrf.init();

    sdr = try hackrf.Device.open();

    try sdr.setSampleRate(2_000_000); // 2 msps
    try sdr.setFreq(1_090_00_00);
}

pub fn stop() !void {
    sdr.close();
    hackrf.deinit() catch {};
}
