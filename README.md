# Toolbox

A wrapper around `std.Build` to make debugging easier for C APIs I package & maintain for [Zig][2]

## Important note

This package was originally thought for the [tiawl/spaceporn][1] dependencies chain. It is actively used in it. For this reason, I do not recommend using it outside of this scope. But this is also a good reason to make it evolve in a way that could answer other needs. So this repository is open to breaking proposals.

If you want to see how to use it you can check repositories list into the [CICD reminder section](https://github.com/tiawl/toolbox/tree/trunk#cicd-reminder).

## Dependencies

The [Zig][2] part of this package is relying on the latest [Zig][2] release (0.15.2) and will only be updated for the next one.

## CICD reminder

These repositories are automatically updated when a new release is available:
* [tiawl/vulkan.zig][3]
* [tiawl/wayland.zig][4]
* [tiawl/X11.zig][5]
* [tiawl/glfw.zig][6]
* [tiawl/cimgui.zig][7]
* [tiawl/spirv.zig][8]
* [tiawl/glslang.zig][9]
* [tiawl/shaderc.zig][10]

## License

This repository is dedicated to the public domain. See the LICENSE file for more details.

[1]:https://github.com/tiawl/spaceporn
[2]:https://github.com/ziglang/zig
[3]:https://github.com/tiawl/vulkan.zig
[4]:https://github.com/tiawl/wayland.zig
[5]:https://github.com/tiawl/X11.zig
[6]:https://github.com/tiawl/glfw.zig
[7]:https://github.com/tiawl/cimgui.zig
[8]:https://github.com/tiawl/spirv.zig
[9]:https://github.com/tiawl/glslang.zig
[10]:https://github.com/tiawl/shaderc.zig
