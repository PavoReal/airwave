# Plan: Fork cyberegoorg/zgui to remove its zsdl dependency

## Goal

Replace airwave's dependency on `cyberegoorg/zgui@upgrade_to_zig_16` with a self-maintained fork under `PavoReal/zgui` that has the unused `zsdl` dep removed. After this change, `rm -rf zig-pkg .zig-cache && zig build` must succeed without any hand-patched files in `zig-pkg/`.

## Why

airwave uses zgui with `.backend = .no_backend` and compiles the ImGui SDL3 + SDLGPU3 backends itself (see `build.zig` around the `airwave-gui` block). We never touch zsdl at runtime.

However, Zig 0.16 **eagerly compiles every dependency's `build.zig`** — the `.lazy = true` flag in a parent zon gates *fetching* but NOT *build.zig compilation*. zgui's zon lists `zsdl` as a lazy dep; Zig 0.16 fetches and compiles zsdl's `build.zig` anyway. zsdl's `build.zig` uses the pre-0.16 `Compile.linkSystemLibrary(...)` / `Compile.addLibraryPath(...)` / `Compile.addFrameworkPath(...)` APIs, which were moved to `Module` in 0.16. Result: `zig build` fails before any of our code compiles.

Today there is a local patch applied in-place at `zig-pkg/zsdl-0.4.0-dev-rFpjEzgIXwBdDmlda0YnQPRVApMc1YEgbyzLWuT9GupM/build.zig` that rewrites 10 call sites from `compile_step.foo(...)` to `compile_step.root_module.foo(...)`. That patch lives inside Zig's project-local package cache and is wiped whenever the cache is cleared or the dep is re-fetched. This plan replaces that fragile patch with a durable fork.

## Scope

**In scope:**
- Fork `cyberegoorg/zgui` at branch `upgrade_to_zig_16` (commit `dc4344aa02b78465bb0d769b5889a99feae4ca6b`) into `PavoReal/zgui`.
- Remove `.zsdl` entry from the fork's `build.zig.zon`.
- Remove the 8 `if (b.lazyDependency("zsdl", .{})) |zsdl| { ... }` blocks in the fork's `build.zig` (lines 367, 393, 404, 416, 428, 440, 452, 481). The SDL* backend switch arms lose their auto-attached SDL header include path as a result — downstream users of those arms must now use `.no_backend` and compile backends themselves, which is what airwave does.
- Update `airwave/build.zig.zon` to point `.zgui` at the new fork.
- Remove the project-local zsdl patch and verify `zig build` works from a clean cache.

**Out of scope:**
- Fixing zsdl itself (upstream PR is a separate, optional follow-up).
- Exposing SDL headers via a new build option to keep the SDL backend arms working. Nobody in this repo uses them.
- Swapping our SDL3 source (we keep `allyourcodebase/SDL3`).
- Touching airwave's `src/gui_main.zig` or the hand-compiled imgui backend block in `airwave/build.zig`.

## Prerequisites

- `gh` CLI authenticated as `PavoReal` (same owner as `PavoReal/airwave`). Confirm with `gh auth status`.
- Working tree at `/Users/peacock/workspace/airwave` on branch `main`. Current `zig build` succeeds thanks to the in-cache zsdl patch; that's the state this plan replaces.
- Zig 0.16.0 available on PATH (check with `zig version`).

## Acceptance criteria

1. `PavoReal/zgui` exists as a fork of `cyberegoorg/zgui` with a branch (e.g. `airwave-no-zsdl`) containing the changes below.
2. The fork's `build.zig.zon` has no `.zsdl` entry.
3. The fork's `build.zig` has zero textual occurrences of `zsdl`.
4. `airwave/build.zig.zon`'s `.zgui` entry points at the fork's commit.
5. From a clean state (`rm -rf zig-pkg .zig-cache zig-out && zig build`), the build succeeds **without** touching any file under `zig-pkg/`.
6. `./zig-out/bin/airwave-gui` launches, opens a window, renders the ImGui demo, and exits cleanly on window close.

## Steps

### 1. Fork and clone

```bash
# From any directory
cd /tmp
gh repo fork cyberegoorg/zgui --clone --org PavoReal --remote-name origin
cd zgui
git checkout -b airwave-no-zsdl upgrade_to_zig_16
```

If `gh repo fork` with `--org` isn't available (personal account vs org), fork into the personal account instead:

