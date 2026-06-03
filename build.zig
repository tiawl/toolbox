const std = @import("std");
const builtin = @import("builtin");

pub const ext = struct {
    pub const c = struct {
        pub const source = [_][]const u8{".c"};
        pub const header = [_][]const u8{".h"};
        pub const file = ext.c.source ++ ext.c.header;
        pub const template = [_][]const u8{".h.in"};
    };

    pub const cpp = struct {
        pub const source = struct {
            pub const strict = [_][]const u8{ ".cc", ".cpp", ".cxx" };
            pub const c_compatible = ext.c.source ++ ext.cpp.source.strict;
        };
        pub const header = struct {
            pub const strict = [_][]const u8{ ".hh", ".hpp", ".hxx" };
            pub const c_compatible = ext.c.header ++ ext.cpp.header.strict;
            pub const @"11" = struct {
                pub const strict = ext.cpp.header.strict ++ [_][]const u8{".hpp11"};
                pub const c_compatible = ext.c.header ++ ext.cpp.header.@"11".strict;
            };
        };

        pub const file = struct {
            pub const strict = ext.cpp.source.strict ++ ext.cpp.header.strict;
            pub const c_compatible = ext.cpp.source.c_compatible ++ ext.cpp.header.c_compatible;
            pub const @"11" = struct {
                pub const strict = ext.cpp.source.strict ++ ext.cpp.header.@"11".strict;
                pub const c_compatible = ext.cpp.source.c_compatible ++ ext.cpp.header.@"11".c_compatible;
            };
        };
    };

    pub const obj = struct {
        pub const c = struct {
            pub const source = [_][]const u8{".m"};
            pub const header = ext.c.header;
            pub const file = ext.obj.c.source ++ ext.obj.c.header;
        };
        pub const cpp = [_][]const u8{".mm"};
    };

    pub const xml = struct {
        pub const file = [_][]const u8{".xml"};
    };

    pub const include = struct {
        pub const file = [_][]const u8{".inc"};
    };
};

inline fn checkExt(name: []const u8, exts: []const []const u8) bool {
    var res = false;
    inline for (exts) |e| res = (res or std.mem.endsWith(u8, name, e));
    return res;
}

pub inline fn isXmlFile(name: []const u8) bool {
    return checkExt(name, &ext.xml.file);
}

pub inline fn isIncludeFile(name: []const u8) bool {
    return checkExt(name, &ext.include.file);
}

pub inline fn isCFile(name: []const u8) bool {
    return checkExt(name, &ext.c.file);
}

pub inline fn isCOrCppFile(name: []const u8) bool {
    return checkExt(name, &ext.cpp.file.c_compatible);
}

pub inline fn isCOrCpp11File(name: []const u8) bool {
    return checkExt(name, &ext.cpp.file.@"11".c_compatible);
}

pub inline fn isCSource(name: []const u8) bool {
    return checkExt(name, &ext.c.source);
}

pub inline fn isObjCSource(name: []const u8) bool {
    return checkExt(name, &ext.obj.c.source);
}

pub inline fn isCppSource(name: []const u8) bool {
    return checkExt(name, &ext.cpp.source.strict);
}

pub inline fn isObjCppSource(name: []const u8) bool {
    return checkExt(name, &ext.obj.cpp.source);
}

pub inline fn isCOrCppSource(name: []const u8) bool {
    return checkExt(name, &ext.cpp.source.c_compatible);
}

pub inline fn isCHeader(name: []const u8) bool {
    return checkExt(name, &ext.c.header);
}

pub inline fn isCppHeader(name: []const u8) bool {
    return checkExt(name, &ext.cpp.header.strict);
}

pub inline fn isCOrCppHeader(name: []const u8) bool {
    return checkExt(name, &ext.cpp.header.c_compatible);
}

pub inline fn isCOrCpp11Header(name: []const u8) bool {
    return checkExt(name, &ext.cpp.header.@"11".c_compatible);
}

pub inline fn isCTemplate(name: []const u8) bool {
    return checkExt(name, &ext.c.template);
}

