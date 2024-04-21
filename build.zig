const std = @import ("std");

const cache = @import ("build/cache.zig");
pub const addHeader = cache.addHeader;
pub const addInclude = cache.addInclude;
pub const addSource = cache.addSource;

const command = @import ("build/command.zig");
pub const write = command.write;
pub const make = command.make;
pub const copy = command.copy;
pub const run = command.run;

const deps = @import ("build/deps.zig");
pub const version = deps.version;
pub const isSubmodule = deps.isSubmodule;
pub const Repository = deps.Repository;
pub const Dependencies = deps.Dependencies;

const @"test" = @import ("build/test.zig");
pub const isCSource = @"test".isCSource;
pub const isCppSource = @"test".isCppSource;
pub const isSource = @"test".isSource;
pub const isCHeader = @"test".isCHeader;
pub const isCppHeader = @"test".isCppHeader;
pub const isHeader = @"test".isHeader;
pub const exists = @"test".exists;

pub fn clean (builder: *std.Build, paths: [] const [] const u8,
  extensions: [] const [] const u8) !void
{
  var flag: bool = undefined;
  var dir: std.fs.Dir = undefined;
  var walker: std.fs.Dir.Walker = undefined;

  for (paths) |path|
  {
    dir = try builder.build_root.handle.openDir (path, .{ .iterate = true, });
    defer dir.close ();

    flag = true;
    while (flag)
    {
      flag = false;

      walker = try dir.walk (builder.allocator);
      defer walker.deinit ();

      while (try walker.next ()) |*entry|
      {
        const entry_abspath = try std.fs.path.join (builder.allocator,
          &.{ builder.build_root.path.?, entry.path, });
        switch (entry.kind)
        {
          .file => {
            for (extensions) |ext|
              if (std.mem.endsWith (u8, entry.basename, ext)) continue;
            if (isSource (entry.basename) or
              isHeader (entry.basename)) continue;
            try std.fs.deleteFileAbsolute (entry_abspath);
            flag = true;
          },
          .directory => {
            std.fs.deleteDirAbsolute (entry_abspath) catch |err|
              if (err == error.DirNotEmpty) continue else return err;
            flag = true;
          },
          else => {},
        }
      }
    }
  }
}

pub fn build (builder: *std.Build) !void
{
  _ = builder.addModule ("toolbox",
    .{ .root_source_file = builder.addWriteFiles ().add ("empty.zig", ""), });
}
