const std = @import("std");
const XClient = @import("XClient.zig");

pub fn main() !void {
    var client = try XClient.init();
    defer client.deinit();
}

