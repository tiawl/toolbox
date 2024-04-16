const std = @import ("std");

pub fn isCSource (name: [] const u8) bool
{
  return std.mem.endsWith (u8, name, ".c");
}

pub fn isCppSource (name: [] const u8) bool
{
  return std.mem.endsWith (u8, name, ".cc") or
   std.mem.endsWith (u8, name, ".cpp");
}

pub fn isSource (name: [] const u8) bool
{
  return isCSource (name) or isCppSource (name);
}

pub fn isCHeader (name: [] const u8) bool
{
  return std.mem.endsWith (u8, name, ".h");
}

pub fn isCppHeader (name: [] const u8) bool
{
  return std.mem.endsWith (u8, name, ".hpp") or
    std.mem.endsWith (u8, name, ".hpp11");
}

pub fn isHeader (name: [] const u8) bool
{
  return isCHeader (name) or isCppHeader (name);
}

pub fn addHeader (lib: *std.Build.Step.Compile, source: [] const u8,
  dest: [] const u8, ext: [] const [] const u8) void
{
  std.debug.print ("[{s} header] {s}\n", .{ lib.name, source, });
  lib.installHeadersDirectory (.{ .path = source, }, dest,
    .{ .include_extensions = ext, });
}

pub fn addInclude (lib: *std.Build.Step.Compile, path: [] const u8) void
{
  const builder = lib.step.owner;
  const lazy = std.Build.LazyPath { .path = builder.dupe (path), };
  std.debug.print ("[{s} include] {s}\n",
    .{ lib.name, lazy.getPath (builder), });
  lib.addIncludePath (lazy);
}

pub fn addSource (lib: *std.Build.Step.Compile, root_path: [] const u8,
  base_path: [] const u8, flags: [] const [] const u8) !void
{
  const builder = lib.step.owner;
  const source_path = try std.fs.path.join (builder.allocator,
    &.{ root_path, base_path, });
  std.debug.print ("[{s} source] {s}\n", .{ lib.name, source_path, });
  lib.addCSourceFile (.{
    .file = try std.fs.path.relative (builder.allocator,
      builder.build_root.path.?, source_path),
    .flags = flags,
  });
}

pub fn write (path: [] const u8, name: [] const u8,
  content: [] const u8) !void
{
  std.debug.print ("[write {s}/{s}]\n", .{ path, name, });
  var dir = try std.fs.openDirAbsolute (path, .{});
  defer dir.close ();
  try dir.writeFile (name, content);
}

pub fn make (path: [] const u8) !void
{
  std.debug.print ("[make {s}]\n", .{ path, });
  std.fs.makeDirAbsolute (path) catch |err|
    if (err != error.PathAlreadyExists) return err;
}

pub fn copy (src: [] const u8, dest: [] const u8) !void
{
  std.debug.print ("[copy {s} {s}]\n", .{ src, dest });
  try std.fs.copyFileAbsolute (src, dest, .{});
}

pub fn run (builder: *std.Build, proc: struct { argv: [] const [] const u8,
  cwd: ?[] const u8 = null, env: ?*const std.process.EnvMap = null,
  wait: ?*const fn () void = null, }) !void
{
  var stdout = std.ArrayList (u8).init (builder.allocator);
  var stderr = std.ArrayList (u8).init (builder.allocator);
  errdefer { stdout.deinit (); stderr.deinit (); }

  std.debug.print ("\x1b[35m[{s}]\x1b[0m\n",
    .{ try std.mem.join (builder.allocator, " ", proc.argv), });

  var child = std.ChildProcess.init (proc.argv, builder.allocator);

  child.stdin_behavior = .Ignore;
  child.stdout_behavior = .Pipe;
  child.stderr_behavior = .Pipe;
  child.cwd = proc.cwd;
  child.env_map = proc.env;

  try child.spawn ();

  var term: std.ChildProcess.Term = undefined;
  if (proc.wait) |wait|
  {
    wait ();
    term = try child.kill ();
  } else {
    try child.collectOutput (&stdout, &stderr, std.math.maxInt (usize));
    term = try child.wait ();
  }
  const exit_success = std.ChildProcess.Term { .Exited = 0, };
  if (stdout.items.len > 0) std.debug.print ("{s}", .{ stdout.items, });
  if (stderr.items.len > 0 and !std.meta.eql (term, exit_success))
    std.debug.print ("\x1b[31m{s}\x1b[0m", .{ stderr.items, });
  if (proc.wait == null) try std.testing.expectEqual (term, exit_success);
}

pub fn clone (builder: *std.Build, url: [] const u8, tag: [] const u8,
  path: [] const u8) !void
{
  try run (builder, .{ .argv = &[_][] const u8 { "git", "clone",
    "--branch", tag, "--depth", "1", url, path, }, });
}

pub fn build (builder: *std.Build) !void
{
  _ = builder.addModule ("toolbox",
    .{ .root_source_file = builder.addWriteFiles ().add ("empty.zig", ""), });
}
