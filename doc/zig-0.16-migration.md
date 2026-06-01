# Zig 0.15.x → 0.16.0 Migration Reference

A practical, **verified** guide for porting a real-world Zig program (CLI + HTTP
server, file I/O, subprocesses, JSON, C interop) from Zig 0.15.1/0.15.2 to
**0.16.0**. Written while migrating `fj`, but the deltas are general.

> **Every API in this document was verified against the installed 0.16.0
> stdlib**, not against blog posts or release-note digests. Several widely-cited
> "0.16 changes" are wrong — they are flagged inline below.

The single defining change in 0.16 is that **I/O is now explicit**: a
`std.Io` value must be threaded into every blocking operation (file open/read/
write/close, directory ops, subprocess spawn, `cwd` changes, stdout/stderr
writes). You obtain it once in `main` and pass it down. Almost all of the
mechanical churn flows from this one fact.

---

## 1. The entry point: `main(init: std.process.Init)`

In 0.16 the runtime builds the allocators, the env map, and a default
`std.Io` for you, and hands them to `main` via `std.process.Init`. You no
longer create a `GeneralPurposeAllocator`, an `ArenaAllocator`, or call
`std.process.argsWithAllocator` yourself.

`std.process.Init` (verified, `std/process.zig:30`):

```zig
pub const Init = struct {
    minimal: Minimal,                 // .args: process.Args, .environ: process.Environ
    arena: *std.heap.ArenaAllocator,  // process-lifetime, threadsafe, freed on exit
    gpa: Allocator,                   // default GPA; leak-checked in Debug
    io: Io,                           // default std.Io (a std.Io.Threaded under the hood)
    environ_map: *Environ.Map,        // env vars; .get(name) -> ?[]const u8 (NOT threadsafe)
    preopens: Preopens,

    pub const Minimal = struct {
        environ: Environ,
        args: Args,
    };
};
```

