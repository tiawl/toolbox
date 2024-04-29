const std = @import ("std");
const builtin = @import ("builtin");

const command = @import ("command.zig");
pub const run = command.run;

const @"test" = @import ("test.zig");
pub const exists = @"test".exists;

pub fn version (builder: *std.Build, repo: [] const u8) ![] const u8
{
  const path = try builder.build_root.join (builder.allocator,
    &.{ ".versions", repo, });
  return std.mem.trim (u8, try builder.build_root.handle.readFileAlloc (
    builder.allocator, path, std.math.maxInt (usize)), " \n");
}

pub fn isSubmodule (builder: *std.Build, name: [] const u8) !bool
{
  var submodules: [] u8 = undefined;
  try run (builder, .{ .argv = &[_][] const u8 { "git", "config", "--file",
    ".gitmodules", "--get-regexp", "path", }, .stdout = &submodules,
      .ignore_errors = true, .cwd = builder.build_root.path.?, });
  var it = std.mem.tokenizeAny (u8, submodules, " \n");
  var flag = false;
  while (it.next ()) |token|
  {
    if (flag and std.mem.eql (u8, name, token)) return true;
    flag = !flag;
  }
  return false;
}

fn fetchSubmodules (builder: *std.Build) !void
{
  if (!exists (try builder.build_root.join (builder.allocator,
    &.{ ".gitmodules", }))) return;

  try run (builder, .{ .argv = &[_][] const u8 { "git", "submodule",
    "update", "--remote", "--merge", },
      .cwd = builder.build_root.path.?, });
}

pub const Repository = struct
{
  pub const API = enum { github, gitlab, };

  name: [] const u8,
  url: [] const u8 = undefined,
  latest: [] const u8 = undefined,

  fn init (builder: *std.Build, name: [] const u8, api: API) !@This ()
  {
    return switch (api)
    {
      .github => try Github.init (builder, name),
      .gitlab => try Gitlab.init (builder, name),
    };
  }

  fn valid (tag: [] const u8) bool
  {
    return (std.mem.indexOfAny (u8, tag, "0123456789") != null) and
      (std.mem.indexOfScalar (u8, tag, '.') != null);
  }

  fn searchLatest (self: @This (), builder: *std.Build) !@This ()
  {
    var tmp_dir = std.testing.tmpDir (.{});
    const tmp = try tmp_dir.dir.realpathAlloc (builder.allocator, ".");

    try run (builder, .{ .argv = &[_][] const u8 { "git", "clone", "--bare",
      "--filter=blob:none", self.url, tmp, }, });

    var tags: [] u8 = undefined;
    try run (builder, .{ .argv = &[_][] const u8 { "git", "tag",
      "--sort=-committerdate", }, .cwd = tmp, .stdout = &tags, });

    var it = std.mem.tokenizeAny (u8, tags, " \n");
    while (it.next ()) |token|
    {
      if (valid (token))
      {
        return .{
          .name = builder.dupe (self.name),
          .url = builder.dupe (self.url),
          .latest = builder.dupe (token),
        };
      }
    } else return error.NoValidTag;
  }

  const Github = struct
  {
    fn init (builder: *std.Build, name: [] const u8) !Repository
    {
      return .{
        .name = name,
        .url = try std.fmt.allocPrint (builder.allocator,
          "https://github.com/{s}", .{ name, }),
      };
    }
  };

  const Gitlab = struct
  {
    fn init (builder: *std.Build, name: [] const u8) !Repository
    {
      return .{
        .name = name,
        .url = try std.fmt.allocPrint (builder.allocator,
          "https://gitlab.freedesktop.org/{s}", .{ name, }),
      };
    }
  };
};

