const std = @import ("std");

const @"test" = @import ("test.zig");
pub const isSource = @"test".isSource;
pub const isHeader = @"test".isHeader;

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

  var child = std.process.Child.init (proc.argv, builder.allocator);

  child.stdin_behavior = .Ignore;
  child.stdout_behavior = .Pipe;
  child.stderr_behavior = .Pipe;
  child.cwd = proc.cwd;
  child.env_map = proc.env;

  try child.spawn ();

  var term: std.process.Child.Term = undefined;
  if (proc.wait) |wait|
  {
    wait ();
    term = try child.kill ();
  } else {
    try child.collectOutput (&stdout, &stderr, std.math.maxInt (usize));
    term = try child.wait ();
  }
  const exit_success = std.process.Child.Term { .Exited = 0, };
  if (!proc.ignore_errors and stderr.items.len > 0 and
    !std.meta.eql (term, exit_success))
      std.debug.print ("\x1b[31m{s}\x1b[0m", .{ stderr.items, });
  if (!proc.ignore_errors and proc.wait == null)
    try std.testing.expectEqual (term, exit_success);

  if (proc.stdout) |out|
    out.* = std.mem.trim (u8, try stdout.toOwnedSlice (), " \n")
  else std.debug.print ("{s}", .{ stdout.items, });
}

pub fn clean (builder: *std.Build, paths: [] const [] const u8,
  extensions: [] const [] const u8) !void
{
  var flag: bool = undefined;
  var dir: std.fs.Dir = undefined;
  var root_path: [] const u8 = undefined;
  var walker: std.fs.Dir.Walker = undefined;

  for (paths) |path|
  {
    dir = try builder.build_root.handle.openDir (path, .{ .iterate = true, });
    defer dir.close ();

    root_path = try builder.build_root.join (builder.allocator, &.{ path, });

    flag = true;
    while (flag)
    {
      flag = false;

      walker = try dir.walk (builder.allocator);
      defer walker.deinit ();

      walk: while (try walker.next ()) |*entry|
      {
        const entry_abspath = try std.fs.path.join (builder.allocator,
          &.{ root_path, entry.path, });
        switch (entry.kind)
        {
          .file => {
            for (extensions) |ext|
              if (std.mem.endsWith (u8, entry.basename, ext)) continue :walk;
            if (isSource (entry.basename) or
              isHeader (entry.basename)) continue :walk;
            try std.fs.deleteFileAbsolute (entry_abspath);
            std.debug.print ("[clean] {s}\n", .{ entry_abspath, });
            flag = true;
          },
          .directory => {
            std.fs.deleteDirAbsolute (entry_abspath) catch |err|
              if (err == error.DirNotEmpty) continue :walk else return err;
            std.debug.print ("[clean] {s}\n", .{ entry_abspath, });
            flag = true;
          },
          else => {},
        }
      }
    }
  }
}
