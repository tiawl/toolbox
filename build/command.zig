const std = @import ("std");

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
  wait: ?*const fn () void = null, stdout: ?*[] const u8 = null,
  ignore_errors: bool = false, }) !void
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
  if (stderr.items.len > 0 and !std.meta.eql (term, exit_success))
    std.debug.print ("\x1b[31m{s}\x1b[0m", .{ stderr.items, });
  if (!proc.ignore_errors and proc.wait == null)
    try std.testing.expectEqual (term, exit_success);

  if (proc.stdout) |out|
    out.* = std.mem.trim (u8, try stdout.toOwnedSlice (), " \n")
  else std.debug.print ("{s}", .{ stdout.items, });
}

pub fn tag (builder: *std.Build, repo: [] const u8) ![] const u8
{
  const path = try builder.build_root.join (builder.allocator,
    &.{ ".versions", repo, });
  return std.mem.trim (u8, try builder.build_root.handle.readFileAlloc (
    builder.allocator, path, std.math.maxInt (usize)), " \n");
}

pub fn clone (builder: *std.Build, url: [] const u8, repo: [] const u8,
  path: [] const u8) !void
{
  try run (builder, .{ .argv = &[_][] const u8 { "git", "clone",
    "--branch", try tag (builder, repo), "--depth", "1", url, path, }, });
}

