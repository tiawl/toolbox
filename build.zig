const std = @import ("std");
const builtin = @import ("builtin");

pub fn isCSource (name: [] const u8) bool
{
  return std.mem.endsWith (u8, name, ".c");
}

pub fn isCppSource (name: [] const u8) bool
{
  return std.mem.endsWith (u8, name, ".cc") or
   std.mem.endsWith (u8, name, ".cpp");
}

pub fn isSource (name: [] const u8) bool
{
  return isCSource (name) or isCppSource (name);
}

pub fn isCHeader (name: [] const u8) bool
{
  return std.mem.endsWith (u8, name, ".h");
}

pub fn isCppHeader (name: [] const u8) bool
{
  return std.mem.endsWith (u8, name, ".hpp") or
    std.mem.endsWith (u8, name, ".hpp11");
}

pub fn isHeader (name: [] const u8) bool
{
  return isCHeader (name) or isCppHeader (name);
}

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

pub fn write (path: [] const u8, name: [] const u8,
  content: [] const u8) !void
{
  std.debug.print ("[write {s}/{s}]\n", .{ path, name, });
  var dir = try std.fs.openDirAbsolute (path, .{});
  defer dir.close ();
  try dir.writeFile (name, content);
}

pub fn make (path: [] const u8) !void
{
  std.debug.print ("[make {s}]\n", .{ path, });
  std.fs.makeDirAbsolute (path) catch |err|
    if (err != error.PathAlreadyExists) return err;
}

pub fn copy (src: [] const u8, dest: [] const u8) !void
{
  std.debug.print ("[copy {s} {s}]\n", .{ src, dest });
  try std.fs.copyFileAbsolute (src, dest, .{});
}

pub fn run (builder: *std.Build, proc: struct { argv: [] const [] const u8,
  cwd: ?[] const u8 = null, env: ?*const std.process.EnvMap = null,
  wait: ?*const fn () void = null, stdout: ?*[] const u8 = null,
  ignore_errors: bool = false, }) !void
{
  var stdout = std.ArrayList (u8).init (builder.allocator);
  var stderr = std.ArrayList (u8).init (builder.allocator);
  errdefer { stdout.deinit (); stderr.deinit (); }

  std.debug.print ("\x1b[35m[{s}]\x1b[0m\n",
    .{ try std.mem.join (builder.allocator, " ", proc.argv), });

  var child = std.ChildProcess.init (proc.argv, builder.allocator);

  child.stdin_behavior = .Ignore;
  child.stdout_behavior = .Pipe;
  child.stderr_behavior = .Pipe;
  child.cwd = proc.cwd;
  child.env_map = proc.env;

  try child.spawn ();

  var term: std.ChildProcess.Term = undefined;
  if (proc.wait) |wait|
  {
    wait ();
    term = try child.kill ();
  } else {
    try child.collectOutput (&stdout, &stderr, std.math.maxInt (usize));
    term = try child.wait ();
  }
  const exit_success = std.ChildProcess.Term { .Exited = 0, };
  if (stderr.items.len > 0 and !std.meta.eql (term, exit_success))
    std.debug.print ("\x1b[31m{s}\x1b[0m", .{ stderr.items, });
  if (!proc.ignore_errors and proc.wait == null)
    try std.testing.expectEqual (term, exit_success);

  if (proc.stdout) |out|
    out.* = std.mem.trim (u8, try stdout.toOwnedSlice (), " \n")
  else std.debug.print ("{s}", .{ stdout.items, });
}

pub fn tag (builder: *std.Build, id: [] const u8) ![] const u8
{
  const path = try builder.build_root.join (builder.allocator,
    &.{ ".versions", id, });
  return std.mem.trim (u8, try builder.build_root.handle.readFileAlloc (
    builder.allocator, path, std.math.maxInt (usize)), " \n");
}

pub fn clone (builder: *std.Build, url: [] const u8, tag_id: [] const u8,
  path: [] const u8) !void
{
  try run (builder, .{ .argv = &[_][] const u8 { "git", "clone",
    "--branch", try tag (builder, tag_id), "--depth", "1", url, path, }, });
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

        for (commits.value.array.items) |*commit|
        {
          for (tags.value.array.items) |*tag|
          {
            if (std.mem.eql (u8,
              commit.object.get ("sha").?.string,
              tag.object.get ("commit").?.object.get ("sha").?.string))
            {
              self.latest_tag = builder.dupe (
                tag.object.get ("name").?.string);
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

      const tags_url = try std.fmt.allocPrint (builder.allocator,
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
        try run (builder, .{ .argv = &[_][] const u8 { "curl", "-sS",
          "--request", "GET", "--url", tags_url, }, .stdout = &raw, });
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
      for (tags.value.array.items) |*tag|
      {
        try run (builder, .{ .argv = &[_][] const u8 { "date", "-d",
          tag.object.get ("commit").?.object.get ("created_at").?.string,
          "+%s", }, .stdout = &raw, });
        commit_ts = try std.fmt.parseInt (u64, raw, 10);
        if (commit_ts > latest_ts)
        {
          latest_ts = commit_ts;
          self.latest_tag = builder.dupe (tag.object.get ("name").?.string);
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

  pub fn init (builder: *std.Build, zon: anytype, clone: anytype,
    use_fetch: bool) !@This ()
  {
    var self = @This () {
      .zon = std.StringHashMap (Repository).init (builder.allocator),
      .clone = std.StringHashMap (Repository).init (builder.allocator),
    };

    inline for (.{ zon, clone, }, &.{ "zon", "clone", }) |proto, name|
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

pub fn build (builder: *std.Build) !void
{
  _ = builder.addModule ("toolbox",
    .{ .root_source_file = builder.addWriteFiles ().add ("empty.zig", ""), });
}
