const std = @import ("std");

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
    .file = .{ .path = try std.fs.path.relative (builder.allocator,
      builder.build_root.path.?, source_path), },
    .flags = flags,
  });
}
