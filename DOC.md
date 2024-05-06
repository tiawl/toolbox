# Documentation

**This documentation describes the 1.10.0 release**

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

The `build/dependencies.zig` submodule needs a `.references` folder at the root of your repository. Each file in this repository matches a field name used to initialize the `extern` and `intern` attributes of the `Dependencies` struct. Here an example:
```zig
const dependencies = try toolbox.Dependencies.init (
  // Your *std.Build instance
  builder,

  // The name of your Zig package (useful when updating your `build.zig.zon`)
  "vulkan.zig",

  // Paths to add in your `build.zig.zon` (`build.zig` and `build.zig.zon`
  // are automatically added)
  &.{ "vulkan", },

  // The `intern` attribute of the `Dependencies` struct: it's your
  // `build.zig.zon` dependencies
  .{
     // Name of the dependency (specified in your `build.zig.zon`)
     .toolbox = .{
       // Repository name
       .name = "tiawl/toolbox",
       // Repository host
       .host = toolbox.Repository.Host.github,
       // Do you want to update this dependency for each new tag or new
       // commit ?
       .ref = toolbox.Repository.Reference.tag,
     },

   // The `extern` attribute of the `Dependencies` struct: it is your
   // `.references` files
   }, .{
     // The name must matches the `.references` filename you choosed
     .wayland = .{
       .name = "wayland/wayland",
       // The complementary domain (only useful for Gitlab repositories). For
       // this example, it matches this URL:
       // 'https://gitlab.freedesktop.org/wayland/wayland'
       .domain = "freedesktop.org",
       .host = toolbox.Repository.Host.gitlab,
       .ref = toolbox.Repository.Reference.commit,
     },
   });
```

### The `reference (builder: *std.Build, repo: [] const u8) ![] const u8` function

* In the current dependency repository, search a filename `repo` into the `.references/` directory and return its trimmed content (which is the reference used).

### The `Repository` struct

* Depicts a Github/Gitlab repository with a `name`, a git `url`, a `latest` `ref`erence. It should not be used in your repositories.

### The `Repository.Host` enum

* Is this a Gitlab or Github repository ?

### The `Repository.Reference` enum

* Depicts the tag or commit used by the Github/Gitlab repository.

### The `Dependencies` struct

* Depicts a whole set of dependencies with `extern` and `intern` dependencies. When initialized in your `build.zig`, it adds the `-Dfetch` option to your build step. This step updates the `.references` folder and the `build.zig.zon` file.

### The `Dependencies.clone (self: @This (), builder: *std.Build, repo: [] const u8, path: [] const u8) !void` method

* Git clone the extern dependency `repo` into `path`.

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