pub const VerboseBuilder = struct {
    const BuildOptions = struct {
        __fetch: bool = false,
        __update: bool = false,
        __verbose: bool = false,

        inline fn isVerbose(self: @This()) bool {
            return self.__verbose;
        }

        inline fn needUpdate(self: @This()) bool {
            return self.__update;
        }

        inline fn needFetch(self: @This()) bool {
            return self.__fetch;
        }

        inline fn debug(self: @This(), comptime f: []const u8, args: anytype) void {
            if (self.isVerbose()) std.log.debug(f, args);
        }

        inline fn info(self: @This(), comptime f: []const u8, args: anytype) void {
            if (self.isVerbose()) std.log.info(f, args);
        }

        inline fn err(self: @This(), comptime f: []const u8, args: anytype) void {
            if (self.isVerbose()) std.log.err(f, args);
        }
    };

    var optimize: std.builtin.OptimizeMode = undefined;
    var target: std.Build.ResolvedTarget = undefined;
    var options: BuildOptions = .{};

    __builder: *std.Build,
    __walker: ?std.Io.Dir.Walker,
    __iterator: ?std.Io.Dir.Iterator,
    __dir: std.Io.Dir,
    __prefix: []const u8,
    __build_fn: ?*const fn (*@This()) anyerror!void,
    __update_fn: ?*const fn (*@This()) anyerror!void,

    pub fn init(builder: *std.Build, comptime name: []const u8, build_fn: ?*const fn (*@This()) anyerror!void, update_fn: ?*const fn (*@This()) anyerror!void) !@This() {
        builder.dep_prefix = name ++ ".";
        var self: @This() = .{
            .__builder = builder,
            .__walker = null,
            .__iterator = null,
            // TODO: remove build_root for 0.17.0 release
            .__dir = if (@hasField(std.Build, "build_root")) builder.build_root.handle else if (@hasField(std.Build, "root")) builder.root.root_dir.handle else unreachable,
            .__prefix = "/",
            .__build_fn = build_fn,
            .__update_fn = update_fn,
        };

        optimize = builder.standardOptimizeOption(.{});
        target = builder.standardTargetOptions(.{});
        options.__verbose = self.option(bool, false, "verbose", "Enabled toolbox debug logging");
        options.__fetch = self.option(bool, false, "fetch", "Update build.zig.zon then stop execution");
        options.__update = self.option(bool, false, "update", "Update binding");

        return self;
    }

    pub fn initFromDependency(dep: *std.Build.Dependency) @This() {
        dep.builder.dep_prefix = dep.builder.dep_prefix[std.mem.indexOfScalar(u8, dep.builder.dep_prefix, '.').? + 1 ..];
        const other: @This() = .{
            .__builder = dep.builder,
            .__walker = null,
            .__iterator = null,
            // TODO: remove build_root for 0.17.0 release
            .__dir = if (@hasField(std.Build, "build_root")) dep.builder.build_root.handle else if (@hasField(std.Build, "root")) dep.builder.root.root_dir.handle else unreachable,
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
        if (options.needUpdate()) try self.getUpdateFn()(self);
    }

    pub fn fetch(self: *@This(), comptime T: type, comptime dependencies: T, dir: *std.Io.Dir) !void {
        if (!options.needFetch()) return;
        const io = self.getIo();
        inline for (comptime std.meta.fieldNames(T)) |field_name| {
            if (!@hasField(@TypeOf(@field(dependencies, field_name)), "url")) continue;
            const uri = try std.Uri.parse(@field(dependencies, field_name).url);
            const host = (uri.getHostAlloc(self.getAllocator()) catch @panic("OOM")).bytes;
            const path = self.uriComponent(&uri.path);
            self.ptrCwd().createDirPath(io, self.resolve(&.{ ".zig-cache", "tmp" })) catch |e|
                if (e != error.PathAlreadyExists) return e;
            var random_bytes: [12]u8 = undefined;
            io.random(&random_bytes);
            var sub_path: [std.base64.url_safe.Encoder.calcSize(12)]u8 = undefined;
            _ = std.base64.url_safe.Encoder.encode(&sub_path, &random_bytes);
            const tmp_path = self.resolve(&.{ ".zig-cache", "tmp", &sub_path });
            defer self.ptrCwd().deleteTree(io, tmp_path) catch {};
            if (@hasField(@TypeOf(@field(dependencies, field_name)), "branch")) {
                _ = try self.run(&.{ "git", "clone", "--bare", "--branch", @field(dependencies, field_name).branch, "--filter=blob:none", "--", self.fmt("https://{s}{s}", .{ host, path }), tmp_path }, self.ptrCwd().*);
            } else {
                _ = try self.run(&.{ "git", "clone", "--bare", "--filter=blob:none", "--", self.fmt("https://{s}{s}", .{ host, path }), tmp_path }, self.ptrCwd().*);
            }
            const tmp_dir = self.ptrCwd().openDir(io, tmp_path, .{}) catch return error.ExitCodeFailure;
            var latest: []const u8 = undefined;
            if (uri.query) |_| {
                const commits = try std.fmt.parseUnsigned(usize, try self.run(&.{ "git", "rev-list", "--count", "--all" }, tmp_dir), 10);
                for (0..commits) |i| {
                    latest = self.run(&.{ "git", "describe", "--tags", "--exact-match", self.fmt("HEAD~{}", .{i}) }, tmp_dir) catch |err| switch (err) {
                        error.ExitCodeFailure => continue,
                        else => return err,
                    };
                    if (std.mem.indexOfAny(u8, latest, "0123456789.") == null) continue;
                    break;
                } else return error.NoValidTag;
            } else {
                latest = try self.run(&.{ "git", "rev-parse", "HEAD" }, tmp_dir);
            }
            _ = try self.run(&.{ "zig", "fetch", "--save=" ++ field_name, self.fmt("git+https://{s}{s}#{s}", .{ host, path, latest }) }, dir.*);
        }
    }

    // inlined ----------------------------------------------------------------

    inline fn getBuilder(self: @This()) *const std.Build {
        return self.__builder;
    }

    pub inline fn ptrBuilder(self: @This()) *std.Build {
        return self.__builder;
    }

    inline fn getAllocator(self: @This()) std.mem.Allocator {
        return self.getBuilder().allocator;
    }

    inline fn ptrRoot(self: *@This()) *std.Build.Cache.Directory {
        // TODO: remove build_root for 0.17.0 release
        return if (@hasField(std.Build, "build_root")) &self.ptrBuilder().build_root else if (@hasField(std.Build, "root")) &self.ptrBuilder().root.root_dir else unreachable;
    }

    pub inline fn getInstallStep(self: *@This()) *std.Build.Step {
        return self.ptrBuilder().getInstallStep();
    }

    pub inline fn ptrCwd(self: *@This()) *std.Io.Dir {
        return &self.ptrRoot().handle;
    }

    inline fn ptrDir(self: *@This()) *std.Io.Dir {
        return &self.__dir;
    }

    inline fn getPrefix(self: @This()) []const u8 {
        return self.__prefix;
    }

    inline fn ptrPrefix(self: *@This()) *[]const u8 {
        return &self.__prefix;
    }

    inline fn getWalker(self: @This()) ?std.Io.Dir.Walker {
        return self.__walker;
    }

    inline fn ptrWalker(self: *@This()) *std.Io.Dir.Walker {
        return &self.__walker.?;
    }

    inline fn getIterator(self: @This()) ?std.Io.Dir.Iterator {
        return self.__iterator;
    }

    inline fn ptrIterator(self: *@This()) *std.Io.Dir.Iterator {
        return &self.__iterator.?;
    }

    inline fn getBuildFn(self: @This()) *const fn (*@This()) anyerror!void {
        return self.__build_fn.?;
    }

    inline fn getUpdateFn(self: @This()) *const fn (*@This()) anyerror!void {
        return self.__update_fn.?;
    }

    inline fn ptrGraph(self: *@This()) *std.Build.Graph {
        return self.ptrBuilder().graph;
    }

    inline fn ptrEnvMap(self: *@This()) *std.process.Environ.Map {
        return &self.ptrGraph().environ_map;
    }

    pub inline fn getIo(self: *@This()) std.Io {
        return self.ptrGraph().io;
    }

    pub inline fn putEnvVar(self: *@This(), key: []const u8, value: []const u8) !void {
        try self.ptrEnvMap().put(key, value);
    }

    pub inline fn getOs(_: *@This()) std.Target.Os.Tag {
        return target.result.os.tag;
    }

    // TODO: remove this for 0.17.0 release
    pub inline fn getArgs(self: @This()) []const []const u8 {
        return if (@hasField(std.Build, "args")) self.getBuilder().args orelse &.{} else unreachable;
    }

    // std.mem wrappers -------------------------------------------------------

    pub inline fn relative(self: *@This(), from: []const u8, to: []const u8) []const u8 {
        return std.fs.path.relative(self.getAllocator(), ".", null, from, to) catch @panic("OOM");
    }

    pub inline fn resolve(self: *@This(), paths: []const []const u8) []const u8 {
        return self.ptrBuilder().pathResolve(paths);
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

    pub inline fn uriComponent(self: @This(), component: *const std.Uri.Component) []const u8 {
        return component.toRawMaybeAlloc(self.getAllocator()) catch @panic("OOM");
    }

    // std.Build wrappers -----------------------------------------------------

    pub fn option(self: *@This(), comptime T: type, default: T, name: []const u8, description: []const u8) T {
        const opt = self.ptrBuilder().option(T, name, description) orelse default;
        switch (@typeInfo(T)) {
            .pointer => |ptr| {
                if (ptr.child == u8) {
                    options.debug("-D{s} option: {s}", .{ name, opt });
                    return opt;
                } else {
                    options.debug("-D{s} option: {any}", .{ name, opt });
                    return opt;
                }
            },
            else => {
                options.debug("-D{s} option: {}", .{ name, opt });
                return opt;
            },
        }
    }

    pub fn step(self: *@This(), name: []const u8, description: []const u8) *std.Build.Step {
        options.debug("Creating \"{s}\" step described \"{s}\"", .{ name, description });
        return self.ptrBuilder().step(name, description);
    }

    pub fn dependency(self: *@This(), name: []const u8) *std.Build.Dependency {
        options.debug("Requesting \"{s}\" dependency", .{name});
        return self.ptrBuilder().dependency(name, .{
            .optimize = optimize,
            .target = target,
        });
    }

    pub fn verboseDependency(self: *@This(), name: []const u8) *std.Build.Dependency {
        options.debug("Requesting \"{s}\" dependency", .{name});
        return self.ptrBuilder().dependency(name, .{
            .optimize = optimize,
            .target = target,
            .verbose = options.isVerbose(),
        });
    }

    pub fn artifact(self: *@This(), dep: *std.Build.Dependency, name: []const u8) *std.Build.Step.Compile {
        const compile = dep.artifact(name);
        options.debug("Requesting \"{s}\" {s} from \"{s}\" dependency", .{ name, self.kind(compile), dep.builder.dep_prefix[0 .. dep.builder.dep_prefix.len - 1] });
        return compile;
    }

    pub fn addExecutable(self: *@This(), name: []const u8) *std.Build.Step.Compile {
        options.debug("Creating \"{s}\" executable", .{name});
        return self.ptrBuilder().addExecutable(.{
            .name = name,
            .root_module = std.Build.Module.create(self.ptrBuilder(), .{
                .optimize = optimize,
                .target = target,
            }),
        });
    }

    pub fn addLibrary(self: *@This(), name: []const u8) *std.Build.Step.Compile {
        options.debug("Creating \"{s}\" static library", .{name});
        return self.ptrBuilder().addLibrary(.{
            .name = name,
            .linkage = .static,
            .root_module = std.Build.Module.create(self.ptrBuilder(), .{
                .root_source_file = self.ptrBuilder().addWriteFiles().add("empty.zig", ""),
                .optimize = optimize,
                .target = target,
            }),
        });
    }

    pub fn kind(self: *@This(), compile: *std.Build.Step.Compile) []const u8 {
        return switch (compile.kind) {
            .lib => self.fmt("{s} library", .{std.enums.tagName(std.builtin.LinkMode, compile.linkage.?).?}),
            .exe => "executable",
            else => @tagName(compile.kind),
        };
    }

    pub fn unsanitizeC(self: *@This(), compile: *std.Build.Step.Compile) void {
        options.debug("Unsanitizing C to \"{s}\" {s}", .{ compile.name, self.kind(compile) });
        compile.root_module.sanitize_c = .off;
    }

    pub fn linkLibC(self: *@This(), compile: *std.Build.Step.Compile) void {
        options.debug("Linking LibC to \"{s}\" {s}", .{ compile.name, self.kind(compile) });
        compile.root_module.link_libc = true;
    }

    pub fn linkLibCpp(self: *@This(), compile: *std.Build.Step.Compile) void {
        options.debug("Linking LibCpp to \"{s}\" {s}", .{ compile.name, self.kind(compile) });
        compile.root_module.link_libcpp = true;
    }

    pub fn linkLibrary(self: *@This(), compile1: *std.Build.Step.Compile, compile2: *std.Build.Step.Compile) void {
        options.debug("Linking \"{s}\" {s} to \"{s}\" {s}", .{ compile2.name, self.kind(compile2), compile1.name, self.kind(compile1) });
        compile1.root_module.linkLibrary(compile2);
    }

    pub fn linkSystemLibrary(self: *@This(), compile: *std.Build.Step.Compile, name: []const u8) void {
        options.debug("Linking \"{s}\" system library to \"{s}\" {s}", .{ name, compile.name, self.kind(compile) });
        compile.root_module.linkSystemLibrary(name, .{});
    }

    pub fn linkFramework(self: *@This(), compile: *std.Build.Step.Compile, name: []const u8) void {
        options.debug("Linking \"{s}\" framework to \"{s}\" {s}", .{ name, compile.name, self.kind(compile) });
        compile.root_module.linkFramework(name, .{});
    }

    pub fn addCSource(self: *@This(), compile: *std.Build.Step.Compile, paths: []const []const u8, flags: []const []const u8) void {
        const path = self.resolve(paths);
        const joined_flags = self.join("\", \"", flags);
        options.debug("Adding C Source {s} to \"{s}\" {s} with these flags: \"{s}\"", .{ path, compile.name, self.kind(compile), joined_flags });
        compile.root_module.addCSourceFile(.{ .file = self.ptrBuilder().path(path), .flags = flags });
    }

    pub fn addCMacro(_: *@This(), compile: *std.Build.Step.Compile, key: []const u8, value: []const u8) void {
        options.debug("Adding C macro: {s} {s}", .{ key, value });
        compile.root_module.addCMacro(key, value);
    }

    pub fn addImport(self: *@This(), compile: *std.Build.Step.Compile, name: []const u8, module: *std.Build.Module) void {
        options.debug("Adding {s} module to be used with @import into \"{s}\" {s}", .{ name, compile.name, self.kind(compile) });
        compile.root_module.addImport(name, module);
    }

    fn addIncludePathIntoModule(_: *@This(), module: *std.Build.Module, path: std.Build.LazyPath) void {
        if (@hasField(std.Build.LazyPath, "relative")) {
            switch (path) {
                inline .generated, .dependency, .relative => |*lazy| options.debug("Including {s} into module", .{lazy.sub_path}),
                .src_path => |*lazy| options.debug("Including {s}{s} into module", .{ lazy.owner.dep_prefix, lazy.sub_path }),
                .cwd_relative => |lazy| options.debug("Including {s} into module", .{lazy}),
            }
            // TODO: remove this for 0.17.0 release
        } else {
            switch (path) {
                inline .generated, .dependency => |*lazy| options.debug("Including {s} into module", .{lazy.sub_path}),
                .src_path => |*lazy| options.debug("Including {s}{s} into module", .{ lazy.owner.dep_prefix, lazy.sub_path }),
                .cwd_relative => |lazy| options.debug("Including {s} into module", .{lazy}),
            }
        }
        module.addIncludePath(path);
    }

    fn addIncludePathIntoCompile(self: *@This(), compile: *std.Build.Step.Compile, path: std.Build.LazyPath) void {
        if (@hasField(std.Build.LazyPath, "relative")) {
            switch (path) {
                inline .generated, .dependency, .relative => |*lazy| options.debug("Including {s} into \"{s}\" {s}", .{ lazy.sub_path, compile.name, self.kind(compile) }),
                .src_path => |*lazy| options.debug("Including {s}{s} into \"{s}\" {s}", .{ lazy.owner.dep_prefix, lazy.sub_path, compile.name, self.kind(compile) }),
                .cwd_relative => |lazy| options.debug("Including {s} into \"{s}\" {s}", .{ lazy, compile.name, self.kind(compile) }),
            }
            // TODO: remove this for 0.17.0 release
        } else {
            switch (path) {
                inline .generated, .dependency => |*lazy| options.debug("Including {s} into \"{s}\" {s}", .{ lazy.sub_path, compile.name, self.kind(compile) }),
                .src_path => |*lazy| options.debug("Including {s}{s} into \"{s}\" {s}", .{ lazy.owner.dep_prefix, lazy.sub_path, compile.name, self.kind(compile) }),
                .cwd_relative => |lazy| options.debug("Including {s} into \"{s}\" {s}", .{ lazy, compile.name, self.kind(compile) }),
            }
        }
        self.addIncludePathIntoModule(compile.root_module, path);
    }

    fn addIncludePathIntoTranslateC(_: *@This(), translate_c: *std.Build.Step.TranslateC, path: std.Build.LazyPath) void {
        if (@hasField(std.Build.LazyPath, "relative")) {
            switch (path) {
                inline .generated, .dependency, .relative => |*lazy| options.debug("Including {s} into \"{s}\" translate-c", .{ lazy.sub_path, translate_c.step.name }),
                .src_path => |*lazy| options.debug("Including {s}{s} into \"{s}\" translate-c", .{ lazy.owner.dep_prefix, lazy.sub_path, translate_c.step.name }),
                .cwd_relative => |lazy| options.debug("Including {s} into \"{s}\" translate-c", .{ lazy, translate_c.step.name }),
            }
            // TODO: remove this for 0.17.0 release
        } else {
            switch (path) {
                inline .generated, .dependency => |*lazy| options.debug("Including {s} into \"{s}\" translate-c", .{ lazy.sub_path, translate_c.step.name }),
                .src_path => |*lazy| options.debug("Including {s}{s} into \"{s}\" translate-c", .{ lazy.owner.dep_prefix, lazy.sub_path, translate_c.step.name }),
                .cwd_relative => |lazy| options.debug("Including {s} into \"{s}\" translate-c", .{ lazy, translate_c.step.name }),
            }
        }
        translate_c.addIncludePath(path);
    }

    pub fn addIncludePath(self: *@This(), comptime T: type, t: *T, path: std.Build.LazyPath) void {
        if (T == std.Build.Step.Compile) self.addIncludePathIntoCompile(t, path) else if (T == std.Build.Module) self.addIncludePathIntoModule(t, path) else if (T == std.Build.Step.TranslateC) self.addIncludePathIntoTranslateC(t, path) else unreachable;
    }

    pub fn addInclude(self: *@This(), compile: *std.Build.Step.Compile, paths: []const []const u8) void {
        const path = self.resolve(paths);
        options.debug("Including {s} into \"{s}\" {s}", .{ path, compile.name, self.kind(compile) });
        self.addIncludePath(@TypeOf(compile.*), compile, self.ptrBuilder().path(path));
    }

    pub fn addIncludePathsFromLib(self: *@This(), comptime T: type, t: *T, compile: *std.Build.Step.Compile) void {
        std.debug.assert(compile.kind == .lib);
        for (compile.root_module.include_dirs.items) |*included| {
            switch (included.*) {
                .path => self.addIncludePath(T, t, included.path),
                .config_header_step => self.addConfigHeader(T, t, included.config_header_step),
                .path_system => self.addSystemIncludePath(T, t, included.path_system),
                .other_step => self.addIncludePathsFromLib(T, t, included.other_step),
                else => unreachable,
            }
        }
    }

    fn addSystemIncludePathIntoModule(_: *@This(), module: *std.Build.Module, path: std.Build.LazyPath) void {
        if (@hasField(std.Build.LazyPath, "relative")) {
            switch (path) {
                inline .generated, .dependency, .relative => |*lazy| options.debug("Including {s} into module", .{lazy.sub_path}),
                .src_path => |*lazy| options.debug("Including {s}{s} into module", .{ lazy.owner.dep_prefix, lazy.sub_path }),
                .cwd_relative => |lazy| options.debug("Including {s} into module", .{lazy}),
            }
            // TODO: remove this for 0.17.0 release
        } else {
            switch (path) {
                inline .generated, .dependency => |*lazy| options.debug("Including {s} into module", .{lazy.sub_path}),
                .src_path => |*lazy| options.debug("Including {s}{s} into module", .{ lazy.owner.dep_prefix, lazy.sub_path }),
                .cwd_relative => |lazy| options.debug("Including {s} into module", .{lazy}),
            }
        }
        module.addSystemIncludePath(path);
    }

    fn addSystemIncludePathIntoCompile(self: *@This(), compile: *std.Build.Step.Compile, path: std.Build.LazyPath) void {
        if (@hasField(std.Build.LazyPath, "relative")) {
            switch (path) {
                inline .generated, .dependency, .relative => |*lazy| options.debug("Including system {s} into \"{s}\" {s}", .{ lazy.sub_path, compile.name, self.kind(compile) }),
                .src_path => |*lazy| options.debug("Including system {s}{s} into \"{s}\" {s}", .{ lazy.owner.dep_prefix, lazy.sub_path, compile.name, self.kind(compile) }),
                .cwd_relative => |lazy| options.debug("Including system {s} into \"{s}\" {s}", .{ lazy, compile.name, self.kind(compile) }),
            }
            // TODO: remove this for 0.17.0 release
        } else {
            switch (path) {
                inline .generated, .dependency => |*lazy| options.debug("Including system {s} into \"{s}\" {s}", .{ lazy.sub_path, compile.name, self.kind(compile) }),
                .src_path => |*lazy| options.debug("Including system {s}{s} into \"{s}\" {s}", .{ lazy.owner.dep_prefix, lazy.sub_path, compile.name, self.kind(compile) }),
                .cwd_relative => |lazy| options.debug("Including system {s} into \"{s}\" {s}", .{ lazy, compile.name, self.kind(compile) }),
            }
        }
        self.addSystemIncludePathIntoModule(compile.root_module, path);
    }

    fn addSystemIncludePathIntoTranslateC(_: *@This(), translate_c: *std.Build.Step.TranslateC, path: std.Build.LazyPath) void {
        if (@hasField(std.Build.LazyPath, "relative")) {
            switch (path) {
                inline .generated, .dependency, .relative => |*lazy| options.debug("Including system {s} into \"{s}\" translate-c", .{ lazy.sub_path, translate_c.step.name }),
                .src_path => |*lazy| options.debug("Including system {s}{s} into \"{s}\" translate-c", .{ lazy.owner.dep_prefix, lazy.sub_path, translate_c.step.name }),
                .cwd_relative => |lazy| options.debug("Including system {s} into \"{s}\" translate-c", .{ lazy, translate_c.step.name }),
            }
            // TODO: remove this for 0.17.0 release
        } else {
            switch (path) {
                inline .generated, .dependency => |*lazy| options.debug("Including system {s} into \"{s}\" translate-c", .{ lazy.sub_path, translate_c.step.name }),
                .src_path => |*lazy| options.debug("Including system {s}{s} into \"{s}\" translate-c", .{ lazy.owner.dep_prefix, lazy.sub_path, translate_c.step.name }),
                .cwd_relative => |lazy| options.debug("Including system {s} into \"{s}\" translate-c", .{ lazy, translate_c.step.name }),
            }
        }
        translate_c.addSystemIncludePath(path);
    }

    pub fn addSystemIncludePath(self: *@This(), comptime T: type, t: *T, path: std.Build.LazyPath) void {
        if (T == std.Build.Step.Compile) self.addSystemIncludePathIntoCompile(t, path) else if (T == std.Build.Module) self.addSystemIncludePathIntoModule(t, path) else if (T == std.Build.Step.TranslateC) self.addSystemIncludePathIntoTranslateC(t, path) else unreachable;
    }

    fn addConfigHeaderIntoModule(_: *@This(), module: *std.Build.Module, config_header: *std.Build.Step.ConfigHeader) void {
        options.debug("Adding {s} C header file into module", .{config_header.getOutputFile().generated.sub_path});
        module.addConfigHeader(config_header);
    }

    fn addConfigHeaderIntoCompile(self: *@This(), compile: *std.Build.Step.Compile, config_header: *std.Build.Step.ConfigHeader) void {
        options.debug("Adding {s} C header file into \"{s}\" {s}", .{ config_header.getOutputFile().generated.sub_path, compile.name, self.kind(compile) });
        self.addConfigHeaderIntoModule(compile.root_module, config_header);
    }

    fn addConfigHeaderIntoTranslateC(_: *@This(), translate_c: *std.Build.Step.TranslateC, config_header: *std.Build.Step.ConfigHeader) void {
        options.debug("Adding {s} C header file into \"{s}\" translate-c", .{ config_header.getOutputFile().generated.sub_path, translate_c.step.name });
        translate_c.addConfigHeader(config_header);
    }

    pub fn addConfigHeader(self: *@This(), comptime T: type, t: *T, config_header: *std.Build.Step.ConfigHeader) void {
        if (T == std.Build.Step.Compile) self.addConfigHeaderIntoCompile(t, config_header) else if (T == std.Build.Module) self.addConfigHeaderIntoModule(t, config_header) else if (T == std.Build.Step.TranslateC) self.addConfigHeaderIntoTranslateC(t, config_header) else unreachable;
    }

    pub fn generateConfigHeader(self: *@This(), compile: *std.Build.Step.Compile, paths: []const []const u8, includes: []const []const u8, style: std.meta.Tag(std.Build.Step.ConfigHeader.Style), macros: anytype) void {
        std.debug.assert(std.meta.activeTag(@typeInfo(@TypeOf(macros))) == .@"struct");
        var include = self.resolve(includes);
        include = include[0 .. std.mem.lastIndexOfScalar(u8, include, '.') orelse include.len];
        const path = self.fmt("{s}/{s}.in", .{ self.resolve(paths), include });
        options.debug("Adding a C header file from {s} {s} template input file into \"{s}\" {s}", .{ path, @tagName(style), compile.name, self.kind(compile) });
        inline for (comptime std.meta.fieldNames(@TypeOf(macros))) |field_name| {
            switch (@typeInfo(@TypeOf(@field(macros, field_name)))) {
                .pointer => |ptr| if (ptr.child == u8) options.debug("Defining {s} {s} into {s}", .{ field_name, @field(macros, field_name), include }),
                else => options.debug("Defining {s} {} into {s}", .{ field_name, @field(macros, field_name), include }),
            }
        }
        const config_header = self.ptrBuilder().addConfigHeader(.{ .style = switch (style) {
            .autoconf_undef => .{ .autoconf_undef = self.ptrBuilder().path(path) },
            .autoconf_at => .{ .autoconf_at = self.ptrBuilder().path(path) },
            else => unreachable,
        }, .include_path = include }, macros);
        self.addConfigHeaderIntoCompile(compile, config_header);
    }

    pub fn installLibraryHeaders(self: *@This(), compile1: *std.Build.Step.Compile, compile2: *std.Build.Step.Compile) void {
        options.debug("Forwarding headers marked for installation from \"{s}\" {s} to \"{s}\" {s}", .{ compile2.name, self.kind(compile2), compile1.name, self.kind(compile1) });
        compile1.installLibraryHeaders(compile2);
    }

    pub fn installHeader(self: *@This(), compile: *std.Build.Step.Compile, source_paths: []const []const u8, dest_paths: []const []const u8) void {
        const source_path = self.resolve(source_paths);
        const dest_path = self.resolve(dest_paths);
        options.debug("Installing {s} into {s} into \"{s}\" {s}", .{ source_path, dest_path, compile.name, self.kind(compile) });
        compile.installHeader(self.ptrBuilder().path(source_path), dest_path);
    }

    pub fn run(self: *@This(), argv: []const []const u8, cwd: std.Io.Dir) ![]const u8 {
        options.debug("Running \"{s}\"", .{self.join(" ", argv)});
        if (@hasDecl(std.Build, "runFallible")) {
            return switch (self.ptrBuilder().runFallible(argv, .{ .cwd = .{ .dir = cwd } })) {
                .success => |stdout| {
                    const trimmed = std.mem.trim(u8, stdout, &std.ascii.whitespace);
                    var it = std.mem.tokenizeScalar(u8, trimmed, '\n');
                    while (it.next()) |line| options.info("   {s}", .{line});
                    return trimmed;
                },
                .spawn_failed => |err| return err,
                .bad_exit_code => return error.ExitCodeFailure,
                .crashed => return error.ProcessTerminated,
            };
        } else {
            std.debug.assert(argv.len != 0);

            if (!std.process.can_spawn) return error.ExecNotSupported;

            const io = self.getIo();
            if (@hasDecl(std.Build.Step, "handleVerbose2")) try std.Build.Step.handleVerbose2(self.ptrBuilder(), .{ .dir = cwd }, &self.ptrGraph().environ_map, argv);

            const result = std.process.run(self.getAllocator(), io, .{
                .argv = argv,
                .cwd = .{ .dir = cwd },
                .environ_map = &self.ptrGraph().environ_map,
            }) catch |e| {
                options.err("System command failed to run: {}", .{e});
                return error.ExitCodeFailure;
            };
            defer self.getAllocator().free(result.stderr);

            switch (result.term) {
                .exited => |code| {
                    if (code != 0) {
                        options.err("System command failed. Exit code: \"{d}\"", .{code});
                        var it = std.mem.tokenizeScalar(u8, result.stderr, '\n');
                        while (it.next()) |line| options.err("  {s}", .{line});
                        self.getAllocator().free(result.stdout);
                        return error.ExitCodeFailure;
                    }
                    const trimmed = std.mem.trim(u8, result.stdout, &std.ascii.whitespace);
                    var it = std.mem.tokenizeScalar(u8, trimmed, '\n');
                    while (it.next()) |line| options.info("   {s}", .{line});
                    return trimmed;
                },
                .signal, .stopped => |sig| {
                    options.err("System command failed. Signal: \"{d}\"", .{@intFromEnum(sig)});
                    var it = std.mem.tokenizeScalar(u8, result.stderr, '\n');
                    while (it.next()) |line| options.err("  {s}", .{line});
                    self.getAllocator().free(result.stdout);
                    return error.ProcessTerminated;
                },
                .unknown => |code| {
                    options.err("System command failed. Exit code: \"{d}\"", .{@as(u8, @truncate(code))});
                    var it = std.mem.tokenizeScalar(u8, result.stderr, '\n');
                    while (it.next()) |line| options.err("  {s}", .{line});
                    self.getAllocator().free(result.stdout);
                    return error.ProcessTerminated;
                },
            }
        }
    }

    pub fn addRunArtifact(self: *@This(), compile: *std.Build.Step.Compile) *std.Build.Step.Run {
        options.debug("Adding a run step from \"{s}\" {s}", .{ compile.name, self.kind(compile) });
        return self.ptrBuilder().addRunArtifact(compile);
    }

    pub fn addWriteFiles(self: *@This()) *std.Build.Step.WriteFile {
        options.debug("Adding a write files step from", .{});
        return self.ptrBuilder().addWriteFiles();
    }

    pub fn addCopyFile(self: *@This(), write_file: *std.Build.Step.WriteFile, source: std.Build.LazyPath, paths: []const []const u8) std.Build.LazyPath {
        const path = self.resolve(paths);
        options.debug("Placing the {s} file into the generated directory within the local cache", .{path});
        return write_file.addCopyFile(source, path);
    }

    pub fn expectExitCode(_: @This(), r: *std.Build.Step.Run, code: u8) void {
        options.debug("Expecting {d} exit code from \"{s}\" run step", .{ code, r.step.name });
        r.expectExitCode(code);
    }

    pub fn captureStdOut(_: @This(), r: *std.Build.Step.Run) std.Build.LazyPath {
        options.debug("Capturing stdout from \"{s}\" run step", .{r.step.name});
        return r.captureStdOut(.{});
    }

    pub fn addPassthruArgs(_: @This(), r: *std.Build.Step.Run) void {
        // TODO: remove this for 0.17.0 release
        if (@hasDecl(std.Build.Step.Run, "addPassthruArgs")) {
            options.debug("Running \"{s}\" step with zig build arguments", .{r.step.name});
            r.addPassthruArgs();
        } else unreachable;
    }

    pub fn addArgs(self: @This(), r: *std.Build.Step.Run, args: []const []const u8) void {
        options.debug("Running \"{s}\" step with these arguments: \"{s}\"", .{ r.step.name, self.join("\" \"", args) });
        r.addArgs(args);
    }

    pub fn setCwd(self: *@This(), r: *std.Build.Step.Run, paths: []const []const u8) void {
        const path = self.resolve(paths);
        options.debug("Changing current working directory to {s} for \"{s}\" run step", .{ path, r.step.name });
        r.setCwd(self.ptrBuilder().path(path));
    }

    pub fn installArtifact(self: *@This(), compile: *std.Build.Step.Compile) void {
        options.debug("Installing \"{s}\" {s}", .{ compile.name, self.kind(compile) });
        self.ptrBuilder().installArtifact(compile);
    }

    pub fn dependOn(_: *@This(), step1: *std.Build.Step, step2: *std.Build.Step) void {
        options.debug("Making \"{s}\" step depends on \"{s}\" step", .{ step1.name, step2.name });
        step1.dependOn(step2);
    }

    // std.fs wrappers --------------------------------------------------------

    pub fn openDir(self: *@This(), paths: []const []const u8) !std.Io.Dir {
        const path = self.resolve(paths);
        options.debug("Opening {s}{s}{s}", .{ self.getBuilder().dep_prefix, self.getPrefix(), path });
        return self.ptrCwd().openDir(self.getIo(), path, .{ .iterate = true });
    }

    pub fn closeDir(self: *@This(), dir: std.Io.Dir) void {
        const build_path = self.ptrCwd().realPathFileAlloc(self.getIo(), ".", self.getAllocator()) catch @panic("std.Io.Dir.realPathFileAlloc failed");
        const dir_path = dir.realPathFileAlloc(self.getIo(), ".", self.getAllocator()) catch @panic("std.Io.Dir.realPathFileAlloc failed");
        options.debug("Closing {s}{s}{s}", .{ self.getBuilder().dep_prefix, self.getPrefix(), self.relative(build_path, dir_path) });
    }

    pub fn access(self: *@This(), paths: []const []const u8) bool {
        const path = self.resolve(paths);
        const res = !std.meta.isError(self.ptrCwd().access(self.getIo(), path, .{}));
        if (res) options.debug("Accessing {s}", .{path}) else options.debug("Can not access {s}", .{path});
        return res;
    }

    pub fn remove(self: *@This(), paths: []const []const u8) !void {
        const path = self.resolve(paths);
        options.debug("Removing {s}{s}{s}", .{ self.getBuilder().dep_prefix, self.getPrefix(), path });
        self.ptrCwd().deleteTree(self.getIo(), path) catch |e|
            if (e != error.FileNotFound) return e;
    }

    pub fn make(self: *@This(), paths: []const []const u8) !void {
        const path = self.resolve(paths);
        options.debug("Making {s}{s}{s}", .{ self.getBuilder().dep_prefix, self.getPrefix(), path });
        self.ptrCwd().createDir(self.getIo(), path, .default_dir) catch |e|
            if (e != error.PathAlreadyExists) return e;
    }

    pub fn copy(dest: *@This(), dest_paths: []const []const u8, source: *@This(), source_paths: []const []const u8) !void {
        const source_path = dest.resolve(source_paths);
        const dest_path = dest.resolve(dest_paths);
        options.debug("Copying {s}/{s} into {s}{s}{s}", .{
            source.getBuilder().dep_prefix, source_path,
            dest.getBuilder().dep_prefix,   dest.getPrefix(),
            dest_path,
        });
        if (dest.access(dest_paths)) return error.OverwritingCopy;
        try source.ptrCwd().copyFile(source_path, dest.ptrCwd().*, dest_path, dest.getIo(), .{});
    }

    pub fn iterate(self: *@This(), paths: []const []const u8) !?std.Io.Dir.Entry {
        if (self.getIterator() == null) {
            self.ptrDir().* = try self.openDir(paths);
            const path = self.resolve(paths);
            self.ptrPrefix().* = if (std.mem.eql(u8, path, ".")) "/" else self.concat(&.{ "/", path, "/" });
            self.__iterator = self.ptrDir().iterate();
        }

        const io = self.getIo();

        // skip hidden files
        const entry = blk: {
            var next = try self.ptrIterator().next(io);
            if (next == null) break :blk null;
            while (std.mem.startsWith(u8, next.?.name, ".")) {
                next = try self.ptrIterator().next(io);
                if (next == null) break :blk null;
            }
            break :blk next;
        };

        if (entry) |e| {
            options.debug("Iterating into {s}{s}{s} {s}", .{ self.getBuilder().dep_prefix, self.getPrefix(), e.name, @tagName(e.kind) });
        } else {
            self.ptrDir().close(io);
            self.ptrDir().* = self.ptrCwd().*;
            self.ptrPrefix().* = "/";
            self.__iterator = null;
        }

        return entry;
    }

    pub fn walk(self: *@This(), paths: []const []const u8) !?std.Io.Dir.Walker.Entry {
        if (self.getWalker() == null) {
            options.debug("Allocating ressources for walker", .{});
            self.ptrDir().* = try self.openDir(paths);
            const path = self.resolve(paths);
            self.ptrPrefix().* = if (std.mem.eql(u8, path, ".")) "/" else self.concat(&.{ "/", path, "/" });
            self.__walker = try self.ptrDir().walk(self.getAllocator());
        }

        const io = self.getIo();

        // skip hidden files
        const entry = blk: {
            var next = try self.ptrWalker().next(io);
            if (next == null) break :blk null;
            var it = std.mem.tokenizeScalar(u8, next.?.path, std.fs.path.sep);
            while (it.next()) |token| {
                if (std.mem.startsWith(u8, token, ".")) {
                    next = try self.ptrWalker().next(io);
                    if (next == null) break :blk null;
                    it = std.mem.tokenizeScalar(u8, next.?.path, std.fs.path.sep);
                }
            }
            break :blk next;
        };

        if (entry) |e| {
            options.debug("Walking into {s}{s}{s} {s}", .{ self.getBuilder().dep_prefix, self.getPrefix(), e.path, @tagName(e.kind) });
        } else {
            options.debug("Freeing ressources for walker", .{});
            self.ptrDir().close(io);
            self.ptrDir().* = self.ptrCwd().*;
            self.ptrPrefix().* = "/";
            self.ptrWalker().deinit();
            self.__walker = null;
        }

        return entry;
    }

    pub fn readFile(self: *@This(), paths: []const []const u8) ![]const u8 {
        const path = self.resolve(paths);
        options.debug("Reading {s}", .{path});
        return self.ptrCwd().readFileAlloc(self.getIo(), path, self.getAllocator(), .unlimited);
    }

    pub fn writeFile(self: *@This(), paths: []const []const u8, content: []const u8) !void {
        const path = self.resolve(paths);
        options.debug("Writing into {s}", .{path});
        try self.ptrCwd().writeFile(self.getIo(), .{ .sub_path = path, .data = content });
    }
};

pub fn build(builder: *std.Build) !void {
    _ = builder.addModule("toolbox", .{
        .root_source_file = builder.addWriteFiles().add("empty.zig", ""),
    });
}