```bash
gh repo fork cyberegoorg/zgui --clone --remote-name origin
# Then manually rename the remote owner if needed, or push to PavoReal via a second remote.
```

The fork only needs to contain the `upgrade_to_zig_16` branch and the new `airwave-no-zsdl` working branch. Other branches can be left untouched.

### 2. Edit `build.zig.zon` — remove `.zsdl`

Delete the entire `.zsdl = { ... }` block (4 lines, currently at roughly lines 30–34 in the `upgrade_to_zig_16` branch):

```zig
// DELETE THIS WHOLE BLOCK:
.zsdl = .{
    .url = "https://github.com/zig-gamedev/zsdl/archive/537de39b5719f39dcd612df2923607f3aedaf147.tar.gz",
    .hash = "zsdl-0.4.0-dev-rFpjEzgIXwBdDmlda0YnQPRVApMc1YEgbyzLWuT9GupM",
    .lazy = true,
},
```

Leave every other dep (`system_sdk`, `zglfw`, `zgpu`, `freetype`, `zopengl`) alone.

### 3. Edit `build.zig` — remove all zsdl references

The fork's `build.zig` has exactly 8 places where zsdl is consumed, all inside switch arms of the `switch (options.backend)` block. Each looks like:

```zig
if (b.lazyDependency("zsdl", .{})) |zsdl| {
    imgui_mod.addIncludePath(zsdl.path("libs/sdl2/include"));  // path varies per arm
}
```

Delete the entire `if (b.lazyDependency("zsdl", .{})) |zsdl| { ... }` block in each arm. The `addCSourceFiles` calls that follow stay. The affected switch arms (by enum tag) are:

- `.sdl2_opengl3` (around line 367)
- `.sdl2` (around line 393)
- `.sdl2_renderer` (around line 404)
- `.sdl3_gpu` (around line 416)
- `.sdl3_renderer` (around line 428)
- `.sdl3_opengl3` (around line 440) — note this arm uses a slightly different include path (`libs/sdl3/include/SDL3`), still delete the whole block
- `.sdl3_vulkan` (around line 452)
- `.sdl3` (around line 481)

After this, `grep -n zsdl build.zig` must print nothing.

**Post-condition for the fork:** selecting any `.sdl*` backend will produce a compile error because `imgui_impl_sdlN.cpp` won't find SDL headers. This is intentional — document it in step 4.

### 4. Update the fork's `README.md` (short note)

Add a short note under a new section at the bottom:

```markdown
## PavoReal fork notes

This fork removes the `zsdl` dependency to unblock Zig 0.16 builds. As a
consequence, the `.sdl*` backend options no longer auto-attach SDL headers
to the imgui module. Users should set `.backend = .no_backend` and compile
the desired `imgui_impl_*.cpp` backends themselves against their chosen
SDL include paths. See
<https://github.com/PavoReal/airwave>'s `airwave-gui` build for an example.
```

### 5. Commit and push

```bash
git add build.zig.zon build.zig README.md
git commit -m "Remove zsdl dependency

Zig 0.16 eagerly compiles every dependency's build.zig regardless of
the .lazy flag. zsdl's build.zig uses pre-0.16 Compile APIs that moved
to Module, which breaks any downstream that consumes zgui on 0.16 even
when no SDL backend is selected.

Downstreams that want SDL backends should use .no_backend and compile
imgui_impl_sdl*.cpp themselves."
git push -u origin airwave-no-zsdl
```

Capture the resulting commit SHA — you'll need it in the next step. Save it as `$FORK_SHA`:

```bash
FORK_SHA=$(git rev-parse HEAD)
echo "$FORK_SHA"
```

### 6. Update airwave to point at the fork

Switch back to the airwave repo and update `build.zig.zon`:

```bash
cd /Users/peacock/workspace/airwave
```

Replace the current `.zgui = { ... }` block (currently at lines 46–49 of `build.zig.zon`):

