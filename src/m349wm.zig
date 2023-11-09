const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const UHashMap = std.AutoHashMapUnmanaged;
const log = std.log.scoped(.m349wm);

const c = @import("c.zig");
const presets = @import("presets.zig");
const wm = @import("wm.zig");
const Client = wm.Client;

const EventHandler = *const fn (ev: *c.xcb_generic_event_t) anyerror!void;
const KeyHandlersT = UHashMap(
    KeyEvent,
    wm.Action,
);
const KeyEvent = struct {
    keycode: c.xcb_keycode_t,
    state: u16,
    action: wm.KeyAction,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();
var conn: *c.xcb_connection_t = undefined;
var screen: *c.xcb_screen_t = undefined;
const event_handlers: [128]?EventHandler = blk: {
    var ev_hndls: [128]?EventHandler = .{null} ** 128;
    ev_hndls[0] = handleError;
    ev_hndls[c.XCB_KEY_PRESS] = handleKeyEvent;
    ev_hndls[c.XCB_KEY_RELEASE] = handleKeyEvent;
    ev_hndls[c.XCB_CREATE_NOTIFY] = handleCreateNotify;
    ev_hndls[c.XCB_DESTROY_NOTIFY] = handleDestroyNotify;
    ev_hndls[c.XCB_UNMAP_NOTIFY] = handleUnmapNotify;
    ev_hndls[c.XCB_MAP_NOTIFY] = handleMapNotify;
    ev_hndls[c.XCB_MAP_REQUEST] = handleMapRequest;
    ev_hndls[c.XCB_REPARENT_NOTIFY] = handleReparentNotify;
    ev_hndls[c.XCB_CONFIGURE_NOTIFY] = handleConfigureNotify;
    ev_hndls[c.XCB_GRAVITY_NOTIFY] = handleGravityNotify;
    ev_hndls[c.XCB_CONFIGURE_REQUEST] = handleConfigureRequest;
    break :blk ev_hndls;
};
var key_handlers: KeyHandlersT = undefined;
var clients: ArrayList(Client) = undefined;

pub fn getConnection() *c.xcb_connection_t {
    return conn;
}
pub fn getScreen() *c.xcb_screen_t {
    return screen;
}

fn handleError(ev: *c.xcb_generic_event_t) !void {
    const err: *c.xcb_generic_error_t = @ptrCast(ev);

    log.warn("unhandled error: {}", .{err.error_code});
}

fn handleKeyEvent(ev: *c.xcb_generic_event_t) !void {
    const e: *c.xcb_key_press_event_t = @ptrCast(ev);
    const keycode = e.detail;
    const state = e.state & ~@as(u16, 0xff00);
    const action: wm.KeyAction = if (e.response_type == c.XCB_KEY_PRESS) .press else .release;

    if (key_handlers.get(.{ .keycode = keycode, .state = state, .action = action })) |act| {
        try act.execute();
    } else {
        log.debug("encountered unhandled key binding: {}", .{.{ .keycode = keycode, .state = state, .action = action }});
    }
}

fn handleCreateNotify(ev: *c.xcb_generic_event_t) !void {
    const e: *c.xcb_create_notify_event_t = @ptrCast(ev);
    const client: Client = .{
        .parent = e.parent,
        .window = e.window,
        .x = e.x,
        .y = e.y,
        .width = e.width,
        .height = e.height,
        .border_width = e.border_width,
        .override_redirect = e.override_redirect != 0,
        .mapped = false,
    };
    log.debug("a new client has been created: {}", .{client});

    try clients.append(client);
}

fn handleDestroyNotify(ev: *c.xcb_generic_event_t) !void {
    const e: *c.xcb_destroy_notify_event_t = @ptrCast(ev);

    for (clients.items, 0..) |client, i| {
        if (client.window != e.window)
            continue;

        const destroyed_client = clients.swapRemove(i);
        log.debug("a client got destroyed: {}", .{destroyed_client});
    } else {
        log.warn("an unknown client got destroyed: {}", .{e});
    }
}

fn handleMapRequest(ev: *c.xcb_generic_event_t) !void {
    const window: c.xcb_window_t = @as(*c.xcb_map_request_event_t, @ptrCast(ev)).window;
    _ = c.xcb_map_window(conn, window);
    _ = c.xcb_flush(conn);
    // triggers a MapNotify(hopefully)
}

fn handleMapNotify(ev: *c.xcb_generic_event_t) !void {
    const e: *c.xcb_destroy_notify_event_t = @ptrCast(ev);
    for (clients.items) |*client| {
        if (client.window != e.window)
            continue;
        client.mapped = true;
        break;
    }
}

fn handleUnmapNotify(ev: *c.xcb_generic_event_t) !void {
    const e: *c.xcb_destroy_notify_event_t = @ptrCast(ev);
    for (clients.items) |*client| {
        if (client.window != e.window)
            continue;
        client.mapped = false;
        break;
    }
}

fn handleReparentNotify(ev: *c.xcb_generic_event_t) !void {
    const e: *c.xcb_reparent_notify_event_t = @ptrCast(ev);
    const translate_cookie = c.xcb_translate_coordinates(conn, e.parent, screen.root, e.x, e.y);
    for (clients.items) |*client| {
        if (client.window != e.window)
            continue;

        const translate_repl = c.xcb_translate_coordinates_reply(conn, translate_cookie, null);
        client.parent = e.parent;
        // only single monitor setups rn
        client.x = translate_repl.*.dst_x;
        client.y = translate_repl.*.dst_y;
        break;
    }
}

fn handleConfigureNotify(ev: *c.xcb_generic_event_t) !void {
    const e: *c.xcb_configure_notify_event_t = @ptrCast(ev);
    for (clients.items) |*client| {
        if (client.window != e.window)
            continue;

        const translate_cookie = c.xcb_translate_coordinates(conn, client.parent, screen.root, e.x, e.y);
        const translate_repl = c.xcb_translate_coordinates_reply(conn, translate_cookie, null);
        // only single monitor setups rn
        client.x = translate_repl.*.dst_x;
        client.y = translate_repl.*.dst_y;
        client.width = e.width;
        client.height = e.height;
        client.border_width = e.border_width;
        client.override_redirect = e.override_redirect != 0;
        break;
    }
}

fn handleGravityNotify(ev: *c.xcb_generic_event_t) !void {
    const e: *c.xcb_gravity_notify_event_t = @ptrCast(ev);

    for (clients.items) |*client| {
        if (client.window != e.window)
            continue;

        const translate_cookie = c.xcb_translate_coordinates(conn, client.parent, screen.root, e.x, e.y);
        const translate_repl = c.xcb_translate_coordinates_reply(conn, translate_cookie, null);
        // only single monitor setups rn
        client.x = translate_repl.*.dst_x;
        client.y = translate_repl.*.dst_y;
        break;
    }
}

fn handleConfigureRequest(ev: *c.xcb_generic_event_t) !void {
    const e: *c.xcb_configure_request_event_t = @ptrCast(ev);
    const value_mask: u16 = 
        c.XCB_CONFIG_WINDOW_X |
        c.XCB_CONFIG_WINDOW_Y |
        c.XCB_CONFIG_WINDOW_WIDTH |
        c.XCB_CONFIG_WINDOW_HEIGHT |
        c.XCB_CONFIG_WINDOW_BORDER_WIDTH |
        c.XCB_CONFIG_WINDOW_SIBLING |
        c.XCB_CONFIG_WINDOW_STACK_MODE;
    const value_list = [_]u32{
        @as(u16, @bitCast(e.x)),
        @as(u16, @bitCast(e.y)),
        e.width,
        e.height,
        e.border_width,
        e.sibling,
        e.stack_mode,
    };

    _ = c.xcb_configure_window(conn, e.window, value_mask, &value_list);

    for (clients.items) |*client| {
        if (client.window != e.window)
            continue;

        client.x = e.x;
        client.y = e.y;
        client.width = e.width;
        client.height = e.height;
        client.border_width = e.border_width;
        break;
    }
}

fn eventLoop() !void {
    while (@as(?*c.xcb_generic_event_t, c.xcb_wait_for_event(conn))) |ev| {
        defer c.free(ev);
        if (event_handlers[ev.response_type & ~@as(u8, 0x80)]) |ev_handl| {
            log.debug("handling event: {}", .{ev.response_type});
            ev_handl(ev) catch |err| {
                if (err == error.Exit) {
                    return;
                } else {
                    return err;
                }
            };
        } else {
            log.info("encountered unhandled event: {}", .{ev.response_type});
        }
    } else {
        // might expand errorhandling in the future
        return error.ConnectionError;
    }
}

fn setupKeys() !void {
    key_handlers = KeyHandlersT{};
    errdefer key_handlers.deinit(allocator);
    const keysyms = c.xcb_key_symbols_alloc(conn).?;
    defer c.xcb_key_symbols_free(keysyms);
    const key_mappings_count: u32 = blk: {
        var count: u32 = presets.default.key_mappings.len;
        if (!presets.default.num_lock_explicit)
            count *= 2;
        if (presets.default.caps_eqls_shift)
            count *= 2;
        break :blk count;
    };
    const numloc_mod: c.xcb_mod_mask_t = blk: {
        if (presets.default.num_lock_explicit)
            break :blk undefined;
        const numloc_code: c.xcb_keycode_t = c.xcb_key_symbols_get_keycode(keysyms, c.XK_Num_Lock).*;
        const mod_map_req = c.xcb_get_modifier_mapping(conn);
        const mod_map_repl = c.xcb_get_modifier_mapping_reply(conn, mod_map_req, null);
        const mod_keys = c.xcb_get_modifier_mapping_keycodes(mod_map_repl);
        const mod_keys_len = c.xcb_get_modifier_mapping_keycodes_length(mod_map_repl);
        const group_size = mod_map_repl.*.keycodes_per_modifier;

        for (mod_keys[0..@intCast(mod_keys_len)], 0..) |mod_key, i| {
            if (mod_key != numloc_code)
                continue;

            break :blk switch (i / group_size) {
                0 => c.XCB_MOD_MASK_SHIFT,
                1 => c.XCB_MOD_MASK_LOCK,
                2 => c.XCB_MOD_MASK_CONTROL,
                3 => c.XCB_MOD_MASK_1,
                4 => c.XCB_MOD_MASK_2,
                5 => c.XCB_MOD_MASK_3,
                6 => c.XCB_MOD_MASK_4,
                7 => c.XCB_MOD_MASK_5,
                else => unreachable,
            };
        }

        break :blk 0;
    };
    try key_handlers.ensureTotalCapacity(allocator, key_mappings_count);

    for (presets.default.key_mappings) |key_map| {
        const key_code: c.xcb_keycode_t = c.xcb_key_symbols_get_keycode(keysyms, key_map.key).*;
        const key_mod: c.xcb_mod_mask_t = key_map.mod;
        const action = key_map.key_action;
        const func = key_map.action;

        _ = c.xcb_grab_key(conn, 1, screen.root, @truncate(key_mod), key_code, c.XCB_GRAB_MODE_ASYNC, c.XCB_GRAB_MODE_ASYNC);
        key_handlers.putAssumeCapacity(.{ .keycode = key_code, .state = @truncate(key_mod), .action = action }, func);

        if (!presets.default.num_lock_explicit) {
            var mod: u16 = @truncate(key_mod ^ numloc_mod);
            _ = c.xcb_grab_key(conn, 1, screen.root, mod, key_code, c.XCB_GRAB_MODE_ASYNC, c.XCB_GRAB_MODE_ASYNC);
            key_handlers.putAssumeCapacity(.{ .keycode = key_code, .state = mod, .action = action }, func);

            if (presets.default.caps_eqls_shift) {
                mod ^= @truncate(@as(c_uint, @intCast(c.XCB_MOD_MASK_SHIFT | c.XCB_MOD_MASK_LOCK)));
                _ = c.xcb_grab_key(conn, 1, screen.root, mod, key_code, c.XCB_GRAB_MODE_ASYNC, c.XCB_GRAB_MODE_ASYNC);
                key_handlers.putAssumeCapacity(.{ .keycode = key_code, .state = mod, .action = action }, func);

                mod = @truncate(key_mod ^ (c.XCB_MOD_MASK_SHIFT | c.XCB_MOD_MASK_LOCK));
                _ = c.xcb_grab_key(conn, 1, screen.root, mod, key_code, c.XCB_GRAB_MODE_ASYNC, c.XCB_GRAB_MODE_ASYNC);
                key_handlers.putAssumeCapacity(.{ .keycode = key_code, .state = mod, .action = action }, func);
            }
        } else if (presets.default.caps_eqls_shift) {
            const mod: u16 = @truncate(key_mod ^ (c.XCB_MOD_MASK_SHIFT | c.XCB_MOD_MASK_LOCK));
            _ = c.xcb_grab_key(conn, 1, screen.root, mod, key_code, c.XCB_GRAB_MODE_ASYNC, c.XCB_GRAB_MODE_ASYNC);
            key_handlers.putAssumeCapacity(.{ .keycode = key_code, .state = mod, .action = action }, func);
        }
    }
    _ = c.xcb_flush(conn);
}

pub fn main() !void {
    defer {
        switch (gpa.deinit()) {
            .ok => log.info("no leaks detected", .{}),
            .leak => log.warn("memory leaks detected!", .{}),
        }
    }

    // never returns null
    conn = c.xcb_connect(null, null).?;
    defer c.xcb_disconnect(conn);
    if (c.xcb_connection_has_error(conn) != 0)
        return error.ConnectionError;

    // sets screen
    screen = @ptrCast(c.xcb_setup_roots_iterator(c.xcb_get_setup(conn)).data);

    log.debug("connection succesfull: {}", .{.screen = screen});

    // Request wm-permissions
    {
        const values = comptime blk: {
            var val = c.XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT;
            val |= c.XCB_EVENT_MASK_STRUCTURE_NOTIFY;
            val |= c.XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY;
            val |= c.XCB_EVENT_MASK_PROPERTY_CHANGE;
            break :blk val;
        };

        const wm_request = c.xcb_change_window_attributes_checked(conn, screen.root, c.XCB_CW_EVENT_MASK, &values);
        _ = c.xcb_flush(conn);
        if (c.xcb_request_check(conn, wm_request)) |_| {
            return error.WmRequestFailed;
        }
    }

    try setupKeys();
    defer key_handlers.deinit(allocator);

    clients = try ArrayList(Client).initCapacity(allocator, 64);
    defer clients.deinit();

    // gather already existing clients
    {
        const tree_cookie = c.xcb_query_tree(conn, screen.root);
        const tree_repl = c.xcb_query_tree_reply(conn, tree_cookie, null);
        const children_length: usize = @intCast(c.xcb_query_tree_children_length(tree_repl));
        const children = c.xcb_query_tree_children(tree_repl)[0..children_length];

        for (children) |child| {
            const geometry_cookie = c.xcb_get_geometry(conn, child);
            const attributes_cookie = c.xcb_get_window_attributes(conn, child);
            const geometry_repl = c.xcb_get_geometry_reply(conn, geometry_cookie, null);
            const attributes_repl = c.xcb_get_window_attributes_reply(conn, attributes_cookie, null);
            var client: Client = .{
                .parent = screen.root,
                .window = child,
                .x = geometry_repl.*.x,
                .y = geometry_repl.*.y,
                .width = geometry_repl.*.width,
                .height = geometry_repl.*.height,
                .border_width = geometry_repl.*.height,
                .override_redirect = attributes_repl.*.override_redirect != 0,
                .mapped = attributes_repl.*.map_state != c.XCB_MAP_STATE_UNMAPPED,
            };
            try clients.append(client);
        }
    }

    try eventLoop();
}