Three `main` shapes are accepted (dispatched on the first param's type):

```zig
pub fn main() !void                            // still valid; no setup handed in
pub fn main(m: std.process.Init.Minimal) !void // just { args, environ }
pub fn main(init: std.process.Init) !void      // the full thing — adopt this
```

Before / after:

```zig
// 0.15
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();
    var cmd_arena = std.heap.ArenaAllocator.init(allocator);
    defer cmd_arena.deinit();
    const arena = cmd_arena.allocator();
    var pargs = try std.process.argsWithAllocator(allocator);
    defer pargs.deinit();
    ...
}

// 0.16
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    var args_it: std.process.Args.Iterator = .init(init.minimal.args); // posix/macOS
    // no deinit of gpa/arena/args needed — runtime owns them
    ...
}
```

Notes:
- The runtime's GPA is already leak-checked in Debug; do not wrap your own.
- `init.arena` is a `*ArenaAllocator`; call `.allocator()` to get the
  `Allocator`. It is freed automatically at process exit.

---

## 2. Command-line arguments: `Args` / `Args.Iterator`

`std.process.ArgIterator` is **gone**. The type is now `std.process.Args`
(a thin wrapper over the platform arg vector) with a nested
`std.process.Args.Iterator`.

```zig
// 0.15
var it = try std.process.argsWithAllocator(allocator);
defer it.deinit();

// 0.16 — from init.minimal.args, no allocation on posix
var it: std.process.Args.Iterator = .init(init.minimal.args);
// cross-platform (Windows/WASI need an allocator):
// var it = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
while (it.next()) |arg| { ... }   // next()/skip() unchanged, return ?[:0]const u8
```

If a library function takes `*std.process.ArgIterator` (e.g. a CLI parser),
change the parameter type to `*std.process.Args.Iterator`. The `.next()` /
`.skip()` API is unchanged.

---

## 3. `std.fs` is gutted — `File`/`Dir`/`cwd` moved under `std.Io`

`std.fs` keeps only: `path`, `base64` helpers, `max_path_bytes`,
`max_name_bytes`. The actual filesystem types moved:

| 0.15 | 0.16 |
|---|---|
| `std.fs.File` (type) | `std.Io.File` |
| `std.fs.Dir` (type) | `std.Io.Dir` |
| `std.fs.cwd()` | `std.Io.Dir.cwd()` *(no `io` needed just to get the handle)* |
| `std.fs.path.…` | `std.fs.path.…` *(UNCHANGED — still under `std.fs`)* |

Every **operation** on a `Dir`/`File` now takes `io` as the first arg after
the receiver:

| 0.15 | 0.16 |
|---|---|
| `dir.openFile(p, .{})` | `dir.openFile(io, p, .{})` |
| `dir.createFile(p, .{})` | `dir.createFile(io, p, .{})` |
| `dir.openDir(p, .{})` | `dir.openDir(io, p, .{})` |
| `dir.deleteFile(p)` | `dir.deleteFile(io, p)` |
| `dir.deleteTree(p)` | `dir.deleteTree(io, p)` |
| `dir.rename(a, b)` | `dir.rename(io, a, b)` |
| `dir.copyFile(a, d, b, .{})` | `dir.copyFile(io, …)` |
| `dir.access(p, .{})` | `dir.access(io, p, .{})` |
| `dir.statFile(p)` | `dir.statFile(io, p, .{})` |
| `std.fs.openFileAbsolute(p, .{})` | `std.Io.Dir.openFileAbsolute(io, p, .{})` |
| `file.close()` | `file.close(io)` |

### Renamed `Dir` methods (these tripped up the original plan)

| 0.15 | 0.16 |
|---|---|
| `dir.makePath(p)` | `dir.createDirPath(io, p)` |
| `dir.makeDir(p)` | `dir.createDir(io, p, permissions)` |
| `dir.realpath(p, buf)` | `dir.realPathFile(io, p, buf)` (note capital **P**) |
| `dir.realpathAlloc(a, p)` | `dir.realPathFileAlloc(io, p, allocator)` → `[:0]u8` |

> ❌ The original migration plan claimed `std.fs.cwd().makePath` →
> `…makePath` with just an added `io`, and `realpath`/`realpathAlloc` keep
> their lowercase names. **Wrong.** They were renamed as above.

---

## 4. Reading a whole file to a string

`File.readToEndAlloc` is gone. There are two idiomatic replacements:

**Best — use the built-in `Dir.readFileAlloc` (verified `Io/Dir.zig:1326`):**

```zig
// 0.16 — one call, opens+reads+closes, caller frees the returned []u8
const data = try dir.readFileAlloc(io, sub_path, gpa, .limited(max_bytes));
```

> ❌ The plan said a custom `fsutil.readFileAlloc` helper is "worth writing."
> Unnecessary — the stdlib ships `Dir.readFileAlloc(io, path, gpa, limit)`.
> A thin wrapper is only worth it if you want a project-default size limit.

**When you already hold an open `File`** (or need a reader for other reasons),
get a reader and use `Reader.allocRemaining` (verified `Io/Reader.zig:292`):

```zig
var buf: [4096]u8 = undefined;             // working buffer (can be &.{} to force heap)
var fr = file.reader(io, &buf);
const data = try fr.interface.allocRemaining(gpa, .limited(max_bytes));
```

The limit argument is an `Io.Limit`: `.limited(n)` or `.unlimited`.

---

## 5. Readers and Writers (`std.io` → `std.Io`)

The lowercase `std.io` namespace alias is **removed**. Use `std.Io`.

| 0.15 | 0.16 |
|---|---|
| `std.io.Writer` | `std.Io.Writer` |
| `std.io.Reader` | `std.Io.Reader` |
| `std.io.Writer.fixed(buf)` | `std.Io.Writer.fixed(buf)` *(method unchanged)* |
| `std.io.Writer.Allocating.init(a)` | `std.Io.Writer.Allocating.init(a)` *(unchanged; no io)* |
| `?*std.io.Writer` param | `?*std.Io.Writer` |

Getting a writer/reader from a `File` now needs `io`, and you still reach the
`std.Io.Writer`/`std.Io.Reader` through `.interface`:

```zig
// 0.15
var fw = file.writer(&buf);
const w = &fw.interface;

// 0.16
var fw = file.writer(io, &buf);
const w = &fw.interface;          // .interface is still std.Io.Writer
```

`Writer.Allocating` does **not** take `io` — it writes to memory:

```zig
var aw = std.Io.Writer.Allocating.init(gpa);
defer aw.deinit();
try aw.writer.print("{s}", .{x});   // unchanged
const owned = aw.written();
```

### stdout / stderr / stdin

```zig
// 0.15
var sw = std.fs.File.stdout().writer(&buf);
try sw.interface.print(...);

// 0.16
var sw = std.Io.File.stdout().writer(io, &buf);   // .stdout()/.stderr()/.stdin() need no io to obtain
try sw.interface.print(...);
```

---

## 6. Environment variables: `getEnvVarOwned` removed

`std.process.getEnvVarOwned` is gone. Read from the env map handed to `main`:

```zig
// 0.15
const home = try std.process.getEnvVarOwned(allocator, "HOME");

// 0.16
const home: ?[]const u8 = init.environ_map.get("HOME");   // borrowed, do not free
```

Thread `init.environ_map` (or the resolved values) into whatever needs them.
The map is **not** threadsafe; treat it as read-only after startup.

---

## 7. `std.process` miscellany

| 0.15 | 0.16 |
|---|---|
| `std.process.argsWithAllocator(a)` | use `init.minimal.args` + `Args.Iterator` |
| `std.process.changeCurDir(path)` | `std.process.setCurrentDir(io, dir)` — **takes an `Io.Dir`, not a path** |
| `std.process.getCwdAlloc(a)` | `std.process.currentPathAlloc(io, a)` → `[:0]u8` |
| `std.process.Child.run(.{…})` | `std.process.run(gpa, io, .{…})` |
| `std.process.Child.RunResult` (type) | `std.process.RunResult` |
| `std.process.fatal(…)` | still exists — keep |

> ❌ The plan wrote `std.process.setCurrentDir(io, p)` with `p` a path string.
> The real signature is `setCurrentDir(io: Io, dir: Io.Dir)` — you must
> `openDir` the path first (and close it after), e.g.:
> ```zig
> var d = try std.Io.Dir.cwd().openDir(io, path, .{});
> defer d.close(io);
> try std.process.setCurrentDir(io, d);
> ```

`std.process.run` returns `RunResult { term, stdout, stderr }`; `stdout`/
`stderr` are owned `[]u8` you must free with `gpa`. The options struct is
`std.process.RunOptions` (`.argv`, `.cwd`, `.max_output_bytes`, …).

---

## 8. Subprocesses

```zig
// 0.15
const result = std.process.Child.run(.{
    .allocator = allocator,
    .argv = &.{ "git", "status" },
    .cwd = home,
});

// 0.16
const result = try std.process.run(gpa, io, .{
    .argv = &.{ "git", "status" },
    .cwd = home,
});
defer gpa.free(result.stdout);
defer gpa.free(result.stderr);
```

Function-parameter and field types that referenced `std.process.Child.RunResult`
become `std.process.RunResult`.

---

## 9. `std.debug.writeStackTrace` + the removal of `std.io.tty`

`std/io/tty.zig` is **gone**. `std.debug.writeStackTrace` was rewritten to
take an `std.Io.Terminal` instead of `(writer, debug_info, tty_config)`:

```zig
// 0.15
const ttyConfig: std.io.tty.Config = .no_color;
const dbg = try std.debug.getSelfDebugInfo();
try std.debug.writeStackTrace(trace, &writer, dbg, ttyConfig);

// 0.16  (writeStackTrace(st, t: Io.Terminal); no debug-info arg)
const term: std.Io.Terminal = .{ .writer = &writer, .mode = .no_color };
try std.debug.writeStackTrace(trace, term);
```

`std.Io.Terminal` is `{ writer: *Io.Writer, mode: Mode }` where `Mode` is a
tagged union (`.no_color`, `.escape_codes`, `.windows_api`). Use
`Terminal.Mode.detect(io, file, no_color, clicolor_force)` to auto-select.

---

## 10. Threading `io`: keep it io-impl-independent (the global is a smell)

The *whole point* of explicit `io` is that code is independent of the I/O
implementation: the caller — ultimately `main` — chooses it and threads it down
**like an allocator**. So the idiomatic move is to take `io: std.Io` as a
parameter (or store it on a struct at construction, next to `gpa`), sourced from
`init.io` in `main(init: std.process.Init)`. Libraries should accept `io` in
their public API rather than conjure one internally.

```zig
const io = std.Io.Threaded.global_single_threaded.io(); // ← hardcodes one impl
```

Reaching for the single-threaded global **defeats io-independence** — it pins a
specific implementation deep in the code, so the program can no longer be driven
by a different `io` (async/event-loop, a test double, a different threading
model). Treat it as a *last resort*, only for contexts whose signature is fixed
by an external contract that `main` cannot reach — e.g. `std.Options.logFn` or a
panic handler. Even there, prefer capturing the real `io` once at startup into
module state over hardcoding the single-threaded one. (`global_single_threaded`
verified at `Io/Threaded.zig:1704`.)

> **Migrating fast vs. migrating right:** during a first pass it is tempting to
> drop `global_single_threaded.io()` wherever the compiler demands an `io` you
> don't have in scope. That compiles and runs, but each such site is debt —
> revisit them and thread `io` from `main` instead.

---

## 11. Verified **UNCHANGED** — do not churn these

- **`std.ArrayList`**: already the unmanaged form (`.empty`, `append(gpa, x)`,
  `appendSlice(gpa, …)`). `std.ArrayListUnmanaged` is an alias of `ArrayList`.
- **`StringArrayHashMapUnmanaged`** / `put(gpa, …)` — unchanged.
- **JSON**: `std.json.parseFromSliceLeaky`, `std.json.Stringify.value(v, opts, *Writer)`,
  `std.json.Stringify.valueAlloc(gpa, v, opts)` — same signatures. Only the
  `*Writer` you pass in now comes from an io-threaded `file.writer(io, buf).interface`.
- **`std.fmt`**: `allocPrint`, `bufPrint`, `allocPrintSentinel` — unchanged.
- **`std.fs.path.*`**: `extension`, `join`, `basename`, … — unchanged.
- **`Writer.fixed`**, **`Writer.Allocating`** — methods unchanged (no `io`).

---

## 12. Dependencies under 0.16

- Third-party `build.zig` files commonly break on `std.process.getEnvVarOwned`
  (build scripts run as normal programs). Fix the same way (env map isn't
  available in `build`, so use `std.process.getEnvVarOwned`'s replacement…
  but note `build.zig` has no `Init`: read the option via `b.graph` env or a
  build option instead). In practice, replacing the env-var lookup with a
  `b.option(...)` default is the cleanest fix.
- Frameworks that wrap a C event loop (e.g. **zap** over facil.io) mostly
  **bypass** `std.Io` networking — their breaking surface is small and confined
  to a few `std.io`→`std.Io` renames and the `writeStackTrace` change. Test
  builds (`src/tests/…`) may use `std.http.Client`/`Writer.Allocating` but those
  don't compile when the package is imported as a module, so they don't block
  consumers.
- Pin local copies with `.path` while migrating:
  ```zig
  .zap  = .{ .path = "deps/zap" },
  .zli  = .{ .path = "deps/zli" },
  .zeit = .{ .path = "deps/zeit" },
  ```

---

## 13. Recommended migration order

1. **Entry point** (`main` → `Init`): obtain `io`, `gpa`, `arena`, args, env map.
2. **Thread `io`** onto your central state struct(s) and per-request context.
3. **Foundational utils first** (filesystem helper, logging, subprocess, error
   reporting) — everything else calls these, so their signatures must settle early.
4. **Leaf modules** (endpoint handlers, isolated features) — same mechanical
   transform, parallelizable once core signatures are frozen.
5. **Build, fix, verify.** Let the compiler drive: `zig build` lists every
   remaining site. Bump `minimum_zig_version = "0.16.0"` last.

The transform is overwhelmingly mechanical: add `io` as the first operation
arg, `std.io`→`std.Io`, `readToEndAlloc`→`readFileAlloc`, `close()`→`close(io)`,
`getEnvVarOwned`→`environ_map.get`. The non-mechanical bits are the renamed
`Dir` methods (§3), `setCurrentDir` taking a `Dir` (§7), and `writeStackTrace`
(§9).

---

# Part II — Deltas discovered during the actual build

Everything above was verified *before* compiling. The list below is everything
the compiler surfaced *during* the migration that the pre-build reference missed.
These are at least as important as Part I — several are pervasive.

## 14. Builtin reflection: `@Type` is gone, split into per-kind builtins

`@Type(info)` was removed. It is replaced by a family of builtins, one per type
kind: `@Struct`, `@Enum`, `@EnumLiteral`, `@Union`, `@Fn`, `@Int`, `@Float`,
`@Pointer`, `@Vector`, `@Tuple` (plus `@FieldType`). `@typeInfo`/`@TypeOf` are
unchanged.

```zig
// 0.15
comptime scope: @Type(.enum_literal),
// 0.16
comptime scope: @EnumLiteral(),
```

`@Struct` takes **five positional args** — and its field model changed from one
`[]StructField` to three parallel arrays (names / types / attributes):

```zig
// 0.15
return @Type(.{ .@"struct" = .{
    .layout = .auto, .fields = &fields, .decls = &.{}, .is_tuple = false,
} });
// 0.16: @Struct(layout, backing_integer, field_names, field_types, field_attrs)
return @Struct(.auto, null, &names, &types, &attrs);
// names: []const [:0]const u8, types: []const type,
// attrs: []const std.builtin.Type.StructField.Attributes
//   ( .{ .@"comptime", .@"align", .default_value_ptr } )
```

## 15. `std.process.exit` (not `std.posix.exit`)

`std.posix.exit` is gone → `std.process.exit(code)`.

## 16. Threading primitives moved to `std.Io`

`std.Thread.Mutex` and `std.Thread.RwLock` did **not** disappear — they **moved**
to `std.Io.Mutex` and `std.Io.RwLock` (both exist; verified). They take an `Io`
on the blocking ops: `m.lock(io)` / `m.lockUncancelable(io)` / `m.unlock(io)` /
`m.tryLock()`; RwLock adds `lockShared(io)` / `lockSharedUncancelable(io)` /
`unlockShared(io)`. There is also `std.Io.Condition`. `std.Thread.getCurrentId()`
and `std.Thread.spawn()` still exist.

**Do not roll your own spinlock.** Use `std.Io.Mutex`/`std.Io.RwLock` and obtain
the `io` the idiomatic way — threaded from `main(init)` like an allocator (§10),
e.g. stored on the struct that owns the lock at construction:

```zig
// field
lock: std.Io.Mutex = .init,
// use (io threaded in from main, not conjured):
self.lock.lockUncancelable(io);
defer self.lock.unlock(io);
```

(The fast/uncontended path is pure atomics; `io` is only consulted to futex-wait
on contention — but that's no reason to hardcode the global single-threaded impl;
thread the real one. See §10.)

`std.Thread.sleep(ns)` is also gone → `io.sleep(std.Io.Duration.fromNanoseconds(ns), .awake)`,
with `io` threaded from `main` per §10.

## 17. Wall-clock time needs `io`

`std.time.nanoTimestamp()` / `std.time.timestamp()` were removed (clocks are an
`Io` capability now):

```zig
const ns: i96 = std.Io.Timestamp.now(io, .real).nanoseconds; // epoch nanoseconds
const secs: i64 = std.Io.Timestamp.now(io, .real).toSeconds();
```

`Clock` values are `.real` (wall clock), `.awake`, `.boot` — *not* `.realtime`.

## 18. `std.Io.File` lost its direct read/write/seek methods

`File.writeAll`, `File.readAll`, `File.getEndPos`, `File.seekTo`,
`File.setEndPos` no longer exist on `File`. They live on the `File.Writer` /
`File.Reader` returned by `file.writer(io, &buf)` / `file.reader(io, &buf)`:

| 0.15 | 0.16 |
|---|---|
| `file.writeAll(bytes)` | `var w = file.writer(io,&buf); try w.interface.writeAll(bytes); try w.interface.flush();` |
| `file.getEndPos()` | `(try file.stat(io)).size` |
| `file.seekTo(p)` | `w.seekTo(p)` (on the `File.Writer`/`File.Reader`) |
| `file.setEndPos(n)` | `w.end()` — flushes **and** truncates to the current write position |

Worth a `fsutil.writeAll(io, file, bytes)` helper (mirrors the `readToEndAlloc`
one). **Buffered stdout/file writers must be `flush()`ed** or output is lost —
0.16 buffers where 0.15 often didn't (a `version` command silently printed
nothing until flush was added).

