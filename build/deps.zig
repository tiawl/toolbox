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

  // prefixed attributes
  __name: [] const u8,
  __url: [] const u8,
  __latest: [] const u8 = undefined,

  // mandatory getters function
  fn getName (self: @This ()) [] const u8 { return self.__name; }
  fn getUrl (self: @This ()) [] const u8 { return self.__url; }
  fn getLatest (self: @This ()) [] const u8 { return self.__latest; }

  // mandatory new function
  fn new (builder: *std.Build, name: [] const u8, url: [] const u8, latest: ?[] const u8) @This ()
  {
    var self = @This () {
      .__name = builder.dupe (name),
      .__url = builder.dupe (url),
    };
    if (latest) |tag| self.__latest = builder.dupe (tag);
    return self;
  }

  fn init (builder: *std.Build, name: [] const u8, api: API) !@This ()
  {
    return new (builder, name, switch (api)
    {
      .github => try Github.url (builder, name),
      .gitlab => try Gitlab.url (builder, name),
    }, null);
  }

  // immutable setters
  fn setLatest (self: @This (), builder: *std.Build,
    latest: [] const u8) @This ()
  {
    return new (builder, self.getName (), self.getUrl (), latest);
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
      "--filter=blob:none", self.getUrl (), tmp, }, });

    var commits: [] u8 = undefined;
    try run (builder, .{ .argv = &[_][] const u8 { "git", "log", "--all",
      "--format=%h", }, .cwd = tmp, .stdout = &commits, });

    var tag: [] u8 = undefined;
    var it = std.mem.tokenizeAny (u8, commits, " \n");
    while (it.next ()) |commit|
    {
      try run (builder, .{ .argv = &[_][] const u8 { "git", "describe",
        "--exact-match", commit, }, .cwd = tmp, .stdout = &tag,
        .ignore_errors = true, });
      if (valid (tag)) return self.setLatest (builder, tag);
    } else error.NoValidTag;
  }

  const Github = struct
  {
    fn url (builder: *std.Build, name: [] const u8) ![] const u8
    {
      return try std.fmt.allocPrint (builder.allocator,
        "https://github.com/{s}", .{ name, });
    }
  };

  const Gitlab = struct
  {
    fn url (builder: *std.Build, name: [] const u8) ![] const u8
    {
      return try std.fmt.allocPrint (builder.allocator,
        "https://gitlab.freedesktop.org/{s}", .{ name, });
    }
  };
};

pub const Dependencies = struct
{
  // prefixed attributes
  __intern: std.StringHashMap (Repository),
  __extern: std.StringHashMap (Repository),

  // mandatory getters function
  pub fn getIntern (self: @This (), key: [] const u8) Repository { return self.__intern.get (key).?; }
  pub fn getExtern (self: @This (), key: [] const u8) Repository { return self.__extern.get (key).?; }
  pub fn getInterns (self: @This ()) std.StringHashMap (Repository).KeyIterator { return self.__intern.keyIterator (); }
  pub fn getExterns (self: @This ()) std.StringHashMap (Repository).KeyIterator { return self.__extern.keyIterator (); }

  pub fn init (builder: *std.Build, name: [] const u8, intern_proto: anytype,
    extern_proto: anytype) !@This ()
  {
    var self = @This () {
      .__intern = std.StringHashMap (Repository).init (builder.allocator),
      .__extern = std.StringHashMap (Repository).init (builder.allocator),
    };

    const fetch = builder.option (bool, "fetch",
      "Update .versions folder and build.zig.zon then stop execution")
        orelse false;

    var repository: Repository = undefined;
    inline for (.{ intern_proto, extern_proto, },
      &.{ "__intern", "__extern", }) |proto, attr|
    {
      inline for (@typeInfo (@TypeOf (proto)).Struct.fields) |field|
      {
        repository = try Repository.init (builder,
          @field (proto, field.name).name, @field (proto, field.name).api);
        if (fetch) repository = try repository.searchLatest (builder);
        try @field (self, attr).put (field.name, repository);
      }
    }

    if (fetch)
    {
      try self.fetchExtern (builder);
      try self.fetchIntern (builder, name);
      try fetchSubmodules (builder);
      std.process.exit (0);
    }

    return self;
  }

  pub fn clone (self: @This (), builder: *std.Build,
    repo: [] const u8, path: [] const u8) !void
  {
    try run (builder, .{ .argv = &[_][] const u8 { "git", "clone",
      "--branch", try version (builder, repo), "--depth", "1",
      self.getExtern (repo).getUrl (), path, }, });
  }

  fn fetchExtern (self: @This (), builder: *std.Build) !void
  {
    var versions_dir =
      try builder.build_root.handle.openDir (".versions", .{});
    defer versions_dir.close ();

    var it = self.getExterns ();
    while (it.next ()) |key|
    {
      try versions_dir.deleteFile (key.*);
      try versions_dir.writeFile (key.*,
        try std.fmt.allocPrint (builder.allocator, "{s}\n",
          .{ self.getExtern (key.*).getLatest (), }));
    }
  }

  fn fetchIntern (self: @This (), builder: *std.Build,
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
      var it = self.getInterns ();
      while (it.next ()) |key|
      {
        const url = try std.fmt.allocPrint (builder.allocator,
          "{s}/archive/refs/tags/{s}.tar.gz",
          .{ self.getIntern (key.*).getUrl (),
             self.getIntern (key.*).getLatest (), });
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
