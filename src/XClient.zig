const std = @import("std");
const log = std.log.scoped(.m349wm);
const Allocator = std.mem.Allocator;
const AutoHashMapUnmanaged = std.AutoHashMapUnmanaged;

const c = @import("c.zig");
const Config = @import("Config.zig");
const presets = @import("user_config.zig");
const wm = @import("wm_actions.zig");

const Self = @This();

const EventHandler = *const fn (self: *Self, ev: *c.xcb_generic_event_t) anyerror!void;
const KeyHandlersT = AutoHashMapUnmanaged(
    KeyEvent,
    wm.Action,
);
const KeyEvent = struct {
    keycode: c.xcb_keycode_t,
    state: u16,
    action: Config.KeyAction,
};

allocator: Allocator,
conn: *c.xcb_connection_t,
screen: *c.xcb_screen_t,
event_handlers: [128]?EventHandler = blk: {
    var ev_hndls: [128]?EventHandler = .{null} ** 128;
    ev_hndls[0] = handleError;
    ev_hndls[c.XCB_KEY_PRESS] = handleKeyEvent;
    ev_hndls[c.XCB_KEY_RELEASE] = handleKeyEvent;
    ev_hndls[c.XCB_MAP_REQUEST] = handleMapRequest;
    break :blk ev_hndls;
},
key_handlers: KeyHandlersT,

fn handleError(self: *Self, ev: *c.xcb_generic_event_t) !void {
    _ = self;
    const err: *c.xcb_generic_error_t = @ptrCast(ev);

    log.warn("unhandled error: {}", .{err.error_code});
}

fn handleKeyEvent(self: *Self, ev: *c.xcb_generic_event_t) !void {
    const e: *c.xcb_key_press_event_t = @ptrCast(ev);
    const keycode = e.detail;
    const state = e.state & ~@as(u16, 0xff00);
    const action: Config.KeyAction = if (e.response_type == c.XCB_KEY_PRESS) .press else .release;

    if (self.key_handlers.get(.{ .keycode = keycode, .state = state, .action = action })) |act| {
        try act.execute(self);
    } else {
        log.debug("encountered unhandled key binding: {}", .{.{ .keycode = keycode, .state = state, .action = action }});
    }
}

fn handleMapRequest(self: *Self, ev: *c.xcb_generic_event_t) !void {
    const window: c.xcb_window_t = @as(*c.xcb_map_request_event_t, @ptrCast(ev)).window;

    _ = c.xcb_map_window_checked(self.conn, window);
    _ = c.xcb_flush(self.conn);
}

pub fn eventLoop(self: *Self) !void {
    while (c.xcb_wait_for_event(self.conn)) |ev| {
        defer c.free(ev);
        if (self.event_handlers[ev.*.response_type & ~@as(u8, 0x80)]) |ev_handl| {
            log.debug("handling event: {}", .{ev.*.response_type});
            ev_handl(self, ev) catch |err| {
                if (err == error.Exit)
                    return
                else
                    return err;
            };
        } else {
            log.warn("encountered unhandled event: {}", .{ev.*.response_type});
        }
    } else {
        // might expand errorhandling in the future
        return error.ConnectionError;
    }
}

