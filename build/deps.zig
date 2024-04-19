const std = @import ("std");
const builtin = @import ("builtin");

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

pub const Repository = struct
{
  pub const API = enum { github, gitlab, };

  name: [] const u8,
  id: u32 = 0,
  url: [] const u8 = undefined,
  latest_tag: [] const u8 = undefined,

  pub const Github = struct
  {
    fn init (builder: *std.Build, name: [] const u8,
      use_fetch: bool) !Repository
    {
      var self = Repository {
        .name = name,
        .url = try std.fmt.allocPrint (builder.allocator,
          "https://github.com/{s}", .{ name, }),
      };

      if (!use_fetch) return self;

      var endpoint = try std.fmt.allocPrint (builder.allocator,
        "/repos/{s}/tags", .{ name, });

      var raw_tags: [] u8 = "";
      var raw: [] u8 = "";
      var page: u32 = 1;
      var page_field: [] const u8 = undefined;
      while (raw_tags.len == 0 or raw.len > 0)
      {
        page_field =
          try std.fmt.allocPrint (builder.allocator, "page={}", .{ page, });
        try run (builder, .{ .argv = &[_][] const u8 { "gh", "api",
          "-H", "'X-GitHub-Api-Version: 2022-11-28'",
          "-H", "'Accept: application/vnd.github+json'",
          "--method", "GET", "-F", "per_page=100", "-F", page_field, endpoint,
          }, .stdout = &raw, });
        raw = @constCast (std.mem.trim (u8, raw, "[]"));
        raw_tags = try std.fmt.allocPrint (builder.allocator, "{s}{s}{s}",
          .{ raw_tags, if (raw.len > 0 and raw_tags.len > 0) "," else "",
             raw, });
        page += 1;
      }
      raw_tags = try std.fmt.allocPrint (builder.allocator, "[{s}]",
        .{ raw_tags, });

      const tags = try std.json.parseFromSlice (std.json.Value,
        builder.allocator, raw_tags, .{});
      defer tags.deinit ();

      endpoint = try std.fmt.allocPrint (builder.allocator,
        "/repos/{s}/commits", .{ name, });

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

        for (commits.value.array.items) |*commit_value|
        {
          for (tags.value.array.items) |*tag_value|
          {
            if (std.mem.eql (u8,
              commit_value.object.get ("sha").?.string,
              tag_value.object.get ("commit").?.object.get ("sha").?.string))
            {
              self.latest_tag = builder.dupe (
                tag_value.object.get ("name").?.string);
              break :loop;
            }
          }
        }
      }

      return self;
    }
  };

  pub const Gitlab = struct
  {
    fn init (builder: *std.Build, name: [] const u8, id: u32,
      use_fetch: bool) !Repository
    {
      var self = Repository {
        .name = name,
        .id = id,
        .url = try std.fmt.allocPrint (builder.allocator,
          "https://gitlab.freedesktop.org/{s}", .{ name, }),
      };

      if (!use_fetch) return self;

      const endpoint = try std.fmt.allocPrint (builder.allocator,
        "https://gitlab.freedesktop.org/api/v4/projects/{}/repository/tags",
        .{ self.id, });

      var raw_tags: [] u8 = "";
      var raw: [] u8 = "";
      var page: u32 = 1;
      var page_field: [] const u8 = undefined;
      while (raw_tags.len == 0 or raw.len > 0)
      {
        page_field =
          try std.fmt.allocPrint (builder.allocator, "page={}", .{ page, });
        try run (builder, .{ .argv = &[_][] const u8 { "glab", "api",
          "--method", "GET", "-F", "per_page=100", "-F", page_field, endpoint,
          }, .stdout = &raw, });
        raw = @constCast (std.mem.trim (u8, raw, "[]"));
        raw_tags = try std.fmt.allocPrint (builder.allocator, "{s}{s}{s}",
          .{ raw_tags, if (raw.len > 0 and raw_tags.len > 0) "," else "",
             raw, });
        page += 1;
      }
      raw_tags = try std.fmt.allocPrint (builder.allocator, "[{s}]",
        .{ raw_tags, });

      const tags = try std.json.parseFromSlice (std.json.Value,
        builder.allocator, raw_tags, .{});
      defer tags.deinit ();

      var latest_ts: u64 = 0;
      var commit_ts: u64 = 0;
      for (tags.value.array.items) |*tag_value|
      {
        try run (builder, .{ .argv = &[_][] const u8 { "date", "-d",
          tag_value.object.get ("commit").?.object.get ("created_at").?.string,
          "+%s", }, .stdout = &raw, });
        commit_ts = try std.fmt.parseInt (u64, raw, 10);
        if (commit_ts > latest_ts)
        {
          latest_ts = commit_ts;
          self.latest_tag =
            builder.dupe (tag_value.object.get ("name").?.string);
        }
      }

      return self;
    }
  };
};

pub const Dependencies = struct
{
  zon: std.StringHashMap (Repository),
  clone: std.StringHashMap (Repository),

  pub fn init (builder: *std.Build, zon_proto: anytype, clone_proto: anytype,
    use_fetch: bool) !@This ()
  {
    var self = @This () {
      .zon = std.StringHashMap (Repository).init (builder.allocator),
      .clone = std.StringHashMap (Repository).init (builder.allocator),
    };

    inline for (.{ zon_proto, clone_proto, },
      &.{ "zon", "clone", }) |proto, name|
    {
      inline for (@typeInfo (@TypeOf (proto)).Struct.fields) |field|
      {
        try @field (self, name).put (field.name,
          switch (@field (proto, field.name).api)
          {
            .github => try Repository.Github.init (builder,
              @field (proto, field.name).name, use_fetch),
            .gitlab => try Repository.Gitlab.init (builder,
              @field (proto, field.name).name, @field (proto, field.name).id,
              use_fetch),
          });
      }
    }

    return self;
  }
};

pub fn fetch (builder: *std.Build, name: [] const u8,
  dependencies: *const Dependencies) !void
{
  var versions_dir =
    try builder.build_root.handle.openDir (".versions", .{});
  defer versions_dir.close ();

  {
    var it = dependencies.clone.keyIterator ();
    while (it.next ()) |key|
    {
      try versions_dir.deleteFile (key.*);
      try versions_dir.writeFile (key.*,
        try std.fmt.allocPrint (builder.allocator, "{s}\n",
          .{ dependencies.clone.get (key.*).?.latest_tag, }));
    }
  }

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
    var it = dependencies.zon.keyIterator ();
    while (it.next ()) |key|
    {
      const url = try std.fmt.allocPrint (builder.allocator,
        "{s}/archive/refs/tags/{s}.tar.gz",
        .{ dependencies.zon.get (key.*).?.url,
           dependencies.zon.get (key.*).?.latest_tag, });
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

  std.process.exit (0);
}

