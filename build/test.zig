const std = @import ("std");

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
