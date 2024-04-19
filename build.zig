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
pub const tag = command.tag;
pub const clone = command.clone;

const deps = @import ("build/deps.zig");
pub const isSubmodule = deps.isSubmodule;
pub const Repository = deps.Repository;
pub const Dependencies = deps.Dependencies;
pub const fetch = deps.fetch;

const @"test" = @import ("build/test.zig");
pub const isCSource = @"test".isCSource;
pub const isCppSource = @"test".isCppSource;
pub const isSource = @"test".isSource;
pub const isCHeader = @"test".isCHeader;
pub const isCppHeader = @"test".isCppHeader;
pub const isHeader = @"test".isHeader;

pub fn build (builder: *std.Build) !void
{
  _ = builder.addModule ("toolbox",
    .{ .root_source_file = builder.addWriteFiles ().add ("empty.zig", ""), });
}
