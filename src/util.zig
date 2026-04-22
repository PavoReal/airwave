pub inline fn KHz(x: f64) u64 {
    return @intFromFloat(x * 1_000.0);
}

pub inline fn MHz(x: f64) u64 {
    return @intFromFloat(x * 1_000_000.0);
}

pub inline fn GHz(x: f64) u64 {
    return @intFromFloat(x * 1_000_000_000.0);
}
