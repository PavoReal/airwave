//! Zig bindings for libhackrf.
//!
//! ## Usage
//!
//! Initialize the library once at program start, then open a device, configure
//! it, and stream samples through a callback. Always close the device and call
//! `deinit` before exit.
//!
//! ```zig
//! const hackrf = @import("hackrf.zig");
//!
//! try hackrf.init();
//! defer hackrf.deinit() catch {};
//!
//! const dev = try hackrf.Device.open();
//! defer dev.close();
//!
//! try dev.setSampleRate(10_000_000);
//! try dev.setFreq(915_000_000);
//! try dev.setLnaGain(24);
//! try dev.setVgaGain(20);
//! try dev.setAmpEnable(false);
//! ```
//!
//! ## Example: receive IQ samples
//!
//! The callback runs on libhackrf's streaming thread. Return `.@"continue"`
//! to keep streaming or `.stop` to halt. Use `Transfer.iqSamples()` for a
//! zero-copy view of the buffer as `IQSample` pairs.
//!
//! ```zig
//! const Ctx = struct { count: usize = 0 };
//! var ctx: Ctx = .{};
//!
//! const Cb = struct {
//!     fn onRx(transfer: hackrf.Transfer, c: *Ctx) hackrf.StreamAction {
//!         const samples = transfer.iqSamples();
//!         c.count += samples.len;
//!         return if (c.count > 1_000_000) .stop else .@"continue";
//!     }
//! };
//!
//! try dev.startRx(*Ctx, Cb.onRx, &ctx);
//! while (dev.isStreaming()) std.Thread.sleep(10 * std.time.ns_per_ms);
//! try dev.stopRx();
//! ```
//!
//! ## Example: transmit IQ samples
//!
//! TX callbacks fill the provided buffer each call. Use `iqSamplesBuffer()` to
//! write into the full transfer buffer.
//!
//! ```zig
//! const Tx = struct {
//!     fn onTx(transfer: hackrf.Transfer, _: void) hackrf.StreamAction {
//!         for (transfer.iqSamplesBuffer()) |*s| s.* = .{ .i = 0, .q = 0 };
//!         return .@"continue";
//!     }
//! };
//!
//! try dev.setTxVgaGain(20);
//! try dev.startTx(void, Tx.onTx, {});
//! ```
//!
//! ## Error handling
//!
//! All fallible calls return `Error!T`. Use `errorName` to get a human-readable
//! string for a returned error.

const std = @import("std");

pub const c = @import("c");

// Re-export raw C bindings for advanced use cases
pub const raw = c;

/// HackRF library errors
pub const Error = error{
    InvalidParam,
    NotFound,
    Busy,
    NoMem,
    LibUsb,
    Thread,
    StreamingThreadErr,
    StreamingStopped,
    StreamingExitCalled,
    UsbApiVersion,
    NotLastDevice,
    Other,
};

/// Convert C error code to Zig error
fn checkResult(result: c_int) Error!void {
    return switch (result) {
        c.HACKRF_SUCCESS, c.HACKRF_TRUE => {},
        c.HACKRF_ERROR_INVALID_PARAM => error.InvalidParam,
        c.HACKRF_ERROR_NOT_FOUND => error.NotFound,
        c.HACKRF_ERROR_BUSY => error.Busy,
        c.HACKRF_ERROR_NO_MEM => error.NoMem,
        c.HACKRF_ERROR_LIBUSB => error.LibUsb,
        c.HACKRF_ERROR_THREAD => error.Thread,
        c.HACKRF_ERROR_STREAMING_THREAD_ERR => error.StreamingThreadErr,
        c.HACKRF_ERROR_STREAMING_STOPPED => error.StreamingStopped,
        c.HACKRF_ERROR_STREAMING_EXIT_CALLED => error.StreamingExitCalled,
        c.HACKRF_ERROR_USB_API_VERSION => error.UsbApiVersion,
        c.HACKRF_ERROR_NOT_LAST_DEVICE => error.NotLastDevice,
        else => error.Other,
    };
}

