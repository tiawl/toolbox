const std = @import ("std");

const compilation = @import ("build/compilation.zig");
pub const addHeader = compilation.addHeader;
pub const addInclude = compilation.addInclude;
pub const addSource = compilation.addSource;

const command = @import ("build/command.zig");
pub const write = command.write;
pub const make = command.make;
pub const copy = command.copy;
pub const run = command.run;
pub const clean = command.clean;

const dependencies = @import ("build/dependencies.zig");
pub const version = dependencies.version;
pub const isSubmodule = dependencies.isSubmodule;
pub const Repository = dependencies.Repository;
pub const Dependencies = dependencies.Dependencies;

const @"test" = @import ("build/test.zig");
pub const isCSource = @"test".isCSource;
pub const isCppSource = @"test".isCppSource;
pub const isSource = @"test".isSource;
pub const isCHeader = @"test".isCHeader;
pub const isCppHeader = @"test".isCppHeader;
pub const isHeader = @"test".isHeader;
pub const exists = @"test".exists;

pub fn build (builder: *std.Build) !void
{
  _ = builder.addModule ("toolbox",
    .{ .root_source_file = builder.addWriteFiles ().add ("empty.zig", ""), });

  const clean_step = builder.step ("clean", "Clean up");

  clean_step.dependOn (&builder.addRemoveDirTree (builder.install_path).step);
  if (@import ("builtin").os.tag != .windows)
  {
    clean_step.dependOn (&builder.addRemoveDirTree (
      builder.pathFromRoot ("zig-cache")).step);
  }
}