```zig
// BEFORE:
// TODO(zgui-upstream): swap to zig-gamedev/zgui once PR #103 lands.
// Tracking: https://github.com/zig-gamedev/zgui/pull/103
// To swap: `zig fetch --save=zgui git+https://github.com/zig-gamedev/zgui#<ref>`
.zgui = .{
    .url = "git+https://github.com/cyberegoorg/zgui.git?ref=upgrade_to_zig_16#dc4344aa02b78465bb0d769b5889a99feae4ca6b",
    .hash = "zgui-0.6.0-dev--L6sZMuAcQDjqZqVM-2t89cR17mtI2Y9Z5zI_CxSiUzj",
},
```

Easiest way to update both the URL and the hash in one go:

```bash
zig fetch --save=zgui "git+https://github.com/PavoReal/zgui.git?ref=airwave-no-zsdl#$FORK_SHA"
```

That command mutates `build.zig.zon` and writes the correct new hash. Inspect the diff afterward.

Update the tracking comment to reflect the new reality:

```zig
// TODO(zgui-upstream): swap to zig-gamedev/zgui once PR #103 lands and zsdl
// is made Zig-0.16-compatible.
// Tracking: https://github.com/zig-gamedev/zgui/pull/103
// Fork: PavoReal/zgui@airwave-no-zsdl — removes the unused zsdl dep that
// blocks Zig 0.16 eager-build-graph compilation.
// To swap back: `zig fetch --save=zgui git+https://github.com/zig-gamedev/zgui#<ref>`
```

### 7. Remove the project-local zsdl patch

The patched file under `zig-pkg/zsdl-.../build.zig` is no longer needed and would become misleading. Clean the project cache and re-fetch:

```bash
rm -rf /Users/peacock/workspace/airwave/zig-pkg
rm -rf /Users/peacock/workspace/airwave/.zig-cache
rm -rf /Users/peacock/workspace/airwave/zig-out
```

After the next `zig build`, confirm that no `zsdl-*` directory is written into `zig-pkg/`:

```bash
ls /Users/peacock/workspace/airwave/zig-pkg/ | grep -i zsdl
# must print nothing
```

### 8. Verify

```bash
cd /Users/peacock/workspace/airwave
zig build                         # must succeed with no errors
ls zig-out/bin/airwave-gui        # must exist
./zig-out/bin/airwave-gui &       # must open a window
PID=$!
sleep 2
kill -0 $PID && echo "OK: alive"  # must print OK
kill $PID; wait $PID 2>/dev/null
```

If the window opens, renders content, and exits cleanly on `kill`, acceptance criteria are met.

## Rollback

If the fork breaks something non-obvious:

1. `cd /Users/peacock/workspace/airwave && git checkout -- build.zig.zon` — reverts the `.zgui` URL/hash.
2. Re-apply the zsdl patches under `zig-pkg/zsdl-.../build.zig` (see git history of this repo for the exact diff) OR let the next `zig build` fail and re-patch by hand.
3. Leave the fork on GitHub — it costs nothing to keep.

## Gotchas / things to watch for

- **Hash match**: `zig fetch --save` in step 6 will compute a new hash that differs from anything previously seen. Don't copy hashes from this plan — let `zig fetch` populate them.
- **Branch protection**: if GitHub rejects `push -u origin airwave-no-zsdl` because of branch protection on `PavoReal/zgui`, push to a personal branch under a different prefix and retarget the airwave zon accordingly.
- **Empty switch arms**: after deleting the `if` blocks, make sure the surrounding arm still compiles. Each arm's remaining body is an `imgui_mod.addCSourceFiles(...)` call — keep it.
- **Don't delete the backend enum tags**. The Zig fork should still accept `.sdl3_gpu` etc. as options — they just won't work without header paths. This preserves API shape so callers who don't use SDL backends keep working unchanged.
- **Cache location**: Zig 0.16 uses both `~/.cache/zig/p/` (global) and `<project>/zig-pkg/` (project-local). Clean *both* when verifying a clean-state build — `rm -rf ~/.cache/zig/p/zsdl-* zig-pkg` to be safe.
- **No commit/push to airwave `main`**: this plan only edits `build.zig.zon`. Do not commit airwave until the human reviews.

## Files touched

- `PavoReal/zgui@airwave-no-zsdl`:
  - `build.zig.zon` — remove `.zsdl` entry
  - `build.zig` — remove 8 `b.lazyDependency("zsdl", .{})` blocks
  - `README.md` — add fork note
- `/Users/peacock/workspace/airwave`:
  - `build.zig.zon` — repoint `.zgui` at the fork, update comment
  - delete `zig-pkg/` and `.zig-cache/` (caches only, no source)

## Success signal to report back

A short message like:

> Forked to `PavoReal/zgui@airwave-no-zsdl` at `<sha>`. `build.zig.zon` now
> points at it. Clean-cache `zig build` succeeds; `airwave-gui` opens a
> window and exits cleanly. Removed `zig-pkg/` entirely.

plus the diff of `build.zig.zon` and the URL of the fork branch.
