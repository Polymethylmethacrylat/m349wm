const c = @import("c.zig");
const std = @import("std");
const Config = @import("Config.zig");
const XClient = @import("XClient.zig");

pub const Action = struct {
    const Self = @This();
    ptr: *anyopaque,
    func: *const fn (*anyopaque, *XClient) anyerror!void,
    pub fn execute(self: Self, client: *XClient) !void {
        return self.func(self.ptr, client);
    }
};

pub const Move = struct {
    const Self = @This();

    direction: Direction,

    pub const Direction = enum {
        north,
        east,
        south,
        west,
    };
    fn execute(ctx: *anyopaque, client: *XClient) !void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const direction = self.direction;

        const tree_cookie = c.xcb_query_tree(client.conn, client.screen.root);
        const tree_reply = c.xcb_query_tree_reply(client.conn, tree_cookie, null);
        const tree_children = c.xcb_query_tree_children(tree_reply);
        const window = tree_children[@as(usize, (@intCast(c.xcb_query_tree_children_length(tree_reply)))) - 1];

        const geometry_cookie = c.xcb_get_geometry(client.conn, window);
        const geometry_reply = c.xcb_get_geometry_reply(client.conn, geometry_cookie, null);

        const x: i16 = geometry_reply.*.x +% @as(i16, switch (direction) {
            .east => 5,
            .west => -5,
            else => 0,
        });
        const y: i16 = geometry_reply.*.y +% @as(i16, switch (direction) {
            .north => -5,
            .south => 5,
            else => 0,
        });

        std.debug.print("x: {}, y: {}\n", .{x, y});

        const value_mask: u16 = c.XCB_CONFIG_WINDOW_X | c.XCB_CONFIG_WINDOW_Y;
        const value_list = [_]i32{
            x,
            y,
        };
        std.debug.print("x: {}, y: {}\n", .{value_list[0], value_list[1]});
        _ = c.xcb_configure_window_checked(client.conn, window, value_mask, &value_list);
        _ = c.xcb_flush(client.conn);
    }
    pub fn action(self: *Self) Action {
        return .{ .ptr = self, .func = execute };
    }
};

pub const Exit = struct {
    const Self = @This();
    fn execute(ctx: *anyopaque, client: *XClient) anyerror!void {
        _ = ctx;
        _ = client;
        return error.Exit;
    }
    pub fn action(self: *Self) Action {
        return .{ .ptr = self, .func = execute };
    }
};