## 19. `std.process.run` — `RunOptions` / `RunResult` / `Term` / `Cwd`

```zig
// 0.15
std.process.Child.run(.{ .allocator = a, .argv = argv, .cwd = path,
                         .max_output_bytes = n, .expand_arg0 = .expand });
// 0.16
std.process.run(gpa, io, .{
    .argv = argv,
    .cwd = .{ .path = path },            // Child.Cwd union: .inherit | .path | .dir
    .stdout_limit = .limited(n),          // max_output_bytes → split per-stream
    .stderr_limit = .limited(n),
    .expand_arg0 = .expand,
});
```

- `RunResult.term` variants are **lowercase**: `.exited` / `.signal` / `.stopped`
  / `.unknown` (were `.Exited` / `.Signal` / …).
- `.signal` / `.stopped` payloads are now `std.posix.SIG` enums — format with
  `@intFromEnum(sig)`, not `{d}` directly.
- `std.process.Child.RunResult` (the type) → `std.process.RunResult`.

## 20. Smaller renames the compiler will flag

| 0.15 | 0.16 |
|---|---|
| `std.heap.GeneralPurposeAllocator(cfg)` | `std.heap.DebugAllocator(cfg)` |
| `std.mem.trimRight` / `trimLeft` | `std.mem.trimEnd` / `trimStart` (`trim` unchanged) |
| `std.crypto.random.bytes(buf)` | `try io.randomSecure(buf)` (or `io.random(buf)`) |
| `dir.createFile(p, .{ .mode = m })` | `.{ .permissions = @enumFromInt(m) }` (`CreateFileOptions.mode` → `permissions`) |
| `std.debug.lockStdErr()` / `unlockStdErr()` | `std.debug.lockStderr(&buf)` / `unlockStderr()` |
| `dirIterator.next()` | `dirIterator.next(io)` (the `Dir.Iterator`; *not* `std.mem` token iterators) |
| `switch (x) { 'a'...'z' => \|_\| {...} }` | capture discard `\|_\|` is rejected — omit it: `=> {...}` |
| `fn f(Types: []const type)` used in `inline for` | must be `comptime Types: []const type` |

