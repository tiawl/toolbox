const std = @import("std");
const builtin = @import("builtin");

pub const ext = struct {
    pub const source = struct {
        pub const c = [_][]const u8{ ".c" };
        pub const cpp = struct {
            pub const pure = [_][]const u8{ ".cc", ".cpp", ".cxx" };
            pub const c_compatible = ext.source.c ++ ext.source.cpp.pure;
        };
    };

    pub const header = struct {
        pub const c = [_][]const u8{ ".h" };
        pub const cpp = struct {
            pub const pure = [_][]const u8{ ".hh", ".hpp", ".hxx" };
            pub const c_compatible = ext.header.c ++ ext.header.cpp.pure;
            pub const @"11" = struct {
                pub const pure = ext.header.cpp.pure ++ [_][]const u8{ ".hpp11" };
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
        var self: @This () = .{
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

    pub fn deinit(self: *@This()) void {
        _ = self;
    }

    pub fn build(self: *@This()) !void {
        try self.getBuildFn()(self);
    }

    pub fn update(self: *@This()) !void {
        if (self.needUpdate()) try self.getUpdateFn()(self);
    }

    // Getters ----------------------------------------------------------------

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

    fn initWalker(self: *@This(), paths: []const []const u8) !void {
        try self.openDir(paths);
        self.__walker = try self.ptrDir().walk(self.getAllocator());
    }

    fn deinitWalker(self: *@This()) void {
        self.ptrDir().close();
        self.ptrWalker().deinit();
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

    // Utilities --------------------------------------------------------------

    inline fn debug(self: @This(), comptime fmt: []const u8, args: anytype) void {
        if (self.isVerbose()) std.log.debug(fmt, args);
    }

    // std.Builder wrappers ---------------------------------------------------

    fn option(self: *@This(), comptime T: type, default: T, name: []const u8, description: []const u8) T {
        const opt = self.ptrBuilder().option(T, name, description) orelse default;
        self.debug("-D{s} option: {}", .{ name, opt });
        return opt;
    }

    pub fn dependency(self: *@This(), name: []const u8) *std.Build.Dependency {
        self.debug("Requesting \"{s}\" dependency", .{ name });
        return self.ptrBuilder().dependency(name, .{
            .optimize = self.getOptimize(),
            .target = self.getTarget(),
        });
    }

    pub fn addLibrary(self: *@This(), name: []const u8) *std.Build.Step.Compile {
        self.debug("Creating \"{s}\" library", .{ name });
        return self.ptrBuilder().addLibrary(.{
            .name = name,
            .root_module = std.Build.Module.create(self.ptrBuilder(), .{
                .root_source_file = self.ptrBuilder().addWriteFiles().add("empty.zig", ""),
                .target = self.getTarget(),
                .optimize = self.getOptimize(),
            }),
        });
    }

    pub fn installHeaders(self: *@This(), lib: *std.Build.Step.Compile, source_paths: []const []const u8, dest: []const u8, exts: []const []const u8) void {
        const source_path = self.ptrBuilder().pathJoin(source_paths);
        self.debug("Installing {s} headers into {s}", .{ source_path, dest });
        lib.installHeadersDirectory(.{
            .cwd_relative = source_path,
        }, dest, .{
            .include_extensions = exts,
        });
    }

    pub fn installArtifact(self: *@This(), artifact: *std.Build.Step.Compile) void {
        self.debug("Installing \"{s}\" artifact", .{ artifact.name });
        self.ptrBuilder().installArtifact(artifact);
    }

    // std.fs wrappers --------------------------------------------------------

    fn openDir(self: *@This(), paths: []const []const u8) !void {
        const path = self.ptrBuilder().pathJoin(paths);
        self.debug("Opening {s}{s}{s}", .{ self.getBuilder().dep_prefix, self.getPrefix(), path });
        self.ptrPrefix().* = if (path.len == 0) "/"
            else try std.mem.concat(self.getAllocator(), u8, &.{ "/", path, "/" });
        self.ptrDir().* = try self.ptrDir().openDir(path, .{ .iterate = true });
    }

    pub fn remove(self: *@This(), paths: []const []const u8) !void {
        const path = self.ptrBuilder().pathJoin(paths);
        self.debug("Removing {s}{s}{s}", .{ self.getBuilder().dep_prefix, self.getPrefix(), path });
        self.ptrDir().deleteTree(path) catch |err|
            if (err != error.FileNotFound) return err;
    }

    pub fn make(self: *@This(), paths: []const []const u8) !void {
        const path = self.ptrBuilder().pathJoin(paths);
        self.debug("Making {s}{s}{s}", .{ self.getBuilder().dep_prefix, self.getPrefix(), path });
        self.ptrDir().makeDir(path) catch |err|
            if (err != error.PathAlreadyExists) return err;
    }

    pub fn copy(dest: *@This(), dest_paths: []const []const u8, source: *@This(), source_paths: []const []const u8) !void {
        const source_path = dest.ptrBuilder().pathJoin(source_paths);
        const dest_path = dest.ptrBuilder().pathJoin(dest_paths);
        dest.debug("Copying {s}{s}{s} into {s}{s}{s}", .{
            source.getBuilder().dep_prefix, source.getPrefix(), source_path,
            dest.getBuilder().dep_prefix, dest.getPrefix(), dest_path,
        });
        try source.ptrDir().copyFile(source_path, dest.ptrDir().*, dest_path, .{});
    }

    pub fn walk(self: *@This(), paths: []const []const u8) !?std.fs.Dir.Walker.Entry {
        if (self.getWalker() == null) {
            self.debug("Allocating ressources for walker", .{});
            try self.initWalker(paths);
        }

        const entry = try self.ptrWalker().next();
        if (entry) |e| {
            self.debug("Walking into {s}{s}{s} {s}", .{ self.getBuilder().dep_prefix, self.getPrefix(), e.path, @tagName(e.kind) });
        } else {
            self.debug("Freeing ressources for walker", .{});
            self.deinitWalker();
        }
        return entry;
    }
};

// TODO: manage -Dfetch option

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
