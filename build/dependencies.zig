const std = @import ("std");
const builtin = @import ("builtin");

const command = @import ("command.zig");
const run = command.run;

const @"test" = @import ("test.zig");
const exists = @"test".exists;

pub fn reference (builder: *std.Build, repo: [] const u8) ![] const u8
{
  const path = try builder.build_root.join (builder.allocator,
    &.{ ".references", repo, });
  return std.mem.trim (u8, try builder.build_root.handle.readFileAlloc (
    builder.allocator, path, std.math.maxInt (usize)), " \n");
}

pub const Repository = struct
{
  pub const Host = enum { github, gitlab, };
  pub const Reference = enum { tag, commit, };

  // prefixed attributes
  __name: [] const u8,
  __url: [] const u8,
  __latest: [] const u8 = undefined,
  __ref: Reference = undefined,

  // mandatory getters function
  fn getName (self: @This ()) [] const u8 { return self.__name; }
  fn getUrl (self: @This ()) [] const u8 { return self.__url; }
  fn getLatest (self: @This ()) [] const u8 { return self.__latest; }
  fn getRef (self: @This ()) Reference { return self.__ref; }

  // mandatory init function
  fn init (builder: *std.Build, name: [] const u8, url: [] const u8,
    latest: ?[] const u8, ref: Reference) @This ()
  {
    var self = @This () {
      .__name = builder.dupe (name),
      .__url = builder.dupe (url),
      .__ref = ref,
    };
    if (latest) |tag| self.__latest = builder.dupe (tag);
    return self;
  }

  // immutable setters
  fn setLatest (self: @This (), builder: *std.Build,
    latest: [] const u8) @This ()
  {
    return init (builder, self.getName (), self.getUrl (), latest,
      self.getRef ());
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

    return switch (self.getRef ())
    {
      .commit => self.searchLatestCommit (builder, tmp),
      .tag => self.searchLatestTag (builder, tmp),
    };
  }

  fn searchLatestCommit (self: @This (), builder: *std.Build,
    tmp: [] const u8) !@This ()
  {
    var commit: [] const u8 = undefined;

    try run (builder, .{ .argv = &[_][] const u8 { "git", "log",
      "-n1", "--pretty='format:%h'", }, .cwd = tmp, .stdout = &commit, });

    return self.setLatest (builder, commit);
  }

  fn searchLatestTag (self: @This (), builder: *std.Build,
    tmp: [] const u8) !@This ()
  {
    var commit: [] const u8 = undefined;
    var tag: [] u8 = undefined;
    for (0 .. std.math.maxInt (usize)) |i|
    {
      commit = try std.fmt.allocPrint (builder.allocator, "HEAD~{}", .{ i, });
      try run (builder, .{ .argv = &[_][] const u8 { "git", "describe",
        "--tags", "--exact-match", commit, }, .cwd = tmp, .stdout = &tag,
        .ignore_errors = true, });
      if (valid (tag)) return self.setLatest (builder, tag);
    } else return error.NoValidTag;
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
    fn url (builder: *std.Build, domain: [] const u8,
      name: [] const u8) ![] const u8
    {
      return try std.fmt.allocPrint (builder.allocator,
        "https://gitlab.{s}/{s}", .{ domain, name, });
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

  // mandatory init function
  pub fn init (builder: *std.Build, pkg_name: [] const u8,
    paths: [] const [] const u8, intern_proto: anytype,
    extern_proto: anytype) !@This ()
  {
    var self = @This () {
      .__intern = std.StringHashMap (Repository).init (builder.allocator),
      .__extern = std.StringHashMap (Repository).init (builder.allocator),
    };

    const fetch = builder.option (bool, "fetch",
      "Update .references folder and build.zig.zon then stop execution")
        orelse false;

    var repository: Repository = undefined;
    inline for (.{ intern_proto, extern_proto, },
      &.{ "__intern", "__extern", }) |proto, attr|
    {
      inline for (@typeInfo (@TypeOf (proto)).Struct.fields) |field|
      {
        const name = @field (proto, field.name).name;
        const host = @field (proto, field.name).host;
        const ref = @field (proto, field.name).ref;
        repository = Repository.init (builder, name, switch (host)
        {
          .github => try Repository.Github.url (builder, name),
          .gitlab => try Repository.Gitlab.url (
            builder, @field (proto, field.name).domain, name),
        }, null, ref);
        if (fetch) repository = try repository.searchLatest (builder);
        try @field (self, attr).put (field.name, repository);
      }
    }

    if (fetch)
    {
      try self.fetchExtern (builder);
      try self.fetchIntern (builder, pkg_name, paths);
      std.process.exit (0);
    }

    return self;
  }

  pub fn clone (self: @This (), builder: *std.Build,
    repo: [] const u8, path: [] const u8) !void
  {
    switch (self.getExtern (repo).getRef ())
    {
      .tag => try run (builder, .{ .argv = &[_][] const u8 { "git", "clone",
        "--branch", try reference (builder, repo), "--depth", "1",
        self.getExtern (repo).getUrl (), path, }, }),
      .commit => try run (builder, .{ .argv = &[_][] const u8 { "git",
        "clone", "--depth", "1", self.getExtern (repo).getUrl (), path, }, }),
    }
  }

  fn fetchExtern (self: @This (), builder: *std.Build) !void
  {
    var references_dir =
      try builder.build_root.handle.openDir (".references", .{});
    defer references_dir.close ();

    var it = self.getExterns ();
    while (it.next ()) |key|
    {
      try references_dir.deleteFile (key.*);
      try references_dir.writeFile (key.*,
        try std.fmt.allocPrint (builder.allocator, "{s}\n",
          .{ self.getExtern (key.*).getLatest (), }));
    }
  }

  fn fetchIntern (self: @This (), builder: *std.Build,
    name: [] const u8, additional_paths: [] const [] const u8) !void
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

    try writer.print ("\"build.zig\",\n\"build.zig.zon\",\n", .{});

    for (additional_paths) |path|
      try writer.print ("\"{s}\",\n", .{ path, });

    try writer.print ("{c},\n.dependencies = .{c}\n", .{ '}', '{', });

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

    try writer.print ("{c},\n{c}\n", .{ '}', '}', });

    try buffer.append (0);
    const source = buffer.items [0 .. buffer.items.len - 1 :0];

    const validated = try std.zig.Ast.parse (builder.allocator, source, .zon);
    const formatted = try validated.render (builder.allocator);

    try builder.build_root.handle.deleteFile ("build.zig.zon");
    try builder.build_root.handle.writeFile ("build.zig.zon", formatted);
  }
};