/// Board identification
pub const BoardId = enum(u8) {
    jellybean = c.BOARD_ID_JELLYBEAN,
    jawbreaker = c.BOARD_ID_JAWBREAKER,
    hackrf1_og = c.BOARD_ID_HACKRF1_OG,
    rad1o = c.BOARD_ID_RAD1O,
    hackrf1_r9 = c.BOARD_ID_HACKRF1_R9,
    undetected = c.BOARD_ID_UNDETECTED,
    _,

    pub fn name(self: BoardId) [:0]const u8 {
        return std.mem.span(c.hackrf_board_id_name(@intFromEnum(self)));
    }

    pub fn platform(self: BoardId) u32 {
        return c.hackrf_board_id_platform(@intFromEnum(self));
    }
};

/// USB board identification
pub const UsbBoardId = enum(c_uint) {
    jawbreaker = c.USB_BOARD_ID_JAWBREAKER,
    hackrf_one = c.USB_BOARD_ID_HACKRF_ONE,
    rad1o = c.USB_BOARD_ID_RAD1O,
    invalid = c.USB_BOARD_ID_INVALID,
    _,

    pub fn name(self: UsbBoardId) [:0]const u8 {
        return std.mem.span(c.hackrf_usb_board_id_name(@intFromEnum(self)));
    }
};

/// Board revision
pub const BoardRev = enum(u8) {
    hackrf1_old = c.BOARD_REV_HACKRF1_OLD,
    hackrf1_r6 = c.BOARD_REV_HACKRF1_R6,
    hackrf1_r7 = c.BOARD_REV_HACKRF1_R7,
    hackrf1_r8 = c.BOARD_REV_HACKRF1_R8,
    hackrf1_r9 = c.BOARD_REV_HACKRF1_R9,
    hackrf1_r10 = c.BOARD_REV_HACKRF1_R10,
    undetected = c.BOARD_REV_UNDETECTED,
    _,

    pub fn name(self: BoardRev) [:0]const u8 {
        return std.mem.span(c.hackrf_board_rev_name(@intFromEnum(self)));
    }
};

/// RF filter path setting
pub const RfPathFilter = enum(c_uint) {
    bypass = c.RF_PATH_FILTER_BYPASS,
    low_pass = c.RF_PATH_FILTER_LOW_PASS,
    high_pass = c.RF_PATH_FILTER_HIGH_PASS,

    pub fn name(self: RfPathFilter) [:0]const u8 {
        return std.mem.span(c.hackrf_filter_path_name(@intFromEnum(self)));
    }
};

/// Sweep style for frequency sweeping
pub const SweepStyle = enum(c_uint) {
    linear = c.LINEAR,
    interleaved = c.INTERLEAVED,
};

/// Return value for Zig-native streaming callbacks
pub const StreamAction = enum {
    /// Continue streaming
    @"continue",
    /// Stop streaming
    stop,
};

/// Interleaved signed 8-bit I/Q sample pair.
/// The HackRF transfer buffer contains these as [I₁, Q₁, I₂, Q₂, ...].
pub const IQSample = extern struct {
    i: i8,
    q: i8,

    /// Normalize to f32 values in [-1.0, ~+0.992].
    pub fn toFloat(self: IQSample) [2]f32 {
        return .{
            @as(f32, @floatFromInt(self.i)) / 128.0,
            @as(f32, @floatFromInt(self.q)) / 128.0,
        };
    }

    /// Create an IQSample from normalized f32 values in [-1.0, 1.0].
    /// Values are clamped to the i8 range.
    pub fn fromFloat(i_f: f32, q_f: f32) IQSample {
        return .{
            .i = @intFromFloat(std.math.clamp(i_f * 128.0, -128.0, 127.0)),
            .q = @intFromFloat(std.math.clamp(q_f * 128.0, -128.0, 127.0)),
        };
    }
};

