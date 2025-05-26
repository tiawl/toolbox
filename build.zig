const std = @import("std");
const builtin = @import("builtin");

const EnumLiteral = @Type(.enum_literal);

const FetchTarget = struct {
    name: []const u8,
    domain: []const u8 = "",
    host: Repository.Host,
    ref: Repository.Reference,
    branch: []const u8 = "",
};

pub fn Repositories(comptime tuple: anytype) type {
    std.debug.assert(@typeInfo(@TypeOf(tuple)).@"struct".is_tuple);
    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = blk: {
                var fields: [tuple.len]std.builtin.Type.StructField = undefined;
                for (tuple, 0..) |literal, i| {
                    fields[i] = .{
                        .name = @tagName(literal),
                        .type = FetchTarget,
                        .default_value_ptr = null,
                        .is_comptime = false,
                        .alignment = if (@sizeOf(FetchTarget) > 0) @alignOf(FetchTarget) else 0,
                    };
                }
                break :blk &fields;
            },
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

pub fn isCSource(name: []const u8) bool {
    return std.mem.endsWith(u8, name, ".c");
}

pub fn isCppSource(name: []const u8) bool {
    return std.mem.endsWith(u8, name, ".cc") or std.mem.endsWith(u8, name, ".cpp");
}

pub fn isSource(name: []const u8) bool {
    return isCSource(name) or isCppSource(name);
}

pub fn isCHeader(name: []const u8) bool {
    return std.mem.endsWith(u8, name, ".h");
}

pub fn isCppHeader(name: []const u8) bool {
    return std.mem.endsWith(u8, name, ".hpp") or std.mem.endsWith(u8, name, ".hpp11");
}

pub fn isHeader(name: []const u8) bool {
    return isCHeader(name) or isCppHeader(name);
}

pub fn exists(path: []const u8) bool {
    if (path.len == 0) return false;
    std.fs.accessAbsolute(path, .{}) catch return false;
    return true;
}

pub const Toolbox = struct {
    __builder: *std.Build,
    __mode: std.builtin.OptimizeMode,
    __dependencies: Dependencies,
    __fetch: bool,
    __update: bool,
    __zon_forks: std.StringHashMap([]const u8),
    __logging: bool,

    pub fn init(comptime FromZon: type, comptime DuringExec: type, builder: *std.Build, mode: std.builtin.OptimizeMode, pkg: EnumLiteral, fingerprint: []const u8, paths: []const []const u8, from_zon_deps: FromZon, during_exec_deps: DuringExec) !@This() {
        var self: @This() = .{
            .__builder = builder,
            .__mode = mode,
            .__dependencies = undefined,
            .__fetch = builder.option(bool, "fetch", "Update .references folder and build.zig.zon then stop execution") orelse false,
            .__update = builder.option(bool, "update", "Update binding") orelse false,
            .__logging = builder.option(bool, "toolbox-logging", "Enabled toolbox debug logging") orelse false,
            .__zon_forks = std.StringHashMap([]const u8).init(builder.allocator),
        };

        self.__dependencies = Dependencies.init(FromZon, DuringExec, &self, pkg, fingerprint, paths, from_zon_deps, during_exec_deps) catch |err| switch (err) {
            error.FetchDepsSucceed => std.process.exit(0),
            else => return err,
        };

        inline for (@typeInfo(FromZon).@"struct".fields) |field| {
            try self.addZonFork(field.name);
        }

        return self;
    }

    pub fn deinit(self: *@This()) void {
        self.ptrZonForks().deinit();
    }

    fn getMode(self: @This()) std.builtin.OptimizeMode {
        return self.__mode;
    }

    fn loggingEnabled(self: @This()) bool {
        return self.__logging;
    }

    pub fn getBuilder(self: @This()) *const std.Build {
        return self.__builder;
    }

    pub fn getAllocator(self: @This()) std.mem.Allocator {
        return self.getBuilder().allocator;
    }

    fn getDependencies(self: @This()) Dependencies {
        return self.__dependencies;
    }

    fn getFetch(self: @This()) bool {
        return self.__fetch;
    }

    pub fn getUpdate(self: @This()) bool {
        return self.__update;
    }

    fn ptrBuilder(self: *@This()) *std.Build {
        return self.__builder;
    }

    fn getZonForks(self: @This()) std.StringHashMap([]const u8) {
        return self.__zon_forks;
    }

    fn ptrZonForks(self: *@This()) *std.StringHashMap([]const u8) {
        return &self.__zon_forks;
    }

    fn getZonFork(self: @This(), key: []const u8) []const u8 {
        return self.getZonForks().get(key) orelse "";
    }

    fn addZonFork(self: *@This(), comptime key: []const u8) !void {
        try self.ptrZonForks().put(key, self.ptrBuilder().option([]const u8, key, "Switch to the given branch from a given fork for the " ++ key ++ " repository") orelse "");
    }

    pub fn clone(self: *@This(), repo: EnumLiteral, path: []const u8) !void {
        try self.getDependencies().clone(self, repo, path);
    }

    pub fn addHeader(self: @This(), lib: *std.Build.Step.Compile, source: []const u8, dest: []const u8, ext: []const []const u8) void {
        if (self.loggingEnabled()) {
            std.debug.print("[{s} header] {s}\n", .{
                lib.name, source,
            });
        }
        lib.installHeadersDirectory(.{
            .cwd_relative = source,
        }, dest, .{
            .include_extensions = ext,
        });
    }

    pub fn addInclude(self: *@This(), lib: *std.Build.Step.Compile, path: []const u8) void {
        const lazy = self.ptrBuilder().path(path);
        if (self.loggingEnabled()) {
            std.debug.print("[{s} include] {s}\n", .{
                lib.name, lazy.getPath(self.ptrBuilder()),
            });
        }
        lib.addIncludePath(lazy);
    }

    pub fn addSource(self: *@This(), lib: *std.Build.Step.Compile, root_path: []const u8, base_path: []const u8, flags: []const []const u8) !void {
        const source_path = self.pathJoin(&.{
            root_path, base_path,
        });
        if (self.loggingEnabled()) {
            std.debug.print("[{s} source] {s}\n", .{
                lib.name, source_path,
            });
        }
        lib.addCSourceFile(.{
            .file = .{
                .cwd_relative = source_path,
            },
            .flags = flags,
        });
    }

    pub fn write(self: @This(), path: []const u8, name: []const u8, content: []const u8) !void {
        if (self.loggingEnabled()) {
            std.debug.print("[write {s}/{s}]\n", .{
                path, name,
            });
        }
        var dir = try std.fs.openDirAbsolute(path, .{});
        defer dir.close();
        try dir.writeFile(.{
            .sub_path = name,
            .data = content,
        });
    }

    pub fn make(self: @This(), path: []const u8) !void {
        if (self.loggingEnabled()) {
            std.debug.print("[make {s}]\n", .{
                path,
            });
        }
        std.fs.makeDirAbsolute(path) catch |err|
            if (err != error.PathAlreadyExists) return err;
    }

    pub fn copy(self: @This(), src: []const u8, dest: []const u8) !void {
        if (self.loggingEnabled()) {
            std.debug.print("[copy {s} {s}]\n", .{
                src, dest,
            });
        }
        try std.fs.copyFileAbsolute(src, dest, .{});
    }

    pub fn run(self: @This(), proc: struct {
        argv: []const []const u8,
        cwd: ?[]const u8 = null,
        env: ?*const std.process.EnvMap = null,
        wait: ?*const fn () void = null,
        stdout: ?*[]const u8 = null,
        ignore_errors: bool = false,
    }) !void {
        var stdout: std.ArrayListUnmanaged(u8) = .empty;
        var stderr: std.ArrayListUnmanaged(u8) = .empty;

        if (self.getMode() == .Debug) {
            std.debug.print("\x1b[35m[{s}]\x1b[0m\n", .{
                try std.mem.join(self.getAllocator(), " ", proc.argv),
            });
        }

        var child = std.process.Child.init(proc.argv, self.getAllocator());

        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        child.cwd = proc.cwd;
        child.env_map = proc.env;

        try child.spawn();

        var term: std.process.Child.Term = undefined;
        if (proc.wait) |wait| {
            wait();
            term = try child.kill();
        } else {
            try child.collectOutput(self.getAllocator(), &stdout, &stderr, std.math.maxInt(usize));
            term = try child.wait();
        }
        const exit_success = std.process.Child.Term{
            .Exited = 0,
        };
        if (!proc.ignore_errors and stderr.items.len > 0 and !std.meta.eql(term, exit_success)) {
            std.debug.print("\x1b[31m{s}\x1b[0m", .{
                stderr.items,
            });
        }
        if (!proc.ignore_errors and proc.wait == null) {
            try std.testing.expectEqual(term, exit_success);
        }

        if (proc.stdout) |out| {
            out.* = std.mem.trim(u8, try stdout.toOwnedSlice(self.getAllocator()), " \n");
        } else if (self.loggingEnabled()) {
            std.debug.print("{s}", .{
                stdout.items,
            });
        }
    }

    pub fn clean(self: *@This(), paths: []const []const u8, extensions: []const []const u8) !void {
        var flag: bool = undefined;
        var dir: std.fs.Dir = undefined;
        var root_path: []const u8 = undefined;
        var walker: std.fs.Dir.Walker = undefined;

        for (paths) |path| {
            dir = try self.getBuilder().build_root.handle.openDir(path, .{
                .iterate = true,
            });
            defer dir.close();

            root_path = try self.buildRootJoin(&.{
                path,
            });

            flag = true;
            while (flag) {
                flag = false;

                walker = try dir.walk(self.getAllocator());
                defer walker.deinit();

                walk: while (try walker.next()) |*entry| {
                    const entry_abspath = self.pathJoin(&.{
                        root_path, entry.path,
                    });
                    switch (entry.kind) {
                        .file => {
                            for (extensions) |ext|
                                if (std.mem.endsWith(u8, entry.basename, ext)) continue :walk;
                            if (isSource(entry.basename) or
                                isHeader(entry.basename)) continue :walk;
                            try std.fs.deleteFileAbsolute(entry_abspath);
                            if (self.loggingEnabled()) {
                                std.debug.print("[clean] {s}\n", .{
                                    entry_abspath,
                                });
                            }
                            flag = true;
                        },
                        .directory => {
                            std.fs.deleteDirAbsolute(entry_abspath) catch |err|
                                if (err == error.DirNotEmpty) continue :walk else return err;
                            if (self.loggingEnabled()) {
                                std.debug.print("[clean] {s}\n", .{
                                    entry_abspath,
                                });
                            }
                            flag = true;
                        },
                        else => {},
                    }
                }
            }
        }
    }

    pub fn buildRootJoin(self: @This(), paths: []const []const u8) ![]u8 {
        return self.getBuilder().build_root.join(self.getAllocator(), paths);
    }

    pub fn pathJoin(self: *@This(), paths: []const []const u8) []u8 {
        return self.ptrBuilder().pathJoin(paths);
    }

    pub fn fmt(self: *@This(), comptime format: []const u8, args: anytype) []u8 {
        return self.ptrBuilder().fmt(format, args);
    }

    pub fn dupe(self: *@This(), bytes: []const u8) []u8 {
        return self.ptrBuilder().dupe(bytes);
    }

    pub fn reference(self: *@This(), repo: EnumLiteral) ![]const u8 {
        const path = try self.buildRootJoin(&.{
            ".references", @tagName(repo),
        });
        return std.mem.trim(u8, try self.getBuilder().build_root.handle.readFileAlloc(self.getAllocator(), path, std.math.maxInt(usize)), " \n");
    }
};

const Repository = struct {
    const Host = enum {
        github,
        gitlab,
    };

    const Reference = enum {
        tag,
        commit,
    };

    __name: []const u8,
    __url: []const u8,
    __latest: []const u8,
    __ref: Reference,

    fn init(toolbox: *Toolbox, name: []const u8, url: []const u8, latest: ?[]const u8, ref: Reference) @This() {
        return .{
            .__name = toolbox.dupe(name),
            .__url = toolbox.dupe(url),
            .__latest = if (latest) |tag| toolbox.dupe(tag) else "",
            .__ref = ref,
        };
    }

    fn getName(self: @This()) []const u8 {
        return self.__name;
    }

    fn getUrl(self: @This()) []const u8 {
        return self.__url;
    }

    fn getLatest(self: @This()) []const u8 {
        return self.__latest;
    }

    fn ptrLatest(self: *@This()) *[]const u8 {
        return &self.__latest;
    }

    fn getRef(self: @This()) Reference {
        return self.__ref;
    }

    fn isLatestValid(self: @This()) !void {
        if (std.mem.indexOfAny(u8, self.getLatest(), "0123456789") == null or std.mem.indexOfScalar(u8, self.getLatest(), '.') == null) return error.InvalidLatest;
    }

    fn getShortLatest(self: @This()) []const u8 {
        return switch (self.getRef()) {
            .tag => self.getLatest(),
            .commit => self.getLatest()[0..7],
        };
    }

    fn searchLatest(self: *@This(), toolbox: *Toolbox, branch_opt: ?[]const u8) !void {
        var tmp_dir = std.testing.tmpDir(.{});
        defer tmp_dir.cleanup();
        const tmp = try tmp_dir.dir.realpathAlloc(toolbox.getAllocator(), ".");

        try toolbox.run(.{
            .argv = if (branch_opt) |branch| &[_][]const u8{
                "git", "clone", "--bare", "--branch", branch, "--filter=blob:none", "--", self.getUrl(), &tmp_dir.sub_path,
            } else &[_][]const u8{
                "git", "clone", "--bare", "--filter=blob:none", "--", self.getUrl(), &tmp_dir.sub_path,
            },
            .cwd = try tmp_dir.parent_dir.realpathAlloc(toolbox.getAllocator(), "."),
        });

        switch (self.getRef()) {
            .commit => try self.searchLatestCommit(toolbox, tmp),
            .tag => try self.searchLatestTag(toolbox, tmp),
        }
    }

    fn searchLatestCommit(self: *@This(), toolbox: *Toolbox, tmp: []const u8) !void {
        try toolbox.run(.{
            .argv = &[_][]const u8{
                "git", "rev-parse", "HEAD",
            },
            .cwd = tmp,
            .stdout = self.ptrLatest(),
        });
    }

    fn searchLatestTag(self: *@This(), toolbox: *Toolbox, tmp: []const u8) !void {
        var commit: []const u8 = undefined;
        for (0..std.math.maxInt(usize)) |i| {
            commit = toolbox.fmt("HEAD~{}", .{
                i,
            });
            try toolbox.run(.{
                .argv = &[_][]const u8{
                    "git", "describe", "--tags", "--exact-match", commit,
                },
                .cwd = tmp,
                .stdout = self.ptrLatest(),
                .ignore_errors = true,
            });
            self.isLatestValid() catch continue;
            break;
        } else return error.NoValidTag;
    }
};

const Dependencies = struct {
    __from_zon_deps: std.StringHashMap(Repository),
    __during_exec_deps: std.StringHashMap(Repository),

    fn getFromZonDeps(self: @This()) std.StringHashMap(Repository) {
        return self.__from_zon_deps;
    }

    fn getDuringExecDeps(self: @This()) std.StringHashMap(Repository) {
        return self.__during_exec_deps;
    }

    fn ptrFromZonDeps(self: *@This()) *std.StringHashMap(Repository) {
        return &self.__from_zon_deps;
    }

    fn ptrDuringExecDeps(self: *@This()) *std.StringHashMap(Repository) {
        return &self.__during_exec_deps;
    }

    fn getFromZon(self: @This(), key: []const u8) Repository {
        return self.getFromZonDeps().get(key).?;
    }

    fn getDuringExec(self: @This(), key: []const u8) Repository {
        return self.getDuringExecDeps().get(key).?;
    }

    fn getFromZonKeys(self: @This()) std.StringHashMap(Repository).KeyIterator {
        return self.getFromZonDeps().keyIterator();
    }

    fn getDuringExecKeys(self: @This()) std.StringHashMap(Repository).KeyIterator {
        return self.getDuringExecDeps().keyIterator();
    }

    fn init(comptime FromZon: type, comptime DuringExec: type, toolbox: *Toolbox, pkg: EnumLiteral, fingerprint: []const u8, paths: []const []const u8, from_zon_deps: FromZon, during_exec_deps: DuringExec) !@This() {
        var self: @This() = .{
            .__from_zon_deps = std.StringHashMap(Repository).init(toolbox.getAllocator()),
            .__during_exec_deps = std.StringHashMap(Repository).init(toolbox.getAllocator()),
        };

        var repository: Repository = undefined;
        inline for (.{
            from_zon_deps, during_exec_deps,
        }, &.{
            ptrFromZonDeps, ptrDuringExecDeps,
        }) |@"struct", func| {
            inline for (@typeInfo(@TypeOf(@"struct")).@"struct".fields) |field| {
                const struct_name = @field(@"struct", field.name).name;
                const struct_host = @field(@"struct", field.name).host;
                const struct_ref = @field(@"struct", field.name).ref;
                const struct_branch = @field(@"struct", field.name).branch;
                const fork = toolbox.getZonFork(field.name);
                const name = if (std.mem.indexOfScalar(u8, fork, ':')) |i| fork[0..i] else struct_name;
                const branch = if (std.mem.indexOfScalar(u8, fork, ':')) |i| fork[i + 1 ..] else if (struct_branch.len > 0) struct_branch else null;
                repository = Repository.init(toolbox, name, switch (struct_host) {
                    .github => toolbox.fmt("https://github.com/{s}", .{
                        name,
                    }),
                    .gitlab => toolbox.fmt("https://gitlab.{s}/{s}", .{
                        @field(@"struct", field.name).domain, name,
                    }),
                }, null, struct_ref);
                if (toolbox.getFetch()) try repository.searchLatest(toolbox, branch);
                try @call(.auto, func, .{
                    &self,
                }).put(field.name, repository);
            }
        }

        if (toolbox.getFetch()) {
            try self.fetchDuringExecDeps(toolbox);
            try self.fetchFromZonDeps(toolbox, pkg, fingerprint, paths);
            return error.FetchDepsSucceed;
        }

        return self;
    }

    fn clone(self: @This(), toolbox: *Toolbox, repo: EnumLiteral, path: []const u8) !void {
        switch (self.getDuringExec(@tagName(repo)).getRef()) {
            .tag => try toolbox.run(.{
                .argv = &[_][]const u8{
                    "git", "clone", "--branch", try toolbox.reference(repo), "--depth", "1", "--", self.getDuringExec(@tagName(repo)).getUrl(), path,
                },
            }),
            .commit => {
                try toolbox.run(.{
                    .argv = &[_][]const u8{
                        "git", "clone", "--", self.getDuringExec(@tagName(repo)).getUrl(), path,
                    },
                });
                try toolbox.run(.{
                    .argv = &[_][]const u8{
                        "git", "checkout", try toolbox.reference(repo),
                    },
                    .cwd = path,
                });
            },
        }
    }

    fn fetchDuringExecDeps(self: @This(), toolbox: *Toolbox) !void {
        var references_dir = try toolbox.getBuilder().build_root.handle.openDir(".references", .{});
        defer references_dir.close();

        var it = self.getDuringExecKeys();
        while (it.next()) |key| {
            try references_dir.deleteFile(key.*);
            try references_dir.writeFile(.{
                .sub_path = key.*,
                .data = toolbox.fmt("{s}\n", .{
                    self.getDuringExec(key.*).getShortLatest(),
                }),
            });
        }
    }

    fn fetchFromZonDeps(self: @This(), toolbox: *Toolbox, pkg: EnumLiteral, fingerprint: []const u8, additional_paths: []const []const u8) !void {
        var buffer = std.ArrayList(u8).init(toolbox.getAllocator());
        const writer = buffer.writer();

        try writer.print(
            \\.{c}
            \\    .name = {},
            \\    .version = "1.0.0",
            \\    .minimum_zig_version = "{}.{}.{}",
            \\    .fingerprint = {s},
            \\    .paths = .{c}
            \\
        , .{
            '{', pkg, builtin.zig_version.major, builtin.zig_version.minor, builtin.zig_version.patch, fingerprint, '{',
        });

        var build_dir = try toolbox.getBuilder().build_root.handle.openDir(".", .{
            .iterate = true,
        });
        defer build_dir.close();

        try writer.print("\"build.zig\",\n\"build.zig.zon\",\n", .{});

        for (additional_paths) |path| {
            try writer.print("\"{s}\",\n", .{
                path,
            });
        }

        try writer.print("{c},\n{c}\n", .{
            '}', '}',
        });

        try buffer.append(0);
        const source = buffer.items[0 .. buffer.items.len - 1 :0];

        const validated = try std.zig.Ast.parse(toolbox.getAllocator(), source, .zon);
        const formatted = try validated.render(toolbox.getAllocator());

        try toolbox.getBuilder().build_root.handle.deleteFile("build.zig.zon");
        try toolbox.getBuilder().build_root.handle.writeFile(.{
            .sub_path = "build.zig.zon",
            .data = formatted,
        });

        var it = self.getFromZonKeys();
        while (it.next()) |key| {
            const url = toolbox.fmt("git+{s}#{s}", .{
                self.getFromZon(key.*).getUrl(), self.getFromZon(key.*).getLatest(),
            });
            try toolbox.run(.{
                .argv = &[_][]const u8{
                    "zig", "fetch", "--save", url,
                },
            });
        }
    }
};

pub fn build(builder: *std.Build) !void {
    _ = builder.addModule("toolbox", .{
        .root_source_file = builder.addWriteFiles().add("empty.zig", ""),
    });

    if (@import("builtin").os.tag != .windows) {
        const clean_step = builder.step("clean", "Clean up");

        clean_step.dependOn(&builder.addRemoveDirTree(.{
            .cwd_relative = builder.install_path,
        }).step);

        clean_step.dependOn(&builder.addRemoveDirTree(.{
            .cwd_relative = builder.pathFromRoot("zig-cache"),
        }).step);
    }
}
