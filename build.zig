const std = @import ("std");

pub fn build (builder: *std.Build) void
{
  const target = builder.standardTargetOptions (.{});
  const optimize = builder.standardOptimizeOption (.{});

  _ = builder.addModule ("toolbox", .{ .root_source_file = .{ .path = "src/main.zig" } },);

  const lib = builder.addStaticLibrary (.{
    .name = "toolbox",
    .root_source_file = .{ .path = "src/main.zig" },
    .target = target,
    .optimize = optimize,
  });

  builder.installArtifact (lib);
}