/// USB transfer information passed to RX or TX callback
pub const Transfer = struct {
    inner: *c.hackrf_transfer,

    pub fn device(self: Transfer) Device {
        return .{ .handle = self.inner.device };
    }

    pub fn buffer(self: Transfer) []u8 {
        return self.inner.buffer[0..@intCast(self.inner.buffer_length)];
    }

    pub fn validData(self: Transfer) []u8 {
        return self.inner.buffer[0..@intCast(self.inner.valid_length)];
    }

    pub fn validLength(self: Transfer) u32 {
        return @intCast(self.inner.valid_length);
    }

    pub fn setValidLength(self: Transfer, len: usize) void {
        self.inner.valid_length = @intCast(len);
    }

    pub fn rxContext(self: Transfer, comptime T: type) ?*T {
        return @ptrCast(@alignCast(self.inner.rx_ctx));
    }

    pub fn txContext(self: Transfer, comptime T: type) ?*T {
        return @ptrCast(@alignCast(self.inner.tx_ctx));
    }

    /// Reinterpret valid received data as IQ sample pairs (zero-copy).
    pub fn iqSamples(self: Transfer) []IQSample {
        return std.mem.bytesAsSlice(IQSample, self.validData());
    }

    /// Reinterpret the full transfer buffer as IQ sample pairs (zero-copy).
    /// Use this in TX callbacks to fill the buffer with samples.
    pub fn iqSamplesBuffer(self: Transfer) []IQSample {
        return std.mem.bytesAsSlice(IQSample, self.buffer());
    }

    /// Reinterpret valid received data as signed 8-bit values (zero-copy).
    pub fn signedData(self: Transfer) []i8 {
        return std.mem.bytesAsSlice(i8, self.validData());
    }
};

/// Raw C callback types for advanced users who need direct C interop
pub const RawCallbacks = struct {
    /// Raw C callback for RX/TX streaming. Return 0 to continue, non-zero to stop.
    pub const SampleBlock = *const fn ([*c]c.hackrf_transfer) callconv(.c) c_int;
    /// Raw C callback for TX block complete notification
    pub const TxBlockComplete = *const fn ([*c]c.hackrf_transfer, c_int) callconv(.c) void;
    /// Raw C callback for TX flush notification
    pub const Flush = *const fn (?*anyopaque, c_int) callconv(.c) void;
};

/// Generates a C-compatible trampoline for RX/TX/Sweep sample block callbacks.
/// Wraps a Zig-native `fn(Transfer, Ctx) StreamAction` into a C function pointer.
fn SampleBlockTrampoline(comptime Ctx: type, comptime callback: fn (Transfer, Ctx) StreamAction, comptime ctx_field: enum { rx, tx }) type {
    return struct {
        fn trampoline(raw_transfer: [*c]c.hackrf_transfer) callconv(.c) c_int {
            const transfer: Transfer = .{ .inner = raw_transfer };
            const ctx: Ctx = if (Ctx == void)
                {}
            else
                @ptrCast(@alignCast(switch (ctx_field) {
                    .rx => raw_transfer.*.rx_ctx,
                    .tx => raw_transfer.*.tx_ctx,
                }));
            return switch (callback(transfer, ctx)) {
                .@"continue" => 0,
                .stop => -1,
            };
        }
    };
}

/// Generates a C-compatible trampoline for TX block complete callbacks.
/// Wraps a Zig-native `fn(Transfer, bool, Ctx) void` into a C function pointer.
fn TxBlockCompleteTrampoline(comptime Ctx: type, comptime callback: fn (Transfer, bool, Ctx) void) type {
    return struct {
        fn trampoline(raw_transfer: [*c]c.hackrf_transfer, success: c_int) callconv(.c) void {
            const transfer: Transfer = .{ .inner = raw_transfer };
            const ctx: Ctx = if (Ctx == void)
                {}
            else
                @ptrCast(@alignCast(raw_transfer.*.tx_ctx));
            callback(transfer, success == 0, ctx);
        }
    };
}

/// Generates a C-compatible trampoline for flush callbacks.
/// Wraps a Zig-native `fn(Ctx, bool) void` into a C function pointer.
fn FlushTrampoline(comptime Ctx: type, comptime callback: fn (Ctx, bool) void) type {
    return struct {
        fn trampoline(raw_ctx: ?*anyopaque, success: c_int) callconv(.c) void {
            const ctx: Ctx = if (Ctx == void)
                {}
            else
                @ptrCast(@alignCast(raw_ctx));
            callback(ctx, success == 0);
        }
    };
}

/// M0 core state
pub const M0State = extern struct {
    requested_mode: u16,
    request_flag: u16,
    active_mode: u32,
    m0_count: u32,
    m4_count: u32,
    num_shortfalls: u32,
    longest_shortfall: u32,
    shortfall_limit: u32,
    threshold: u32,
    next_mode: u32,
    @"error": u32,
};

/// Part ID and serial number
pub const PartIdSerialNo = extern struct {
    part_id: [2]u32,
    serial_no: [4]u32,
};