## 21. `writeStackTrace` + two distinct `StackTrace` types

`@errorReturnTrace()` still yields a `std.builtin.StackTrace`
(`{ index, instruction_addresses }`), but `std.debug.writeStackTrace` now takes
`*const std.debug.StackTrace` — a **different** struct
(`{ return_addresses, skipped: SkippedAddresses }`) — plus an `std.Io.Terminal`
instead of `(writer, debug_info, tty_config)`. Convert explicitly:

```zig
const dbg: std.debug.StackTrace = .{
    .return_addresses = bt.instruction_addresses[0..@min(bt.index, bt.instruction_addresses.len)],
    .skipped = .none, // SkippedAddresses enum
};
const term: std.Io.Terminal = .{ .writer = &writer, .mode = .no_color };
try std.debug.writeStackTrace(&dbg, term);
```

## 22. `build.zig` API: artifacts take a `root_module`

`addTest` / `addExecutable` / `addObject` no longer accept `root_source_file`
directly — pass a `root_module`:

```zig
// 0.15
b.addTest(.{ .root_source_file = b.path("src/x.zig"), .target = t, .optimize = o });
// 0.16
const m = b.addModule("x", .{ .root_source_file = b.path("src/x.zig"), .target = t, .optimize = o });
b.addTest(.{ .root_module = m });
```

