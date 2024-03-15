const std = @import ("std");

pub const toolbox = @import ("src/main.zig");

pub fn build (builder: *std.Build) !void
{
  _ = builder.addModule ("toolbox", .{ .root_source_file = .{ .path = "src/main.zig" }, });
}
