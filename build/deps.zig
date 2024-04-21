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
  id: u32 = 0,
  url: [] const u8 = undefined,
  latest: [] const u8 = undefined,

  fn searchLatest (self: @This (), builder: *std.Build) !@This ()
  {
    return if (self.id == 0) Repository.Github.searchLatest (self, builder)
      else Repository.Gitlab.searchLatest (self, builder);
  }

  pub const Github = struct
  {
    fn init (builder: *std.Build, name: [] const u8) !Repository
    {
      return .{
        .name = name,
        .url = try std.fmt.allocPrint (builder.allocator,
          "https://github.com/{s}", .{ name, }),
      };
    }

    fn searchLatest (self: Repository, builder: *std.Build) !Repository
    {
      var endpoint = try std.fmt.allocPrint (builder.allocator,
        "/repos/{s}/tags", .{ self.name, });

      var raw: [] u8 = "";
      var raw_page: [] u8 = "";
      var page: u32 = 1;
      var page_field: [] const u8 = undefined;
      while (raw.len == 0 or raw_page.len > 0)
      {
        page_field =
          try std.fmt.allocPrint (builder.allocator, "page={}", .{ page, });
        try run (builder, .{ .argv = &[_][] const u8 { "gh", "api",
          "-H", "'X-GitHub-Api-Version: 2022-11-28'",
          "-H", "'Accept: application/vnd.github+json'",
          "--method", "GET", "-F", "per_page=100", "-F", page_field, endpoint,
          }, .stdout = &raw_page, });
        raw_page = @constCast (std.mem.trim (u8, raw_page, "[]"));
        raw = try std.fmt.allocPrint (builder.allocator, "{s}{s}{s}",
          .{ raw, if (raw_page.len > 0 and raw.len > 0) "," else "",
             raw_page, });
        page += 1;
      }
      raw = try std.fmt.allocPrint (builder.allocator, "[{s}]",
        .{ raw, });

      const tags = try std.json.parseFromSlice (std.json.Value,
        builder.allocator, raw, .{});
      defer tags.deinit ();

      endpoint = try std.fmt.allocPrint (builder.allocator,
        "/repos/{s}/commits", .{ self.name, });

      var result: Repository = .{
        .name = builder.dupe (self.name),
        .url = builder.dupe (self.url),
      };

      page = 1;
      loop: while (true)
      {
        page_field =
          try std.fmt.allocPrint (builder.allocator, "page={}", .{ page, });
        try run (builder, .{ .argv = &[_][] const u8 { "gh", "api",
          "-H", "'X-GitHub-Api-Version: 2022-11-28'",
          "-H", "'Accept: application/vnd.github+json'",
          "--method", "GET", "-F", "per_page=100", "-F", page_field, endpoint,
          }, .stdout = &raw, });

        const commits = try std.json.parseFromSlice (std.json.Value,
          builder.allocator, raw, .{});
        defer commits.deinit ();

        for (commits.value.array.items) |*commit|
        {
          for (tags.value.array.items) |*tag|
          {
            if (std.mem.eql (u8,
              commit.object.get ("sha").?.string,
              tag.object.get ("commit").?.object.get ("sha").?.string))
            {
              result.latest = builder.dupe (
                tag.object.get ("name").?.string);
              break :loop;
            }
          }
        }
      }

      return result;
    }
  };

  pub const Gitlab = struct
  {
    fn init (builder: *std.Build, name: [] const u8, id: u32) !Repository
    {
      return .{
        .name = name,
        .id = id,
        .url = try std.fmt.allocPrint (builder.allocator,
          "https://gitlab.freedesktop.org/{s}", .{ name, }),
      };
    }

    fn searchLatest (self: Repository, builder: *std.Build) !Repository
    {
      const pageless_endpoint = try std.fmt.allocPrint (builder.allocator,
        "https://gitlab.freedesktop.org/api/v4/projects/{}/repository/tags?per_page=100&page=",
        .{ self.id, });

      var raw: [] u8 = "";
      var raw_page: [] u8 = "";
      var page: u32 = 1;
      var endpoint: [] const u8 = undefined;
      while (raw.len == 0 or raw_page.len > 0)
      {
        endpoint = try std.fmt.allocPrint (builder.allocator, "{s}{}",
          .{ pageless_endpoint, page, });
        try run (builder, .{ .argv = &[_][] const u8 { "curl", "-sS",
          "--request", "GET", "--url", endpoint, }, .stdout = &raw_page, });
        raw_page = @constCast (std.mem.trim (u8, raw_page, "[]"));
        raw = try std.fmt.allocPrint (builder.allocator, "{s}{s}{s}",
          .{ raw, if (raw_page.len > 0 and raw.len > 0) "," else "",
             raw_page, });
        page += 1;
      }
      raw = try std.fmt.allocPrint (builder.allocator, "[{s}]",
        .{ raw, });

      const tags = try std.json.parseFromSlice (std.json.Value,
        builder.allocator, raw, .{});
      defer tags.deinit ();

      var result: Repository = .{
        .name = builder.dupe (self.name),
        .id = self.id,
        .url = builder.dupe (self.url),
      };

      var latest_ts: u64 = 0;
      var commit_ts: u64 = 0;
      for (tags.value.array.items) |*tag|
      {
        try run (builder, .{ .argv = &[_][] const u8 { "date", "-d",
          tag.object.get ("commit").?.object.get ("created_at").?.string,
          "+%s", }, .stdout = &raw_page, });
        commit_ts = try std.fmt.parseInt (u64, raw_page, 10);
        if (commit_ts > latest_ts)
        {
          latest_ts = commit_ts;
          result.latest =
            builder.dupe (tag.object.get ("name").?.string);
        }
      }

      return result;
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
        try @field (self, name).put (field.name,
          switch (@field (proto, field.name).api)
          {
            .github => try Repository.Github.init (builder,
              @field (proto, field.name).name),
            .gitlab => try Repository.Gitlab.init (builder,
              @field (proto, field.name).name, @field (proto, field.name).id),
          });
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
