const std = @import ("std");

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

pub fn exec (builder: *std.Build, proc: struct { argv: [] const [] const u8, cwd: ?[] const u8 = null, env: ?*const std.process.EnvMap = null, }) !void
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
  try child.collectOutput (&stdout, &stderr, std.math.maxInt (usize));

  const term = try child.wait ();

  if (stdout.items.len > 0) std.debug.print ("{s}", .{ stdout.items, });
  if (stderr.items.len > 0 and !std.meta.eql (term, std.ChildProcess.Term { .Exited = 0, })) std.debug.print ("\x1b[31m{s}\x1b[0m", .{ stderr.items, });
  try std.testing.expectEqual (term, std.ChildProcess.Term { .Exited = 0, });
}