Build scripts that read env vars use `b.graph.environ_map.get(name)` (there is no
`Init` in `build()`); prefer a `b.option(...)` with a default instead.

## 23. translate-c is now **Aro**, and `@cImport` can silently drop symbols

0.16 replaced the clang-based C translator with **Aro**. On large single-header
C libraries (here: vendored **miniz.h**), Aro fails to translate parts of the
header and `@cImport` then exposes only a fraction of the symbols — the missing
ones surface as *"struct 'cimport' has no member named 'X'"* even though `X` is
plainly defined in the header.

Workaround when a needed symbol is dropped: bypass `@cImport` for that symbol and
declare the bindings **manually**. The C object is still linked, so `extern fn`
declarations resolve, and an `extern struct` kept byte-compatible with the C
layout works for stack-allocated / pointer-passed structs:

```zig
const c = struct {
    const mz_zip_archive = extern struct { /* fields in C order; pointers as ?*anyopaque */ };
    extern fn mz_zip_writer_init_file(p: *mz_zip_archive, name: [*:0]const u8, reserve: u64) c_int;
    // …
};
```

## 24. Sanity-check list the compiler walked us through (in order)

dep `build.zig` (`root_source_file`→`root_module`) → `@Type` split → `|_|` capture
→ `std.posix.exit` → `std.time.nanoTimestamp` → `File.getEndPos` →
`RunOptions.max_output_bytes` → `Term.Exited` → `std.mem.trimRight` →
`std.crypto.random` → `CreateFileOptions.mode` → `std.Thread.Mutex` →
`std.Thread.RwLock` → `std.Thread.sleep` → `writeStackTrace`/`StackTrace` →
`std.heap.GeneralPurposeAllocator` → `std.io.Writer.Allocating` →
`comptime []const type` → `@cImport` (Aro) dropped symbols. Lean on
`zig build` — it reports one root-cause site at a time; fix, rebuild, repeat.
