const std = @import ("std");

pub fn is_source_file (name: [] const u8) bool
{
  return std.mem.endsWith (u8, name, ".c") or
    std.mem.endsWith (u8, name, ".cc") or
    std.mem.endsWith (u8, name, ".cpp");
}

pub fn is_header_file (name: [] const u8) bool
{
  return std.mem.endsWith (u8, name, ".h") or
    std.mem.endsWith (u8, name, ".hpp");
}

pub fn write (path: [] const u8, name: [] const u8, content: [] const u8) !void
{
  std.debug.print ("[write {s}/{s}]\n", .{ path, name, });
  var dir = try std.fs.openDirAbsolute (path, .{});
  defer dir.close ();
  try dir.writeFile (name, content);
}

pub fn make (path: [] const u8) !void
{
  std.debug.print ("[make {s}]\n", .{ path, });
  std.fs.makeDirAbsolute (path) catch |err| if (err != error.PathAlreadyExists) return err;
}

pub fn copy (src: [] const u8, dest: [] const u8) !void
{
  std.debug.print ("[copy {s} {s}]\n", .{ src, dest });
  try std.fs.copyFileAbsolute (src, dest, .{});
}

pub fn run (builder: *std.Build, proc: struct { argv: [] const [] const u8, cwd: ?[] const u8 = null, env: ?*const std.process.EnvMap = null, wait: ?*const fn () void = null, }) !void
{
  var stdout = std.ArrayList (u8).init (builder.allocator);
  var stderr = std.ArrayList (u8).init (builder.allocator);
  errdefer { stdout.deinit (); stderr.deinit (); }

  std.debug.print ("\x1b[35m[{s}]\x1b[0m\n", .{ try std.mem.join (builder.allocator, " ", proc.argv), });

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
  if (stdout.items.len > 0) std.debug.print ("{s}", .{ stdout.items, });
  if (stderr.items.len > 0 and !std.meta.eql (term, std.ChildProcess.Term { .Exited = 0, })) std.debug.print ("\x1b[31m{s}\x1b[0m", .{ stderr.items, });
  if (proc.wait == null) try std.testing.expectEqual (term, std.ChildProcess.Term { .Exited = 0, });
}

pub fn build (builder: *std.Build) !void
{
  _ = builder.addModule ("toolbox", .{ .root_source_file = builder.addWriteFiles ().add ("empty.zig", ""), });
}
