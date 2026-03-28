# Toolbox

A wrapper around `std.Build` to make debugging easier for C APIs I package & maintain for [Zig][2]

## Important note

This package was originally thought for the [tiawl/spaceporn][1] dependencies chain. It is actively used in it. For this reason, I do not recommend using it outside of this scope. But this is also a good reason to make it evolve in a way that could answer other needs. So this repository is open to breaking proposals.

## Dependencies

The [Zig][2] part of this package is relying on the latest [Zig][2] release (0.15.2) and will only be updated for the next one.
It you use a more recent [Zig][2] version, please consider the `zig-nightly` branch and `*-nightly` tags.

## License

This repository is dedicated to the public domain. See the LICENSE file for more details.

[1]:https://github.com/tiawl/spaceporn
[2]:https://codeberg.org/ziglang/zig
