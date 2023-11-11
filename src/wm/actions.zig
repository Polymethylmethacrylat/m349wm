const c = @import("../c.zig");
const std = @import("std");
const Config = @import("Config.zig");
const root = @import("root");
const wm = @import("../wm.zig");
const Action = wm.Action;

pub const Focus = struct {
    const Self = @This();

    focus_mode: FocusMode,

    const FocusMode = union(enum) {
        window: c.xcb_window_t,
        direction: Direction,
    };

    const Direction = enum {
        left,
        right,
        up,
        down,
    };

    fn execute(ctx: *anyopaque) !void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const conn = root.getConnection();
        switch (self.focus_mode) {
            .window => |window| {
                c.xcb_set_input_focus(conn, c.XCB_INPUT_FOCUS_NONE, window, c.XCB_CURRENT_TIME);
                // error handling !!!!!!!!!!!!
            },
            .direction => |direction| {
                const current_client = root.getCurrentClient().?;
                const clients = root.getClients();

                var found: ?wm.Client = null;
                for (clients) |client| {
                    const current_client_center = .{
                        .x = current_client.x + current_client.width / 2 + current_client.border_width,
                        .y = current_client.y + current_client.height / 2 + current_client.border_width,
                    };
                    const client_center = .{
                        .x = client.x + client.width / 2 + client.border_width,
                        .y = client.y + client.height / 2 + client.border_width,
                    };
                    const found_center = if (found) |_|
                        .{
                            .x = found.?.x + found.?.width/2 + found.?.border_width,
                            .y = found.?.y + found.?.height/2 + found.?.border_width,
                        } else .{.x = 0, .y = 0};
                    if (switch (direction) {
                        .left => {
                            if (client_center.x > current_client_center.x)
                                break true;
                            if (
                                client_center.x > current_client.x
                                and std.math.absInt(client_center.y - current_client_center.y) > current_client.height
                            ) break true;
                            if (found == null) break false;
                            if (
                                std.math.absInt(client_center.y - current_client_center.y) > current_client.height
                                and std.math.absInt(found_center.y - current_client_center.y) < current_client.height
                            ) break true;
                            if (
                                std.math.absInt(client_center.y - current_client_center.y) < current_client.height
                                and std.math.absInt(found_center.y - current_client_center.y) > current_client.height
                            ) break false;
                            if (found_center.x > client_center.x)
                                break true;
                            break false;
                        },
                        .right => {
                            if (client_center.x < current_client_center.x)
                                break true;
                            if (
                                client_center.x < current_client.x + 2*current_client.border_width + current_client.width
                                and std.math.absInt(client_center.y - current_client_center.y) > current_client.height
                            ) break true;
                            if (found == null) break false;
                            if (
                                std.math.absInt(client_center.y - current_client_center.y) > current_client.height
                                and std.math.absInt(found_center.y - current_client_center.y) < current_client.height
                            ) break true;
                            if (
                                std.math.absInt(client_center.y - current_client_center.y) < current_client.height
                                and std.math.absInt(found_center.y - current_client_center.y) > current_client.height
                            ) break false;
                            if (found_center.x < client_center.X)
                                break true;
                            break false;
                        },
                        .up => {
                            if (client_center.y < current_client_center.y)
                                break true;
                            if (
                                client_center.y > current_client.y
                                and std.math.absInt(client_center.x - current_client_center.x) > current_client.width
                            ) break true;
                            if (found == null) break false;
                            if (
                                std.math.absInt(client_center.x - current_client_center.x) > current_client.width
                                and std.math.absInt(found_center.x - current_client_center.x) < current_client.width
                            ) break true;
                            if (
                                std.math.absInt(client_center.x - current_client_center.x) < current_client.width
                                and std.math.absInt(found_center.x - current_client_center.x) > current_client.width
                            ) break true;
                            if (found_center.y > client_center.Y)
                                break true;
                            break false;
                        },
                        .down => {
                            if (client_center.y > current_client_center.y)
                                break true;
                            if (
                                client_center.y < current_client.y + 2*current_client.border_width + current_client.height
                                and std.math.absInt(client_center.y - current_client_center.y) > current_client.width
                            ) break true;
                            if (found == null) break false;
                            if (
                                std.math.absInt(client_center.x - current_client_center.x) < current_client.width
                                and std.math.absInt(found_center.x - current_client_center.x) > current_client.width
                            ) break true;
                            if (
                                std.math.absInt(client_center.x - current_client_center.x) > current_client.width
                                and std.math.absInt(found_center.x - current_client_center.x) < current_client.width
                            ) break true;
                            if (found_center.y < client_center.Y)
                                break true;
                            break false;
                        },
                    }) continue;

                    found = client;
                }
            },
        }
    }
    fn action(self: *Self) Action {
        return .{ .ptr = self, .func = execute };
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
    fn execute(ctx: *anyopaque) !void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const direction = self.direction;
        const conn = root.getConnection();

        //const tree_cookie = c.xcb_query_tree(conn, root.getScreen().root);
        //const tree_reply = c.xcb_query_tree_reply(conn, tree_cookie, null);
        //if (c.xcb_query_tree_children_length(tree_reply) < 1)
        //  return;
        //const tree_children = c.xcb_query_tree_children(tree_reply);
        const window = root.getCurrentClient().?.window; //tree_children[@as(usize, (@intCast(c.xcb_query_tree_children_length(tree_reply)))) - 1];

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