/// List of connected HackRF devices
pub const DeviceList = struct {
    inner: *c.hackrf_device_list_t,

    /// Get list of all connected HackRF devices
    pub fn get() Error!DeviceList {
        return .{ .inner = c.hackrf_device_list() orelse return error.NoMem };
    }

    /// Free the device list
    pub fn deinit(self: DeviceList) void {
        c.hackrf_device_list_free(self.inner);
    }

    /// Number of connected devices
    pub fn count(self: DeviceList) usize {
        return @intCast(self.inner.devicecount);
    }

    /// Get serial numbers as a slice
    pub fn serialNumbers(self: DeviceList) []const ?[*:0]const u8 {
        const len = self.count();
        return @ptrCast(self.inner.serial_numbers[0..len]);
    }

    /// Get USB board IDs as a slice
    pub fn usbBoardIds(self: DeviceList) []const UsbBoardId {
        const len = self.count();
        const ptr: [*]const UsbBoardId = @ptrCast(self.inner.usb_board_ids);
        return ptr[0..len];
    }

    /// Open a device from the list by index
    pub fn open(self: DeviceList, idx: usize) Error!Device {
        var handle: ?*c.hackrf_device = null;
        try checkResult(c.hackrf_device_list_open(self.inner, @intCast(idx), &handle));
        return .{ .handle = handle orelse return error.NotFound };
    }

    /// Check if a device is sharing its USB bus with other devices
    pub fn busSharing(self: DeviceList, idx: usize) Error!usize {
        const result = c.hackrf_device_list_bus_sharing(self.inner, @intCast(idx));
        if (result < 0) {
            try checkResult(result);
            unreachable;
        }
        return @intCast(result);
    }
};