pub fn init(allocator: Allocator) !*Self {
    // create self
    const self: *Self = try allocator.create(Self);
    errdefer allocator.destroy(self);
    self.* = Self{
        .allocator = allocator,
        .conn = undefined,
        .screen = undefined,
        .key_handlers = undefined,
    };

    // never returns null
    self.conn = c.xcb_connect(null, null).?;
    errdefer c.xcb_disconnect(self.conn);
    if (c.xcb_connection_has_error(self.conn) != 0)
        return error.ConnectionError;

    // sets screen
    self.screen = @ptrCast(c.xcb_setup_roots_iterator(c.xcb_get_setup(self.conn)).data);

    // Request wm-permissions
    {
        const values = comptime blk: {
            var val = c.XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT;
            val |= c.XCB_EVENT_MASK_STRUCTURE_NOTIFY;
            val |= c.XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY;
            val |= c.XCB_EVENT_MASK_PROPERTY_CHANGE;
            break :blk val;
        };

        const wm_request = c.xcb_change_window_attributes_checked(self.conn, self.screen.root, c.XCB_CW_EVENT_MASK, &values);
        _ = c.xcb_flush(self.conn);
        if (c.xcb_request_check(self.conn, wm_request)) |_| {
            return error.WmRequestFailed;
        }
    }

    // set up keybindings
    {
        self.key_handlers = KeyHandlersT{};
        errdefer self.key_handlers.deinit(allocator);
        const keysyms = c.xcb_key_symbols_alloc(self.conn).?;
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
            const mod_map_req = c.xcb_get_modifier_mapping(self.conn);
            const mod_map_repl = c.xcb_get_modifier_mapping_reply(self.conn, mod_map_req, null);
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
        try self.key_handlers.ensureTotalCapacity(allocator, key_mappings_count);

        for (presets.default.key_mappings) |key_map| {
            const key_code: c.xcb_keycode_t = c.xcb_key_symbols_get_keycode(keysyms, key_map.key).*;
            const key_mod: c.xcb_mod_mask_t = key_map.mod;
            const action = key_map.key_action;
            const func = key_map.action;

            _ = c.xcb_grab_key(self.conn, 1, self.screen.root, @truncate(key_mod), key_code, c.XCB_GRAB_MODE_ASYNC, c.XCB_GRAB_MODE_ASYNC);
            self.key_handlers.putAssumeCapacity(.{ .keycode = key_code, .state = @truncate(key_mod), .action = action }, func);

            if (!presets.default.num_lock_explicit) {
                var mod: u16 = @truncate(key_mod ^ numloc_mod);
                _ = c.xcb_grab_key(self.conn, 1, self.screen.root, mod, key_code, c.XCB_GRAB_MODE_ASYNC, c.XCB_GRAB_MODE_ASYNC);
                self.key_handlers.putAssumeCapacity(.{ .keycode = key_code, .state = mod, .action = action }, func);

                if (presets.default.caps_eqls_shift) {
                    mod ^= @truncate(@as(c_uint, @intCast(c.XCB_MOD_MASK_SHIFT | c.XCB_MOD_MASK_LOCK)));
                    _ = c.xcb_grab_key(self.conn, 1, self.screen.root, mod, key_code, c.XCB_GRAB_MODE_ASYNC, c.XCB_GRAB_MODE_ASYNC);
                    self.key_handlers.putAssumeCapacity(.{ .keycode = key_code, .state = mod, .action = action }, func);

                    mod = @truncate(key_mod ^ (c.XCB_MOD_MASK_SHIFT | c.XCB_MOD_MASK_LOCK));
                    _ = c.xcb_grab_key(self.conn, 1, self.screen.root, mod, key_code, c.XCB_GRAB_MODE_ASYNC, c.XCB_GRAB_MODE_ASYNC);
                    self.key_handlers.putAssumeCapacity(.{ .keycode = key_code, .state = mod, .action = action }, func);
                }
            } else if (presets.default.caps_eqls_shift) {
                const mod: u16 = @truncate(key_mod ^ (c.XCB_MOD_MASK_SHIFT | c.XCB_MOD_MASK_LOCK));
                _ = c.xcb_grab_key(self.conn, 1, self.screen.root, mod, key_code, c.XCB_GRAB_MODE_ASYNC, c.XCB_GRAB_MODE_ASYNC);
                self.key_handlers.putAssumeCapacity(.{ .keycode = key_code, .state = mod, .action = action }, func);
            }
        }
        _ = c.xcb_flush(self.conn);
    }
    errdefer self.key_handlers.deinit(allocator);

    return self;
}
pub fn deinit(self: *Self) void {
    c.xcb_disconnect(self.conn);
    self.key_handlers.deinit(self.allocator);
    self.allocator.destroy(self);
}
