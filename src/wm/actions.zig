const c = @import("../c.zig");
const std = @import("std");
const Config = @import("Config.zig");
const root = @import("root");
const wm = @import("../wm.zig");
const Action = wm.Action;

pub const Move = struct {
    const Self = @This();

    direction: Direction,

    pub const Direction = enum {
        north,
        east,
        south,
        west,
    };
    fn execute(ctx: *anyopaque) !void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const direction = self.direction;
        const conn = root.getConnection();

        const tree_cookie = c.xcb_query_tree(conn, root.getScreen().root);
        const tree_reply = c.xcb_query_tree_reply(conn, tree_cookie, null);
        if (c.xcb_query_tree_children_length(tree_reply) < 1)
            return;
        const tree_children = c.xcb_query_tree_children(tree_reply);
        const window = tree_children[@as(usize, (@intCast(c.xcb_query_tree_children_length(tree_reply)))) - 1];

        var old_x: i16 = undefined;
        var old_y: i16 = undefined;

        const client: ?*wm.Client = val: for (root.getClients()) |*client| {
            if (client.window != window)
                continue;
            break :val client;
        } else {
            const geometry_cookie = c.xcb_get_geometry(conn, window);
            const geometry_reply = c.xcb_get_geometry_reply(conn, geometry_cookie, null);
            old_x = geometry_reply.*.x;
            old_y = geometry_reply.*.y;
            break :val null;
        };

        old_x = if (client != null) client.?.x else old_x;
        old_y = if (client != null) client.?.y else old_y;

        const x: i16 = old_x +% @as(i16, switch (direction) {
            .east => 5,
            .west => -5,
            else => 0,
        });
        const y: i16 = old_y +% @as(i16, switch (direction) {
            .north => -5,
            .south => 5,
            else => 0,
        });

        if (client != null) {
            client.?.x = x;
            client.?.y = y;
        }

        const value_mask: u16 = c.XCB_CONFIG_WINDOW_X | c.XCB_CONFIG_WINDOW_Y;
        const value_list = [_]i32{
            x,
            y,
        };
        _ = c.xcb_configure_window_checked(conn, window, value_mask, &value_list);
        _ = c.xcb_flush(conn);
    }
    pub fn action(self: *Self) Action {
        return .{ .ptr = self, .func = execute };
    }
};

pub const Exit = struct {
    const Self = @This();
    fn execute(ctx: *anyopaque) anyerror!void {
        _ = ctx;
        return error.Exit;
    }
    pub fn action(self: *Self) Action {
        return .{ .ptr = self, .func = execute };
    }
};