/// HackRF device handle
pub const Device = struct {
    handle: *c.hackrf_device,

    /// Open first available HackRF device
    pub fn open() Error!Device {
        var handle: ?*c.hackrf_device = null;
        try checkResult(c.hackrf_open(&handle));
        return .{ .handle = handle orelse return error.NotFound };
    }

    /// Open HackRF device by serial number
    pub fn openBySerial(serial: ?[*:0]const u8) Error!Device {
        var handle: ?*c.hackrf_device = null;
        try checkResult(c.hackrf_open_by_serial(serial, &handle));
        return .{ .handle = handle orelse return error.NotFound };
    }

    /// Close the device
    pub fn close(self: Device) void {
        _ = c.hackrf_close(self.handle);
    }

    // === Streaming ===

    /// Start receiving samples with a Zig-native callback.
    /// Callback signature: `fn(Transfer, Ctx) StreamAction`
    pub fn startRx(self: Device, comptime Ctx: type, comptime callback: fn (Transfer, Ctx) StreamAction, ctx: Ctx) Error!void {
        const T = SampleBlockTrampoline(Ctx, callback, .rx);
        try checkResult(c.hackrf_start_rx(
            self.handle,
            @ptrCast(&T.trampoline),
            if (Ctx == void) null else @ptrCast(@alignCast(ctx)),
        ));
    }

    /// Start receiving samples with a raw C callback
    pub fn startRxRaw(self: Device, callback: RawCallbacks.SampleBlock, ctx: ?*anyopaque) Error!void {
        try checkResult(c.hackrf_start_rx(self.handle, @ptrCast(callback), ctx));
    }

    /// Stop receiving
    pub fn stopRx(self: Device) Error!void {
        try checkResult(c.hackrf_stop_rx(self.handle));
    }

    /// Start transmitting samples with a Zig-native callback.
    /// Callback signature: `fn(Transfer, Ctx) StreamAction`
    pub fn startTx(self: Device, comptime Ctx: type, comptime callback: fn (Transfer, Ctx) StreamAction, ctx: Ctx) Error!void {
        const T = SampleBlockTrampoline(Ctx, callback, .tx);
        try checkResult(c.hackrf_start_tx(
            self.handle,
            @ptrCast(&T.trampoline),
            if (Ctx == void) null else @ptrCast(@alignCast(ctx)),
        ));
    }

    /// Start transmitting samples with a raw C callback
    pub fn startTxRaw(self: Device, callback: RawCallbacks.SampleBlock, ctx: ?*anyopaque) Error!void {
        try checkResult(c.hackrf_start_tx(self.handle, @ptrCast(callback), ctx));
    }

    /// Stop transmitting
    pub fn stopTx(self: Device) Error!void {
        try checkResult(c.hackrf_stop_tx(self.handle));
    }

    /// Set TX block complete callback with a Zig-native callback.
    /// Callback signature: `fn(Transfer, bool, Ctx) void`
    pub fn setTxBlockCompleteCallback(self: Device, comptime Ctx: type, comptime callback: fn (Transfer, bool, Ctx) void) Error!void {
        const T = TxBlockCompleteTrampoline(Ctx, callback);
        try checkResult(c.hackrf_set_tx_block_complete_callback(self.handle, @ptrCast(&T.trampoline)));
    }

    /// Set TX block complete callback with a raw C callback
    pub fn setTxBlockCompleteCallbackRaw(self: Device, callback: RawCallbacks.TxBlockComplete) Error!void {
        try checkResult(c.hackrf_set_tx_block_complete_callback(self.handle, @ptrCast(callback)));
    }

    /// Enable TX flush with a Zig-native callback.
    /// Callback signature: `fn(Ctx, bool) void`
    pub fn enableTxFlush(self: Device, comptime Ctx: type, comptime callback: fn (Ctx, bool) void, ctx: Ctx) Error!void {
        const T = FlushTrampoline(Ctx, callback);
        try checkResult(c.hackrf_enable_tx_flush(
            self.handle,
            @ptrCast(&T.trampoline),
            if (Ctx == void) null else @ptrCast(@alignCast(ctx)),
        ));
    }

    /// Enable TX flush with a raw C callback
    pub fn enableTxFlushRaw(self: Device, callback: RawCallbacks.Flush, ctx: ?*anyopaque) Error!void {
        try checkResult(c.hackrf_enable_tx_flush(self.handle, @ptrCast(callback), ctx));
    }

    /// Check if device is streaming
    pub fn isStreaming(self: Device) bool {
        return c.hackrf_is_streaming(self.handle) == c.HACKRF_TRUE;
    }

    // === Configuration ===

    /// Set center frequency in Hz
    pub fn setFreq(self: Device, freq_hz: u64) Error!void {
        try checkResult(c.hackrf_set_freq(self.handle, freq_hz));
    }

    /// Set center frequency explicitly with IF, LO and filter path
    pub fn setFreqExplicit(self: Device, if_freq_hz: u64, lo_freq_hz: u64, path: RfPathFilter) Error!void {
        try checkResult(c.hackrf_set_freq_explicit(self.handle, if_freq_hz, lo_freq_hz, @intFromEnum(path)));
    }

    /// Set sample rate in Hz (2-20 MHz recommended)
    pub fn setSampleRate(self: Device, freq_hz: f64) Error!void {
        try checkResult(c.hackrf_set_sample_rate(self.handle, freq_hz));
    }

    /// Set sample rate with explicit frequency and divider
    pub fn setSampleRateManual(self: Device, freq_hz: u32, divider: u32) Error!void {
        try checkResult(c.hackrf_set_sample_rate_manual(self.handle, freq_hz, divider));
    }

    /// Set baseband filter bandwidth in Hz
    pub fn setBasebandFilterBandwidth(self: Device, bandwidth_hz: u32) Error!void {
        try checkResult(c.hackrf_set_baseband_filter_bandwidth(self.handle, bandwidth_hz));
    }

    /// Enable or disable the RF amplifier (14dB)
    pub fn setAmpEnable(self: Device, enable: bool) Error!void {
        try checkResult(c.hackrf_set_amp_enable(self.handle, @intFromBool(enable)));
    }

    /// Set LNA gain (0-40 dB in 8dB steps)
    pub fn setLnaGain(self: Device, value: u32) Error!void {
        try checkResult(c.hackrf_set_lna_gain(self.handle, value));
    }

    /// Set VGA gain (0-62 dB in 2dB steps)
    pub fn setVgaGain(self: Device, value: u32) Error!void {
        try checkResult(c.hackrf_set_vga_gain(self.handle, value));
    }

    /// Set TX VGA gain (0-47 dB in 1dB steps)
    pub fn setTxVgaGain(self: Device, value: u32) Error!void {
        try checkResult(c.hackrf_set_txvga_gain(self.handle, value));
    }

    /// Enable or disable antenna port power (bias tee)
    pub fn setAntennaEnable(self: Device, enable: bool) Error!void {
        try checkResult(c.hackrf_set_antenna_enable(self.handle, @intFromBool(enable)));
    }

    /// Set hardware sync mode
    pub fn setHwSyncMode(self: Device, enable: bool) Error!void {
        try checkResult(c.hackrf_set_hw_sync_mode(self.handle, @intFromBool(enable)));
    }

    /// Set clock output enable
    pub fn setClkoutEnable(self: Device, enable: bool) Error!void {
        try checkResult(c.hackrf_set_clkout_enable(self.handle, @intFromBool(enable)));
    }

    /// Set UI enable
    pub fn setUiEnable(self: Device, enable: bool) Error!void {
        try checkResult(c.hackrf_set_ui_enable(self.handle, @intFromBool(enable)));
    }

    /// Set TX underrun limit
    pub fn setTxUnderrunLimit(self: Device, value: u32) Error!void {
        try checkResult(c.hackrf_set_tx_underrun_limit(self.handle, value));
    }

    /// Set RX overrun limit
    pub fn setRxOverrunLimit(self: Device, value: u32) Error!void {
        try checkResult(c.hackrf_set_rx_overrun_limit(self.handle, value));
    }

    // === Device Info ===

    /// Read board ID
    pub fn boardIdRead(self: Device) Error!BoardId {
        var value: u8 = undefined;
        try checkResult(c.hackrf_board_id_read(self.handle, &value));
        return @enumFromInt(value);
    }

    /// Read board revision
    pub fn boardRevRead(self: Device) Error!BoardRev {
        var value: u8 = undefined;
        try checkResult(c.hackrf_board_rev_read(self.handle, &value));
        return @enumFromInt(value);
    }

    /// Read firmware version string
    pub fn versionStringRead(self: Device, buffer: []u8) Error![]u8 {
        try checkResult(c.hackrf_version_string_read(self.handle, buffer.ptr, @intCast(buffer.len - 1)));
        const len = std.mem.indexOfScalar(u8, buffer, 0) orelse buffer.len;
        return buffer[0..len];
    }

    /// Read USB API version
    pub fn usbApiVersionRead(self: Device) Error!u16 {
        var version: u16 = undefined;
        try checkResult(c.hackrf_usb_api_version_read(self.handle, &version));
        return version;
    }

    /// Read part ID and serial number
    pub fn boardPartIdSerialNoRead(self: Device) Error!PartIdSerialNo {
        var result: c.read_partid_serialno_t = undefined;
        try checkResult(c.hackrf_board_partid_serialno_read(self.handle, &result));
        return .{
            .part_id = result.part_id,
            .serial_no = result.serial_no,
        };
    }

    /// Read supported platform
    pub fn supportedPlatformRead(self: Device) Error!u32 {
        var value: u32 = undefined;
        try checkResult(c.hackrf_supported_platform_read(self.handle, &value));
        return value;
    }

    /// Get M0 core state
    pub fn getM0State(self: Device) Error!M0State {
        var state: c.hackrf_m0_state = undefined;
        try checkResult(c.hackrf_get_m0_state(self.handle, &state));
        return @bitCast(state);
    }

    /// Get clock input status
    pub fn getClkinStatus(self: Device) Error!u8 {
        var status: u8 = undefined;
        try checkResult(c.hackrf_get_clkin_status(self.handle, &status));
        return status;
    }

    // === Sweep ===

    /// Initialize frequency sweep
    pub fn initSweep(
        self: Device,
        freq_ranges: [][2]u16,
        num_bytes: u32,
        step_width: u32,
        offset: u32,
        style: SweepStyle,
    ) Error!void {
        try checkResult(c.hackrf_init_sweep(
            self.handle,
            @ptrCast(freq_ranges.ptr),
            @intCast(freq_ranges.len),
            num_bytes,
            step_width,
            offset,
            @intFromEnum(style),
        ));
    }

    /// Start RX sweep with a Zig-native callback.
    /// Callback signature: `fn(Transfer, Ctx) StreamAction`
    pub fn startRxSweep(self: Device, comptime Ctx: type, comptime callback: fn (Transfer, Ctx) StreamAction, ctx: Ctx) Error!void {
        const T = SampleBlockTrampoline(Ctx, callback, .rx);
        try checkResult(c.hackrf_start_rx_sweep(
            self.handle,
            @ptrCast(&T.trampoline),
            if (Ctx == void) null else @ptrCast(@alignCast(ctx)),
        ));
    }

    /// Start RX sweep with a raw C callback
    pub fn startRxSweepRaw(self: Device, callback: RawCallbacks.SampleBlock, ctx: ?*anyopaque) Error!void {
        try checkResult(c.hackrf_start_rx_sweep(self.handle, @ptrCast(callback), ctx));
    }

    // === SPI Flash ===

    /// Erase SPI flash
    pub fn spiflashErase(self: Device) Error!void {
        try checkResult(c.hackrf_spiflash_erase(self.handle));
    }

    /// Write to SPI flash
    pub fn spiflashWrite(self: Device, address: u32, data: []const u8) Error!void {
        try checkResult(c.hackrf_spiflash_write(self.handle, address, data.ptr, @intCast(data.len)));
    }

    /// Read from SPI flash
    pub fn spiflashRead(self: Device, address: u32, data: []u8) Error!void {
        try checkResult(c.hackrf_spiflash_read(self.handle, address, data.ptr, @intCast(data.len)));
    }

    /// Read SPI flash status
    pub fn spiflashStatus(self: Device) Error!u8 {
        var status: u8 = undefined;
        try checkResult(c.hackrf_spiflash_status(self.handle, &status));
        return status;
    }

    /// Clear SPI flash status
    pub fn spiflashClearStatus(self: Device) Error!void {
        try checkResult(c.hackrf_spiflash_clear_status(self.handle));
    }

    // === CPLD ===

    /// Write CPLD bitstream
    pub fn cpldWrite(self: Device, data: []const u8) Error!void {
        try checkResult(c.hackrf_cpld_write(self.handle, data.ptr, @intCast(data.len)));
    }

    // === Debug/Low-level ===

    /// Reset the device
    pub fn reset(self: Device) Error!void {
        try checkResult(c.hackrf_reset(self.handle));
    }

    /// Set LEDs state
    pub fn setLeds(self: Device, state: u8) Error!void {
        try checkResult(c.hackrf_set_leds(self.handle, state));
    }

    /// Get transfer buffer size
    pub fn getTransferBufferSize(self: Device) usize {
        return c.hackrf_get_transfer_buffer_size(self.handle);
    }

    /// Get transfer queue depth
    pub fn getTransferQueueDepth(self: Device) u32 {
        return c.hackrf_get_transfer_queue_depth(self.handle);
    }
};

