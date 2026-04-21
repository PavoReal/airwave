const std = @import("std");
const Io = std.Io;

const airwave = @import("airwave");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;

    try airwave.start(arena, io);

    //const args = try init.minimal.args.toSlice(arena);
    //for (args) |arg| {
    //   std.log.info("arg: {s}", .{arg});
    //}
}

