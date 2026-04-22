# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

airwave is a Zig 0.16 project that ingests IQ samples from a HackRF One SDR at 1090 MHz and will eventually render ADS-B aircraft data. See `README.md` for the phased vision (web frontend → native renderer → e-ink smart-frame). Current state is earlier than that roadmap: `airwave-server` opens the device and pushes samples into a ring buffer; `airwave-gui` renders an empty ImGui window. No ADS-B decoding is wired up yet, and the dump1090 integration described in the README does not exist in the tree.

## Commands

All commands run from the repo root.

- `zig build` — builds both executables (`airwave-server`, `airwave-gui`) into `zig-out/bin/`.
- `zig build run` — builds and runs `airwave-server` (requires a HackRF One plugged in; it will error out on `hackrf_open` otherwise).
- `zig build run-gui` — builds and runs `airwave-gui` (opens an SDL3 window; does not touch the SDR).
- `zig build test` — runs tests for the `airwave` module and the `airwave-server` exe. Most tests currently live in `src/ring_buffer.zig`.
- Extra args after `--`: `zig build run -- --foo` forwards `--foo` to the executable.

Zig 0.16.0 is required (enforced by `minimum_zig_version` in `build.zig.zon`). First build downloads libhackrf, libusb, the zgui fork, and SDL3 into `zig-pkg/`.

## Architecture

### Two executables sharing one module

`build.zig` builds a single `airwave` module (`src/airwave.zig`) and links it into two executables:

- **`airwave-server`** (`src/main.zig`) — headless SDR ingestion. Calls `airwave.start()`, which opens the HackRF, configures 2 Msps @ 1090 MHz, and installs an RX callback that pushes `IQSample`s into a `FixedSizeRingBuffer`.
- **`airwave-gui`** (`src/gui_main.zig`) — standalone SDL3 + SDL_GPU + Dear ImGui window. Currently independent from the SDR pipeline; it imports `airwave` and `hackrf` but doesn't use them yet.

The two executables are intentionally separate binaries, not subcommands. Any shared logic belongs in `src/airwave.zig` (the `airwave` module), not in either `main.zig`.

### C dependencies are built from source inside `build.zig`

Rather than linking system libraries, `build.zig` builds libusb and libhackrf from vendored source trees fetched via the package manager:

- **libusb** — per-OS source file selection (`events_posix.c` / `linux_usbfs.c` / `darwin_usb.c` / Windows variants). On macOS it also links the `CoreFoundation`, `IOKit`, and `Security` frameworks. Config is injected via an `addConfigHeader` stub for `config.h`.
- **libhackrf** — built on top of the libusb static library. Needs `LIBRARY_VERSION` / `LIBRARY_RELEASE` defines baked in at compile time (currently `"2026.01.2"` / `"release"` — keep in sync with the `libhackrf` URL in `build.zig.zon`).
- **Zig bindings** — `addTranslateC` on `src/hackrf_c.h` (a one-line `#include <hackrf.h>` stub) produces a `c` module that `src/hackrf.zig` wraps in idiomatic Zig. That wrapper is exported as the `hackrf` module.

If you change the libhackrf version in `build.zig.zon`, update the `LIBRARY_VERSION` define in `build.zig` to match.

### zgui / SDL3 / ImGui backend glue

The GUI stack is the trickiest part of the build:

- **zgui is pulled from a fork** (`PavoReal/zgui@airwave-no-zsdl`), not upstream, because Zig 0.16 eagerly compiles every dependency's `build.zig` and upstream zgui transitively pulls in `zsdl`, whose `build.zig` uses pre-0.16 `Compile.*` APIs that were moved to `Module.*`. The fork strips the `zsdl` dep. See `plans/fork-zgui-remove-zsdl.md` for the full history and `build.zig.zon` for the tracking comment. The long-term intent is to go back to canonical upstream once PR [zig-gamedev/zgui#103](https://github.com/zig-gamedev/zgui/pull/103) merges and zsdl is 0.16-compatible.
- **zgui is built with `.backend = .no_backend`.** The ImGui SDL3 + SDL_GPU backend C++ files (`imgui_impl_sdl3.cpp`, `imgui_impl_sdlgpu3.cpp`) are compiled *in this repo's `build.zig`* against our SDL3 include path. This guarantees the backend sees the same SDL3 headers at compile time that `airwave-gui` links against at link time — mixing zgui's bundled SDL backend with our own SDL3 dep would risk ABI drift. Those backend functions are forward-declared as `extern fn` in `src/gui_main.zig`.
- **SDL3 is built from source** via `allyourcodebase/SDL3`, statically linked.

When touching the GUI build, preserve: `.no_backend` on the zgui dep, the `addCSourceFiles` for the two `imgui_impl_sdl*` files, and the `-DIMGUI_IMPL_API=extern "C"` flag (the forward declarations in `gui_main.zig` assume C linkage).

### Ring buffer

`src/ring_buffer.zig` implements a generic `FixedSizeRingBuffer(T)` used to buffer IQ samples coming from libhackrf's streaming thread. It supports:

- `append` / `appendOne` — writer side.
- `slices` / `oldest` / `newest` — zero-copy two-segment reads.
- `copySequential(cursor, dest)` — reader-side API that tracks a sequence-number cursor across the buffer and transparently jumps forward to the oldest available data if the reader has fallen behind and been overwritten. Use this for any consumer that must process samples in order without blocking the producer.

The HackRF RX callback runs on libhackrf's streaming thread, so producer/consumer access to the ring buffer is guarded by `std.Io.Mutex` in `airwave.zig`.