// === Library functions ===

/// Initialize the HackRF library
pub fn init() Error!void {
    try checkResult(c.hackrf_init());
}

/// Exit the HackRF library (all devices must be closed first)
pub fn deinit() Error!void {
    try checkResult(c.hackrf_exit());
}

/// Get library version string
pub fn libraryVersion() [:0]const u8 {
    return std.mem.span(c.hackrf_library_version());
}

/// Get library release string
pub fn libraryRelease() [:0]const u8 {
    return std.mem.span(c.hackrf_library_release());
}

/// Compute nearest valid baseband filter bandwidth
pub fn computeBasebandFilterBw(bandwidth_hz: u32) u32 {
    return c.hackrf_compute_baseband_filter_bw(bandwidth_hz);
}

/// Compute nearest valid baseband filter bandwidth (round down)
pub fn computeBasebandFilterBwRoundDownLt(bandwidth_hz: u32) u32 {
    return c.hackrf_compute_baseband_filter_bw_round_down_lt(bandwidth_hz);
}

/// Get error name string
pub fn errorName(err: Error) [:0]const u8 {
    const code: c_int = switch (err) {
        error.InvalidParam => c.HACKRF_ERROR_INVALID_PARAM,
        error.NotFound => c.HACKRF_ERROR_NOT_FOUND,
        error.Busy => c.HACKRF_ERROR_BUSY,
        error.NoMem => c.HACKRF_ERROR_NO_MEM,
        error.LibUsb => c.HACKRF_ERROR_LIBUSB,
        error.Thread => c.HACKRF_ERROR_THREAD,
        error.StreamingThreadErr => c.HACKRF_ERROR_STREAMING_THREAD_ERR,
        error.StreamingStopped => c.HACKRF_ERROR_STREAMING_STOPPED,
        error.StreamingExitCalled => c.HACKRF_ERROR_STREAMING_EXIT_CALLED,
        error.UsbApiVersion => c.HACKRF_ERROR_USB_API_VERSION,
        error.NotLastDevice => c.HACKRF_ERROR_NOT_LAST_DEVICE,
        error.Other => c.HACKRF_ERROR_OTHER,
    };
    return std.mem.span(c.hackrf_error_name(code));
}
