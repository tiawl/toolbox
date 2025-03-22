const std = @import("std");
const builtin = @import("builtin");

var singleton: ?Toolbox = null;

pub fn isInit() bool {
    return singleton != null;
}

pub fn init(builder: *std.Build, mode: std.builtin.OptimizeMode) void {
    if (!isInit()) {
        singleton = undefined;
        singleton.?.init(builder, mode);
    }
}

pub fn deinit() void {
    if (singleton) |*toolbox| toolbox.deinit();
    singleton = null;
}

pub fn instance() *Toolbox {
    return if (singleton) |*toolbox| toolbox else @panic("Toolbox not initialized");
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

const Toolbox = struct {
    __builder: *std.Build,
    __mode: std.builtin.OptimizeMode,

    fn init(self: *@This(), builder: *std.Build, mode: std.builtin.OptimizeMode) void {
        self.* = .{
            .__builder = builder,
            .__mode = mode,
        };
    }

    fn deinit(_: *@This()) void {}

    fn getMode(self: @This()) std.builtin.OptimizeMode {
        return self.__mode;
    }

    pub fn getBuilder(self: @This()) *const std.Build {
        return self.__builder;
    }

    pub fn ptrBuilder(self: *@This()) *std.Build {
        return self.__builder;
    }

    pub fn addHeader(self: @This(), lib: *std.Build.Step.Compile, source: []const u8, dest: []const u8, ext: []const []const u8) void {
        if (self.getMode() == .Debug) {
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
        if (self.getMode() == .Debug) {
            std.debug.print("[{s} include] {s}\n", .{
                lib.name, lazy.getPath(self.ptrBuilder()),
            });
        }
        lib.addIncludePath(lazy);
    }

    pub fn addSource(self: *@This(), lib: *std.Build.Step.Compile, root_path: []const u8, base_path: []const u8, flags: []const []const u8) !void {
        const source_path = self.ptrBuilder().pathJoin(&.{
            root_path, base_path,
        });
        if (self.getMode() == .Debug) {
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
        if (self.getMode() == .Debug) {
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
        if (self.getMode() == .Debug) {
            std.debug.print("[make {s}]\n", .{
                path,
            });
        }
        std.fs.makeDirAbsolute(path) catch |err|
            if (err != error.PathAlreadyExists) return err;
    }

    pub fn copy(self: @This(), src: []const u8, dest: []const u8) !void {
        if (self.getMode() == .Debug) {
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
                try std.mem.join(self.getBuilder().allocator, " ", proc.argv),
            });
        }

        var child = std.process.Child.init(proc.argv, self.getBuilder().allocator);

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
            try child.collectOutput(self.getBuilder().allocator, &stdout, &stderr, std.math.maxInt(usize));
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
            std.debug.print("{s}", .{
                stdout.items,
            });
            out.* = std.mem.trim(u8, try stdout.toOwnedSlice(self.getBuilder().allocator), " \n");
        } else if (self.getMode() == .Debug) {
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

            root_path = try self.getBuilder().build_root.join(self.getBuilder().allocator, &.{
                path,
            });

            flag = true;
            while (flag) {
                flag = false;

                walker = try dir.walk(self.getBuilder().allocator);
                defer walker.deinit();

                walk: while (try walker.next()) |*entry| {
                    const entry_abspath = self.ptrBuilder().pathJoin(&.{
                        root_path, entry.path,
                    });
                    switch (entry.kind) {
                        .file => {
                            for (extensions) |ext|
                                if (std.mem.endsWith(u8, entry.basename, ext)) continue :walk;
                            if (isSource(entry.basename) or
                                isHeader(entry.basename)) continue :walk;
                            try std.fs.deleteFileAbsolute(entry_abspath);
                            if (self.getMode() == .Debug) {
                                std.debug.print("[clean] {s}\n", .{
                                    entry_abspath,
                                });
                            }
                            flag = true;
                        },
                        .directory => {
                            std.fs.deleteDirAbsolute(entry_abspath) catch |err|
                                if (err == error.DirNotEmpty) continue :walk else return err;
                            if (self.getMode() == .Debug) {
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
};

pub const Repository = struct {
    pub const Host = enum {
        github,
        gitlab,
    };

    pub const Reference = enum {
        tag,
        commit,
    };

    __name: []const u8,
    __url: []const u8,
    __latest: []const u8,
    __ref: Reference,

    fn init(name: []const u8, url: []const u8, latest: ?[]const u8, ref: Reference) @This() {
        return .{
            .__name = instance().ptrBuilder().dupe(name),
            .__url = instance().ptrBuilder().dupe(url),
            .__latest = if (latest) |tag| instance().ptrBuilder().dupe(tag) else "",
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
        std.debug.print("latest = {s}\n", .{self.getLatest()});
        _ = try std.SemanticVersion.parse(self.getLatest());
    }

    fn getShortLatest(self: @This()) []const u8 {
        return switch (self.getRef()) {
            .tag => self.getLatest(),
            .commit => self.getLatest()[0..7],
        };
    }

    fn searchLatest(self: *@This(), branch_opt: ?[]const u8) !void {
        var tmp_dir = std.testing.tmpDir(.{});
        const tmp = try tmp_dir.dir.realpathAlloc(instance().getBuilder().allocator, ".");

        try instance().run(.{
            .argv = if (branch_opt) |branch| &[_][]const u8{
                "git", "clone", "--bare", "--branch", branch, "--filter=blob:none", self.getUrl(), tmp,
            } else &[_][]const u8{
                "git", "clone", "--bare", "--filter=blob:none", self.getUrl(), tmp,
            },
        });

        switch (self.getRef()) {
            .commit => try self.searchLatestCommit(tmp),
            .tag => try self.searchLatestTag(tmp),
        }
    }

    fn searchLatestCommit(self: *@This(), tmp: []const u8) !void {
        try instance().run(.{
            .argv = &[_][]const u8{
                "git", "rev-parse", "HEAD",
            },
            .cwd = tmp,
            .stdout = self.ptrLatest(),
        });
    }

    fn searchLatestTag(self: *@This(), tmp: []const u8) !void {
        var commit: []const u8 = undefined;
        for (0..std.math.maxInt(usize)) |i| {
            commit = instance().ptrBuilder().fmt("HEAD~{}", .{
                i,
            });
            try instance().run(.{
                .argv = &[_][]const u8{
                    "git", "describe", "--tags", "--exact-match", commit,
                },
                .cwd = tmp,
                .stdout = self.ptrLatest(),
                .ignore_errors = true,
            });
            try self.isLatestValid();
        } else return error.NoValidTag;
    }

    const Github = struct {
        fn url(name: []const u8) []const u8 {
            return instance().ptrBuilder().fmt("https://github.com/{s}", .{
                name,
            });
        }
    };

    const Gitlab = struct {
        fn url(domain: []const u8, name: []const u8) []const u8 {
            return instance().ptrBuilder().fmt("https://gitlab.{s}/{s}", .{
                domain, name,
            });
        }
    };
};

pub fn reference(repo: []const u8) ![]const u8 {
    const path = try instance().getBuilder().build_root.join(instance().getBuilder().allocator, &.{
        ".references", repo,
    });
    return std.mem.trim(u8, try instance().getBuilder().build_root.handle.readFileAlloc(instance().getBuilder().allocator, path, std.math.maxInt(usize)), " \n");
}

pub const Dependencies = struct {
    __intern: std.StringHashMap(Repository),
    __extern: std.StringHashMap(Repository),

    fn getIntern(self: @This(), key: []const u8) Repository {
        return self.__intern.get(key).?;
    }

    fn getExtern(self: @This(), key: []const u8) Repository {
        return self.__extern.get(key).?;
    }

    fn getInterns(self: @This()) std.StringHashMap(Repository).KeyIterator {
        return self.__intern.keyIterator();
    }

    fn getExterns(self: @This()) std.StringHashMap(Repository).KeyIterator {
        return self.__extern.keyIterator();
    }

    pub fn init(pkg: @Type(.enum_literal), fingerprint: []const u8, paths: []const []const u8, intern_proto: anytype, extern_proto: anytype) !@This() {
        var self = @This(){
            .__intern = std.StringHashMap(Repository).init(instance().getBuilder().allocator),
            .__extern = std.StringHashMap(Repository).init(instance().getBuilder().allocator),
        };

        const fetch = instance().ptrBuilder().option(bool, "fetch", "Update .references folder and build.zig.zon then stop execution") orelse false;

        var repository: Repository = undefined;
        inline for (.{
            intern_proto, extern_proto,
        }, &.{
            "__intern", "__extern",
        }) |proto, attr| {
            inline for (@typeInfo(@TypeOf(proto)).@"struct".fields) |field| {
                const proto_name = @field(proto, field.name).name;
                const proto_host = @field(proto, field.name).host;
                const proto_ref = @field(proto, field.name).ref;
                const module_name = proto_name[std.mem.indexOfScalar(u8, proto_name, '/').? + 1 ..];
                const fork = instance().ptrBuilder().option([]const u8, module_name, "Switch to the given branch from a given fork for the " ++ proto_name ++ " repository") orelse "";
                const name = if (std.mem.indexOfScalar(u8, fork, ':')) |i| fork[0..i] else proto_name;
                const branch = if (std.mem.indexOfScalar(u8, fork, ':')) |i| fork[i + 1 ..] else null;
                repository = Repository.init(name, switch (proto_host) {
                    .github => Repository.Github.url(name),
                    .gitlab => Repository.Gitlab.url(@field(proto, field.name).domain, name),
                }, null, proto_ref);
                if (fetch) try repository.searchLatest(branch);
                try @field(self, attr).put(field.name, repository);
            }
        }

        if (fetch) {
            try self.fetchExtern();
            try self.fetchIntern(pkg, fingerprint, paths);
            std.process.exit(0);
        }

        return self;
    }

    pub fn clone(self: @This(), repo: []const u8, path: []const u8) !void {
        switch (self.getExtern(repo).getRef()) {
            .tag => try instance().run(.{
                .argv = &[_][]const u8{
                    "git", "clone", "--branch", try reference(repo), "--depth", "1", self.getExtern(repo).getUrl(), path,
                },
            }),
            .commit => {
                try instance().run(.{
                    .argv = &[_][]const u8{
                        "git", "clone", self.getExtern(repo).getUrl(), path,
                    },
                });
                try instance().run(.{
                    .argv = &[_][]const u8{
                        "git", "checkout", try reference(repo),
                    },
                    .cwd = path,
                });
            },
        }
    }

    fn fetchExtern(self: @This()) !void {
        var references_dir = try instance().getBuilder().build_root.handle.openDir(".references", .{});
        defer references_dir.close();

        var it = self.getExterns();
        while (it.next()) |key| {
            try references_dir.deleteFile(key.*);
            try references_dir.writeFile(.{
                .sub_path = key.*,
                .data = instance().ptrBuilder().fmt("{s}\n", .{
                    self.getExtern(key.*).getShortLatest(),
                }),
            });
        }
    }

    fn fetchIntern(self: @This(), pkg: @Type(.enum_literal), fingerprint: []const u8, additional_paths: []const []const u8) !void {
        var buffer = std.ArrayList(u8).init(instance().getBuilder().allocator);
        const writer = buffer.writer();

        try writer.print(
            \\.{c}
            \\    .name = {},
            \\    .version = "1.0.0",
            \\    .minimum_zig_version = "{}.{}.0",
            \\    .fingerprint = {s},
            \\    .paths = .{c}
            \\
        , .{
            '{', pkg, builtin.zig_version.major, builtin.zig_version.minor, fingerprint, '{',
        });

        var build_dir = try instance().getBuilder().build_root.handle.openDir(".", .{
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

        const validated = try std.zig.Ast.parse(instance().getBuilder().allocator, source, .zon);
        const formatted = try validated.render(instance().getBuilder().allocator);

        try instance().getBuilder().build_root.handle.deleteFile("build.zig.zon");
        try instance().getBuilder().build_root.handle.writeFile(.{
            .sub_path = "build.zig.zon",
            .data = formatted,
        });

        var it = self.getInterns();
        while (it.next()) |key| {
            const url = instance().ptrBuilder().fmt("git+{s}#{s}", .{
                self.getIntern(key.*).getUrl(), self.getIntern(key.*).getLatest(),
            });
            try instance().run(.{
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
