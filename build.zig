const std = @import("std");
const builtin = @import("builtin");

pub const ext = struct {
    pub const source = struct {
        pub const c = [_][]const u8{".c"};
        pub const cpp = struct {
            pub const pure = [_][]const u8{ ".cc", ".cpp", ".cxx" };
            pub const c_compatible = ext.source.c ++ ext.source.cpp.pure;
        };
    };

    pub const header = struct {
        pub const c = [_][]const u8{".h"};
        pub const cpp = struct {
            pub const pure = [_][]const u8{ ".hh", ".hpp", ".hxx" };
            pub const c_compatible = ext.header.c ++ ext.header.cpp.pure;
            pub const @"11" = struct {
                pub const pure = ext.header.cpp.pure ++ [_][]const u8{".hpp11"};
                pub const c_compatible = ext.header.c ++ ext.header.cpp.@"11".pure;
            };
        };
    };
};

inline fn checkExt(name: []const u8, exts: []const []const u8) bool {
    var res = false;
    inline for (exts) |e| res = (res or std.mem.endsWith(u8, name, e));
    return res;
}

pub inline fn isCSource(name: []const u8) bool {
    return checkExt(name, &ext.source.c);
}

pub inline fn isCppSource(name: []const u8) bool {
    return checkExt(name, &ext.source.cpp.pure);
}

pub inline fn isSource(name: []const u8) bool {
    return checkExt(name, &ext.source.cpp.c_compatible);
}

pub inline fn isCHeader(name: []const u8) bool {
    return checkExt(name, &ext.header.c);
}

pub inline fn isCppHeader(name: []const u8) bool {
    return checkExt(name, &ext.header.cpp.pure);
}

pub inline fn isHeader(name: []const u8) bool {
    return checkExt(name, &ext.header.cpp.c_compatible);
}

