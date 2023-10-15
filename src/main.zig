const std = @import("std");
const XClient = @import("XClient.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _= gpa.deinit();
    var client = try XClient.init(allocator);
    defer client.deinit();
    try client.eventLoop();
}
