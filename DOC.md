# Documentation

**This documentation describes the 1.9.5 release**

The package is divided into 4 submodules:
* `build/command.zig` gathers files or processes manipulation utilities used during the updating step,
* `build/compilation.zig` gathers utilities used during the compilation step,
* `build/dependencies.zig` gather utilities related to external dependencies during the fetching step,
* `build/test.zig` gather boolean utilities used during the updating step,

## The `build/command.zig` submodule

### The `write (path: [] const u8, name: [] const u8, content: [] const u8) !void` function

* Write a new file `name` into the absolute `path` with this `content` and print `path`/`name`.

### The `make (path: [] const u8) !void` function

* Make a new directory with the absolute `path` and print `path`.

### The `copy (src: [] const u8, dest: [] const u8) !void` function

* Copy the file specified by the `src` asolute path into the `dest` absolute path location and print them.

### The `run (builder: *std.Build, proc: struct { argv: [] const [] const u8, cwd: ?[] const u8 = null, env: ?*const std.process.EnvMap = null, wait: ?*const fn () void = null, stdout: ?*[] const u8 = null, ignore_errors: bool = false, }) !void` function

* Run an external process with `argv` arguments into the optional `cwd` directory with the optional `env` variables. It optionnally uses the `wait` function before killing the process. It optionnally collects the standard output into `stdout`. It optionally ignores errors (and stderr).

### The `clean (builder: *std.Build, paths: [] const [] const u8, extensions: [] const [] const u8) !void` function

* In the specified `paths`, it deletes recursively all empty directories and files without known C, C++, or specified `extensions`. It prints the absolute path of removed directories/files.

## The `build/compilation.zig` submodule

### The `addHeader (lib: *std.Build.Step.Compile, source: [] const u8, dest: [] const u8, ext: [] const [] const u8) void` function

* Mark headers with specified `ext` into the absolute path `source` directory for the specified `lib` installation, add them to the `lib`'s include search path `dest` and print `source`.

### The `addInclude (lib: *std.Build.Step.Compile, path: [] const u8) void` function

* Add the absolute `path` directory to the list of directories to be searched for header files during preprocessing to the specified `lib` and print `path`.

### The `addSource (lib: *std.Build.Step.Compile, root_path: [] const u8, base_path: [] const u8, flags: [] const [] const u8) !void` function

* Compile or assemble the `root_path`/`base_path` source file with `flags`, add it to the specified `lib` and print the absolute source filepath.

## The `build/dependencies.zig` submodule

### The `version (builder: *std.Build, repo: [] const u8) ![] const u8` function

* In the current dependency repository, search a filename `repo` into the `.versions/` directory and return its trimmed content (which is the version of `repo` used by the dependency).

### The `isSubmodule (builder: *std.Build, name: [] const u8) !bool` function

* In the current dependency repository, check if the given `name` is a git submodule.

### The `Repository` struct

* Depicts a Github/Gitlab repository with a `name`, a git `url` and a `latest` release.

### The `Repository.Host` enum

* Gitlab or Github ? choose your disease.

### The `Dependencies` struct

* Depicts a whole tiawl/spaceporn dependency set of dependencies. A tiawl/spaceporn dependency has `extern` and `intern` dependencies.

### The `Dependencies.clone (self: @This (), builder: *std.Build, repo: [] const u8, path: [] const u8) !void` method

* Git clone the `repo` extern dependency into `path`.

## The `build/test.zig` submodule

### The `isCSource (name: [] const u8) bool` function

* Test if the given `name` is a C source file.

### The `isCppSource (name: [] const u8) bool` function

* Test if the given `name` is a C++ source file.

### The `isSource (name: [] const u8) bool` function

* Test if the given `name` is a C or C++ source file.

### The `isCHeader (name: [] const u8) bool` function

* Test if the given `name` is a C header file.

### The `isCppHeader (name: [] const u8) bool` function

* Test if the given `name` is a Cpp header file.

### The `isHeader (path: [] const u8) bool` function

* Test if the given `name` is a C or C++ header file.

### The `exists (name: [] const u8) bool` function

* Test if the given absolute `path` is accessible.