pub const Dependencies = struct
{
  intern: std.StringHashMap (Repository),
  @"extern": std.StringHashMap (Repository),

  pub fn init (builder: *std.Build, intern_proto: anytype,
    extern_proto: anytype) !@This ()
  {
    var self = @This () {
      .intern = std.StringHashMap (Repository).init (builder.allocator),
      .@"extern" = std.StringHashMap (Repository).init (builder.allocator),
    };

    inline for (.{ intern_proto, extern_proto, },
      &.{ "intern", "extern", }) |proto, name|
    {
      inline for (@typeInfo (@TypeOf (proto)).Struct.fields) |field|
      {
        try @field (self, name).put (field.name, try Repository.init (builder,
          @field (proto, field.name).name, @field (proto, field.name).api));
      }
    }

    return self;
  }

  pub fn clone (self: @This (), builder: *std.Build,
    repo: [] const u8, path: [] const u8) !void
  {
    try run (builder, .{ .argv = &[_][] const u8 { "git", "clone",
      "--branch", try version (builder, repo), "--depth", "1",
      self.@"extern".get (repo).?.url, path, }, });
  }

  pub fn fetch (self: *@This (), builder: *std.Build, name: [] const u8) !void
  {
    try self.searchLatest (builder);
    try self.fetchExtern (builder);
    try self.fetchIntern (builder, name);
    try fetchSubmodules (builder);

    std.process.exit (0);
  }

  fn searchLatest (self: *@This (), builder: *std.Build) !void
  {
    for (&[_] *std.StringHashMap (Repository) {
      &self.@"extern", &self.intern,
    }) |*dep| {
      var it = dep.*.keyIterator ();
      while (it.next ()) |key|
        try dep.*.put (key.*, try dep.*.get (key.*).?.searchLatest (builder));
    }
  }

  fn fetchExtern (self: *@This (), builder: *std.Build) !void
  {
    var versions_dir =
      try builder.build_root.handle.openDir (".versions", .{});
    defer versions_dir.close ();

    var it = self.@"extern".keyIterator ();
    while (it.next ()) |key|
    {
      try versions_dir.deleteFile (key.*);
      try versions_dir.writeFile (key.*,
        try std.fmt.allocPrint (builder.allocator, "{s}\n",
          .{ self.@"extern".get (key.*).?.latest, }));
    }
  }

  fn fetchIntern (self: *@This (), builder: *std.Build,
    name: [] const u8) !void
  {
    var buffer = std.ArrayList (u8).init (builder.allocator);
    const writer = buffer.writer ();

    try writer.print (
      \\.{c}
      \\  .name = "{s}",
      \\  .version = "1.0.0",
      \\  .minimum_zig_version = "{}.{}.0",
      \\  .paths = .{c}
      \\
      , .{ '{', name, builtin.zig_version.major,
           builtin.zig_version.minor, '{', });

    var build_dir = try builder.build_root.handle.openDir (".",
      .{ .iterate = true, });
    defer build_dir.close ();

    {
      var it = build_dir.iterate ();
      while (try it.next ()) |*entry|
      {
        if (!std.mem.startsWith (u8, entry.name, ".") and
          !std.mem.eql (u8, entry.name, "zig-cache") and
          !std.mem.eql (u8, entry.name, "zig-out") and
          !try isSubmodule (builder, entry.name))
            try writer.print ("\"{s}\",\n", .{ entry.name, });
      }
    }

    try writer.print ("{c},\n.dependencies = .{c}\n", .{ '}', '{', });

    {
      var it = self.intern.keyIterator ();
      while (it.next ()) |key|
      {
        const url = try std.fmt.allocPrint (builder.allocator,
          "{s}/archive/refs/tags/{s}.tar.gz",
          .{ self.intern.get (key.*).?.url,
             self.intern.get (key.*).?.latest, });
        var hash: [] u8 = undefined;
        try run (builder, .{ .argv = &[_][] const u8 { "zig", "fetch", url, },
          .stdout = &hash, });
        try writer.print (
          \\.{s} = .{c}
          \\  .url = "{s}",
          \\  .hash = "{s}",
          \\{c},
          \\
        , .{ key.*, '{', url, hash, '}', });
      }
    }

    try writer.print ("{c},\n{c}\n", .{ '}', '}', });

    try buffer.append (0);
    const source = buffer.items [0 .. buffer.items.len - 1 :0];

    const validated = try std.zig.Ast.parse (builder.allocator, source, .zon);
    const formatted = try validated.render (builder.allocator);

    try builder.build_root.handle.deleteFile ("build.zig.zon");
    try builder.build_root.handle.writeFile ("build.zig.zon", formatted);
  }
};