pub const VerboseBuilder = struct {
    const BuildOptions = struct {
        __fetch: bool,
        __update: bool,
        __verbose: bool = false,
    };

    __builder: *std.Build,
    __optimize: std.builtin.OptimizeMode,
    __target: std.Build.ResolvedTarget,
    __options: BuildOptions,
    __walker: ?std.fs.Dir.Walker,
    __dir: std.fs.Dir,
    __prefix: []const u8,
    __build_fn: ?*const fn (*@This()) anyerror!void,
    __update_fn: ?*const fn (*@This()) anyerror!void,

    pub fn init(builder: *std.Build, zon: anytype, build_fn: ?*const fn (*@This()) anyerror!void, update_fn: ?*const fn (*@This()) anyerror!void) !@This() {
        builder.dep_prefix = @tagName(zon.name) ++ ".";
        var self: @This() = .{
            .__builder = builder,
            .__optimize = builder.standardOptimizeOption(.{}),
            .__target = builder.standardTargetOptions(.{}),
            .__options = undefined,
            .__walker = null,
            .__dir = builder.build_root.handle,
            .__prefix = "/",
            .__build_fn = build_fn,
            .__update_fn = update_fn,
        };

        self.ptrOptions().__verbose = self.option(bool, false, "verbose", "Enabled toolbox debug logging");
        self.ptrOptions().__fetch = self.option(bool, false, "fetch", "Update build.zig.zon then stop execution");
        self.ptrOptions().__update = self.option(bool, false, "update", "Update binding");

        return self;
    }

    pub fn initFromDependency(self: @This(), dep: *std.Build.Dependency) @This() {
        dep.builder.dep_prefix = dep.builder.dep_prefix[self.getBuilder().dep_prefix.len..];
        const other: @This() = .{
            .__builder = dep.builder,
            .__optimize = self.getOptimize(),
            .__target = self.getTarget(),
            .__options = self.getOptions(),
            .__walker = null,
            .__dir = dep.builder.build_root.handle,
            .__prefix = "/",
            .__build_fn = null,
            .__update_fn = null,
        };
        return other;
    }

    pub fn build(self: *@This()) !void {
        try self.getBuildFn()(self);
    }

    pub fn update(self: *@This()) !void {
        if (self.needUpdate()) try self.getUpdateFn()(self);
    }

    pub fn fetch(self: *@This(), zon: anytype) !void {
        if (!self.needFetch()) return;
        inline for (std.meta.fields(@TypeOf(zon.dependencies))) |field| {
            if (!@hasField(@TypeOf(@field(zon.dependencies, field.name)), "url")) continue;
            const uri = try std.Uri.parse(@field(zon.dependencies, field.name).url);
            const host = uri.getHostAlloc(self.getAllocator()) catch @panic("OOM");
            const path = self.uriComponent(uri.path);
            var tmp = std.testing.tmpDir(.{});
            defer tmp.cleanup();
            const tmp_path = self.pathJoin(&.{ self.getBuilder().cache_root.path.?, "tmp", tmp.sub_path });
            if (@hasField(@TypeOf(@field(zon.dependencies, field.name)), "branch")) {
                _ = try self.run(&.{ "git", "clone", "--bare", "--branch", @field(zon.dependencies, field.name).branch, "--filter=blob:none", "--", self.fmt("https://{s}{s}", .{ host, path }), tmp_path }, self.ptrRoot().handle);
            } else {
                _ = try self.run(&.{ "git", "clone", "--bare", "--filter=blob:none", "--", self.fmt("https://{s}{s}", .{ host, path }), tmp_path }, self.ptrRoot().handle);
            }
            var latest: []const u8 = undefined;
            if (uri.query) |_| {
                const commits = try std.fmt.parseUnsigned(usize, try self.run(&.{ "git", "rev-list", "--count", "--all" }, tmp.dir), 10);
                for (0..commits) |i| {
                    latest = self.run(&.{ "git", "describe", "--tags", "--exact-match", self.fmt("HEAD~{}", .{i}) }, tmp.dir) catch |err| switch (err) {
                        error.ExitCodeFailure => continue,
                        else => return err,
                    };
                    if (std.mem.indexOfAny(u8, latest, "0123456789.") == null) continue;
                    break;
                } else return error.NoValidTag;
            } else {
                latest = try self.run(&.{ "git", "rev-parse", "HEAD" }, tmp.dir);
            }
            _ = try self.run(&.{ "zig", "fetch", "--save=" ++ field.name, self.fmt("git+https://{s}{s}#{s}", .{ host, path, latest }) }, self.ptrRoot().handle);
        }
    }

    // inlined ----------------------------------------------------------------

    inline fn getBuilder(self: @This()) *const std.Build {
        return self.__builder;
    }

    inline fn ptrBuilder(self: @This()) *std.Build {
        return self.__builder;
    }

    inline fn getAllocator(self: @This()) std.mem.Allocator {
        return self.getBuilder().allocator;
    }

    inline fn ptrRoot(self: *@This()) *std.Build.Cache.Directory {
        return &self.ptrBuilder().build_root;
    }

    pub inline fn getInstallStep(self: *@This()) *std.Build.Step {
        return self.ptrBuilder().getInstallStep();
    }

    inline fn ptrCwd(self: *@This()) *std.fs.Dir {
        return &self.ptrRoot().handle;
    }

    inline fn ptrDir(self: *@This()) *std.fs.Dir {
        return &self.__dir;
    }

    inline fn getPrefix(self: @This()) []const u8 {
        return self.__prefix;
    }

    inline fn ptrPrefix(self: *@This()) *[]const u8 {
        return &self.__prefix;
    }

    pub inline fn getOptimize(self: @This()) std.builtin.OptimizeMode {
        return self.__optimize;
    }

    pub inline fn getTarget(self: @This()) std.Build.ResolvedTarget {
        return self.__target;
    }

    inline fn getWalker(self: @This()) ?std.fs.Dir.Walker {
        return self.__walker;
    }

    inline fn ptrWalker(self: *@This()) *std.fs.Dir.Walker {
        return &self.__walker.?;
    }

    inline fn getOptions(self: @This()) BuildOptions {
        return self.__options;
    }

    inline fn ptrOptions(self: *@This()) *BuildOptions {
        return &self.__options;
    }

    inline fn getBuildFn(self: @This()) *const fn (*@This()) anyerror!void {
        return self.__build_fn.?;
    }

    inline fn getUpdateFn(self: @This()) *const fn (*@This()) anyerror!void {
        return self.__update_fn.?;
    }

    inline fn isVerbose(self: @This()) bool {
        return self.getOptions().__verbose;
    }

    inline fn needUpdate(self: @This()) bool {
        return self.getOptions().__update;
    }

    inline fn needFetch(self: @This()) bool {
        return self.getOptions().__fetch;
    }

    inline fn debug(self: @This(), comptime f: []const u8, args: anytype) void {
        if (self.isVerbose()) std.log.debug(f, args);
    }

    // std.mem wrappers -------------------------------------------------------

    pub inline fn pathJoin(self: *@This(), paths: []const []const u8) []const u8 {
        return self.ptrBuilder().pathJoin(paths);
    }

    pub inline fn join(self: @This(), sep: []const u8, slices: []const []const u8) []const u8 {
        return std.mem.join(self.getAllocator(), sep, slices) catch @panic("OOM");
    }

    pub inline fn concat(self: @This(), slices: []const []const u8) []const u8 {
        return std.mem.concat(self.getAllocator(), u8, slices) catch @panic("OOM");
    }

    pub inline fn replace(self: @This(), input: []const u8, search: []const u8, rep: []const u8) []const u8 {
        return std.mem.replaceOwned(u8, self.getAllocator(), input, search, rep) catch @panic("OOM");
    }

    pub inline fn fmt(self: *@This(), comptime f: []const u8, args: anytype) []const u8 {
        return self.ptrBuilder().fmt(f, args);
    }

    pub inline fn uriComponent(self: @This(), component: *std.Uri.Component) []const u8 {
        return component.toRawMaybeAlloc(self.getAllocator()) catch @panic("OOM");
    }

    // std.Build wrappers -----------------------------------------------------

    pub fn option(self: *@This(), comptime T: type, default: T, name: []const u8, description: []const u8) T {
        const opt = self.ptrBuilder().option(T, name, description) orelse default;
        self.debug("-D{s} option: {}", .{ name, opt });
        return opt;
    }

    pub fn dependency(self: *@This(), name: []const u8) *std.Build.Dependency {
        self.debug("Requesting \"{s}\" dependency", .{name});
        return self.ptrBuilder().dependency(name, .{
            .optimize = self.getOptimize(),
            .target = self.getTarget(),
        });
    }

    pub fn addExecutable(self: *@This(), name: []const u8) *std.Build.Step.Compile {
        self.debug("Creating \"{s}\" executable", .{name});
        return self.ptrBuilder().addExecutable(.{
            .name = name,
            .root_module = std.Build.Module.create(self.ptrBuilder(), .{
                .target = self.getTarget(),
                .optimize = self.getOptimize(),
            }),
        });
    }

    pub fn addLibrary(self: *@This(), name: []const u8) *std.Build.Step.Compile {
        self.debug("Creating \"{s}\" library", .{name});
        return self.ptrBuilder().addLibrary(.{
            .name = name,
            .root_module = std.Build.Module.create(self.ptrBuilder(), .{
                .root_source_file = self.ptrBuilder().addWriteFiles().add("empty.zig", ""),
                .target = self.getTarget(),
                .optimize = self.getOptimize(),
            }),
        });
    }

    pub fn linkLibC(self: *@This(), compile: *std.Build.Step.Compile) void {
        self.debug("Linking LibC to \"{s}\" compile step", .{compile.name});
        compile.linkLibC();
    }

    pub fn addCSource(self: *@This(), compile: *std.Build.Step.Compile, paths: []const []const u8, flags: []const []const u8) void {
        const path = self.pathJoin(paths);
        self.debug("Adding C Source {s} to \"{s}\" compile step", .{ path, compile.name });
        compile.addCSourceFile(self.ptrBuilder().path(path), flags);
    }

    pub fn addInclude(self: *@This(), lib: *std.Build.Step.Compile, paths: []const []const u8) void {
        const path = self.pathJoin(paths);
        self.debug("Including {s} into \"{s}\" library", .{ path, lib.name });
        lib.addIncludePath(self.ptrBuilder().path(path));
    }

    pub fn installHeaders(self: *@This(), lib: *std.Build.Step.Compile, source_paths: []const []const u8, dest: []const u8, exts: []const []const u8) void {
        const source_path = self.pathJoin(source_paths);
        self.debug("Installing {s} headers into {s} into {s} library", .{ source_path, dest, lib.name });
        lib.installHeadersDirectory(.{
            .cwd_relative = source_path,
        }, dest, .{
            .include_extensions = exts,
        });
    }

    pub fn run(self: *@This(), argv: []const []const u8, cwd: std.fs.Dir) ![]const u8 {
        std.debug.assert(argv.len != 0);
        self.debug("Running \"{s}\"", .{self.join(" ", argv)});

        if (!std.process.can_spawn) return error.ExecNotSupported;

        const max_output_size = 400 * 1024;
        var child = std.process.Child.init(argv, self.getAllocator());
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;
        child.cwd_dir = cwd;
        child.env_map = &self.ptrBuilder().graph.env_map;

        try std.Build.Step.handleVerbose2(self.ptrBuilder(), null, child.env_map, argv);
        try child.spawn();

        const stdout = child.stdout.?.deprecatedReader().readAllAlloc(self.getAllocator(), max_output_size) catch {
            return error.ReadFailure;
        };
        errdefer self.getAllocator().free(stdout);

        const term = try child.wait();
        switch (term) {
            .Exited => |code| {
                if (code != 0) {
                    std.log.err("System command failed. Exit code: \"{d}\"", .{@as(u8, @truncate(code))});
                    return error.ExitCodeFailure;
                }
                const trimmed = std.mem.trim(u8, stdout, &std.ascii.whitespace);
                if (trimmed.len > 0) self.debug("Output: \"{s}\"", .{trimmed});
                return trimmed;
            },
            .Signal, .Stopped, .Unknown => |code| {
                std.log.err("System command failed. Exit code: \"{d}\"", .{@as(u8, @truncate(code))});
                return error.ProcessTerminated;
            },
        }
    }

    pub fn addRunArtifact(self: *@This(), exe: *std.Build.Step.Compile) *std.Build.Step.Run {
        self.debug("Adding a run step from \"{s}\" executable", .{exe.name});
        return self.ptrBuilder().addRunArtifact(exe);
    }

    pub fn addWriteFiles(self: *@This()) *std.Build.Step.WriteFile {
        self.debug("Adding a write files step from", .{});
        return self.ptrBuilder().addWriteFiles();
    }

    pub fn addCopyFile(self: *@This(), write_file: *std.Build.Step.WriteFile, source: std.Build.LazyPath, paths: []const []const u8) std.Build.LazyPath {
        const path = self.pathJoin(paths);
        self.debug("Placing the {s} file into the generated directory within the local cache", .{path});
        return write_file.addCopyFile(source, path);
    }

    pub fn expectExitCode(self: @This(), r: *std.Build.Step.Run, code: u8) void {
        self.debug("Expecting {d} exit code from \"{s}\" run step", .{ code, r.step.name });
        r.expectExitCode(code);
    }

    pub fn captureStdOut(self: @This(), r: *std.Build.Step.Run) []const u8 {
        self.debug("Capturing stdout from \"{s}\" run step", .{r.step.name});
        return r.captureStdOut();
    }

    pub fn addArgs(self: @This(), r: *std.Build.Step.Run, args: []const []const u8) void {
        self.debug("Running \"{s}\" step with these arguments: \"{s}\"", .{ r.step.name, self.join("\" \"", args) });
        r.addArgs(args);
    }

    pub fn installArtifact(self: *@This(), compile: *std.Build.Step.Compile) void {
        self.debug("Installing \"{s}\" compile step", .{compile.name});
        self.ptrBuilder().installArtifact(compile);
    }

    pub fn dependOn(self: *@This(), step1: *std.Build.Step, step2: *std.Build.Step) void {
        self.debug("Making \"{s}\" step depends on \"{s}\" step", .{ step1.name, step2.name });
        step1.dependOn(step2);
    }

    // std.fs wrappers --------------------------------------------------------

    fn openDir(self: *@This(), paths: []const []const u8) !void {
        const path = self.pathJoin(paths);
        self.debug("Opening {s}{s}{s}", .{ self.getBuilder().dep_prefix, self.getPrefix(), path });
        self.ptrPrefix().* = if (path.len == 0) "/" else self.concat(&.{ "/", path, "/" });
        self.ptrDir().* = try self.ptrCwd().openDir(path, .{ .iterate = true });
    }

    pub fn remove(self: *@This(), paths: []const []const u8) !void {
        const path = self.pathJoin(paths);
        self.debug("Removing {s}{s}{s}", .{ self.getBuilder().dep_prefix, self.getPrefix(), path });
        self.ptrDir().deleteTree(path) catch |err|
            if (err != error.FileNotFound) return err;
    }

    pub fn make(self: *@This(), paths: []const []const u8) !void {
        const path = self.pathJoin(paths);
        self.debug("Making {s}{s}{s}", .{ self.getBuilder().dep_prefix, self.getPrefix(), path });
        self.ptrDir().makeDir(path) catch |err|
            if (err != error.PathAlreadyExists) return err;
    }

    pub fn copy(dest: *@This(), dest_paths: []const []const u8, source: *@This(), source_paths: []const []const u8) !void {
        const source_path = dest.pathJoin(source_paths);
        const dest_path = dest.pathJoin(dest_paths);
        dest.debug("Copying {s}{s}{s} into {s}{s}{s}", .{
            source.getBuilder().dep_prefix, source.getPrefix(), source_path,
            dest.getBuilder().dep_prefix,   dest.getPrefix(),   dest_path,
        });
        try source.ptrDir().copyFile(source_path, dest.ptrDir().*, dest_path, .{});
    }

    fn initWalker(self: *@This(), paths: []const []const u8) !void {
        self.debug("Allocating ressources for walker", .{});
        try self.openDir(paths);
        self.__walker = try self.ptrDir().walk(self.getAllocator());
    }

    fn deinitWalker(self: *@This()) void {
        self.debug("Freeing ressources for walker", .{});
        self.ptrDir().close();
        self.ptrDir().* = self.ptrCwd();
        self.ptrWalker().deinit();
    }

    pub fn walk(self: *@This(), paths: []const []const u8) !?std.fs.Dir.Walker.Entry {
        if (self.getWalker() == null) try self.initWalker(paths);

        const entry = try self.ptrWalker().next();
        if (entry) |e| {
            self.debug("Walking into {s}{s}{s} {s}", .{ self.getBuilder().dep_prefix, self.getPrefix(), e.path, @tagName(e.kind) });
        } else self.deinitWalker();
        return entry;
    }

    pub fn readFile(self: *@This(), paths: []const []const u8) ![]const u8 {
        const path = self.pathJoin(paths);
        self.debug("Reading {s}", .{path});
        return self.ptrCwd().readFileAlloc(self.getAllocator(), path, std.math.maxInt(usize));
    }

    pub fn writeFile(self: *@This(), paths: []const []const u8, content: []const u8) !void {
        const path = self.pathJoin(paths);
        self.debug("Writing into {s}", .{path});
        self.ptrCwd().writeFile(.{ .sub_path = path, .data = content });
    }
};

pub fn build(builder: *std.Build) !void {
    _ = builder.addModule("toolbox", .{
        .root_source_file = builder.addWriteFiles().add("empty.zig", ""),
    });
}
