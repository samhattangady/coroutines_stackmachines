const std = @import("std");
const c = @import("platform.zig");
const constants = @import("constants.zig");

const glyph_lib = @import("glyphee.zig");
const TypeSetter = glyph_lib.TypeSetter;

const shapes = @import("shapes.zig");
const ShapeGroup = shapes.ShapeGroup;
const Shape = shapes.Shape;

const helpers = @import("helpers.zig");
const Vector2 = helpers.Vector2;
const Camera = helpers.Camera;
const SingleInput = helpers.SingleInput;
const MouseState = helpers.MouseState;
const EditableText = helpers.EditableText;
const TYPING_BUFFER_SIZE = 16;
const DOUBLE_CLICK_TICKS = 200;
const MAX_NUM_COROUTINES = 128;
const DEBUG_COROUTINES = true;
const SUPER_DEBUG_COROUTINES = DEBUG_COROUTINES and false;
const SUPER_DEBUG_COROUTINES2 = DEBUG_COROUTINES and false;

const InputKey = enum {
    shift,
    tab,
    enter,
    space,
    escape,
    ctrl,
};
const INPUT_KEYS_COUNT = @typeInfo(InputKey).Enum.fields.len;
const InputMap = struct {
    key: c.SDL_Keycode,
    input: InputKey,
};

const INPUT_MAPPING = [_]InputMap{
    .{ .key = c.SDLK_LSHIFT, .input = .shift },
    .{ .key = c.SDLK_LCTRL, .input = .ctrl },
    .{ .key = c.SDLK_TAB, .input = .tab },
    .{ .key = c.SDLK_RETURN, .input = .enter },
    .{ .key = c.SDLK_SPACE, .input = .space },
    .{ .key = c.SDLK_ESCAPE, .input = .escape },
};

pub const InputState = struct {
    const Self = @This();
    keys: [INPUT_KEYS_COUNT]SingleInput = [_]SingleInput{.{}} ** INPUT_KEYS_COUNT,
    mouse: MouseState = MouseState{},
    typed: [TYPING_BUFFER_SIZE]u8 = [_]u8{0} ** TYPING_BUFFER_SIZE,
    num_typed: usize = 0,

    pub fn get_key(self: *Self, key: InputKey) *SingleInput {
        return &self.keys[@enumToInt(key)];
    }

    pub fn type_key(self: *Self, k: u8) void {
        if (self.num_typed >= TYPING_BUFFER_SIZE) {
            helpers.debug_print("Typing buffer already filled.\n", .{});
            return;
        }
        self.typed[self.num_typed] = k;
        self.num_typed += 1;
    }

    pub fn reset(self: *Self) void {
        for (self.keys) |*key| key.reset();
        self.mouse.reset_mouse();
        self.num_typed = 0;
    }
};

const State = enum {
    neutral,
    group_clicked,
    group_dragged,
    group_selected,
    shape_clicked,
    shape_dragged,
    shape_selected,
};

const Coroutine = struct {
    frame: anyframe = undefined,
    data: []u8 = undefined,
    name: []const u8 = undefined,
    used: bool = false,
    done: bool = false,
};
const CoroutineStack = struct {
    const Self = @This();
    coroutines: []Coroutine,
    allocator: std.mem.Allocator,
    stack_size: usize = 0,
    // TODO (17 Dec 2021 sam): Keep a count of how many coros are touched / dirty / used
    // We don't want to keep looping through all every single frame @@Performance

    pub fn init(allocator: std.mem.Allocator) Self {
        // We use a fixed allocation because we don't want to be dealing with pointer updates
        // if we have to grow the stack at any point.
        var coroutines = allocator.alloc(Coroutine, MAX_NUM_COROUTINES) catch unreachable;
        for (coroutines) |*coro| {
            coro.used = false;
            coro.done = false;
        }
        return Self{
            .coroutines = coroutines,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.coroutines) |*coro| {
            if (coro.used) self.allocator.free(coro.data);
        }
        self.allocator.free(self.coroutines);
    }

    pub fn new_coroutine(self: *Self, comptime function: anytype) *Coroutine {
        var coro: *Coroutine = undefined;
        var out_of_space = false;
        for (self.coroutines) |*coroutine, i| {
            if (coroutine.used and i == MAX_NUM_COROUTINES - 1) out_of_space = true;
            if (coroutine.used) continue;
            if (i > self.stack_size) self.stack_size = i;
            coro = coroutine;
            break;
        }
        if (out_of_space) {
            unreachable; // we tried to add too many stacks onto the coroutine stack.
        }
        coro.data = self.allocator.allocAdvanced(u8, @alignOf(@Frame(function)), @sizeOf(@Frame(function)), .at_least) catch unreachable;
        coro.used = true;
        coro.done = false;
        return coro;
    }

    pub fn cleanup(self: *Self) void {
        for (self.coroutines) |*coroutine, i| {
            if (coroutine.done) {
                coroutine.used = false;
                coroutine.done = false;
                self.allocator.free(coroutine.data);
            }
            if (i > self.stack_size) break;
            // TODO (20 Dec 2021 sam): Shrink the stack_size when requried.
        }
    }
};

pub const App = struct {
    const Self = @This();
    typesetter: TypeSetter = undefined,
    camera: Camera = .{},
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    ticks: u32 = 0,
    quit: bool = false,
    position: Vector2 = .{},
    inputs: InputState = .{},
    load_data: []u8 = undefined,
    groups: std.ArrayList(ShapeGroup),
    coroutines: CoroutineStack = undefined,
    active_coroutine: ?anyframe = null,
    state: State = .neutral,
    last_click_ticks: u32 = 0,
    last_group_offset: Vector2 = .{},
    last_group_index: ?usize = null,
    active_group_index: ?usize = null,
    last_shape_offset: Vector2 = .{},
    last_shape_index: ?usize = null,
    active_shape_index: ?usize = null,

    pub fn new(allocator: std.mem.Allocator, arena: std.mem.Allocator) Self {
        return Self{
            .groups = std.ArrayList(ShapeGroup).init(allocator),
            .allocator = allocator,
            .arena = arena,
        };
    }

    pub fn init(self: *Self) !void {
        try self.typesetter.init(&self.camera, self.allocator);
        self.coroutines = CoroutineStack.init(self.allocator);
        {
            {
                var group = ShapeGroup.init(self.allocator);
                {
                    var shape = Shape.init(self.allocator);
                    shape.add_vertex_pos(.{ .x = 100, .y = 100 });
                    shape.add_vertex_pos(.{ .x = -100, .y = 100 });
                    shape.add_vertex_pos(.{ .x = -100, .y = -70 });
                    shape.add_vertex_pos(.{ .x = 100, .y = -100 });
                    shape.position = .{ .x = 100, .y = 200 };
                    shape.color = .{ .x = 0.7, .y = 0.7, .z = 0.3, .w = 1.0 };
                    group.add_shape(shape);
                }
                group.tesselate(self.arena);
                group.position = .{ .x = 50, .y = 100 };
                self.groups.append(group) catch unreachable;
            }
            {
                var group = ShapeGroup.init(self.allocator);
                {
                    var shape = Shape.init(self.allocator);
                    shape.add_vertex_pos(.{ .x = 50, .y = 50 });
                    shape.add_vertex_pos(.{ .x = -50, .y = 50 });
                    shape.add_vertex_pos(.{ .x = -50, .y = -70 });
                    shape.add_vertex_pos(.{ .x = 50, .y = -50 });
                    shape.position = .{ .x = 160, .y = 250 };
                    shape.color = .{ .x = 0.7, .y = 0.4, .z = 0.4, .w = 1.0 };
                    group.add_shape(shape);
                }
                {
                    var shape = Shape.init(self.allocator);
                    shape.add_vertex_pos(.{ .x = 50, .y = 30 });
                    shape.add_vertex_pos(.{ .x = -50, .y = 70 });
                    shape.add_vertex_pos(.{ .x = -50, .y = -50 });
                    shape.add_vertex_pos(.{ .x = 50, .y = -50 });
                    shape.position = .{ .x = 100, .y = 200 };
                    shape.color = .{ .x = 0.4, .y = 0.4, .z = 0.7, .w = 1.0 };
                    group.add_shape(shape);
                }
                group.tesselate(self.arena);
                group.position = .{ .x = 250, .y = 200 };
                self.groups.append(group) catch unreachable;
            }
        }
    }

    pub fn deinit(self: *Self) void {
        for (self.groups.items) |*group| group.deinit();
        self.groups.deinit();
        self.typesetter.deinit();
        self.coroutines.deinit();
    }

    pub fn handle_inputs(self: *Self, event: c.SDL_Event) void {
        if (event.@"type" == c.SDL_KEYDOWN and event.key.keysym.sym == c.SDLK_END)
            self.quit = true;
        self.inputs.mouse.handle_input(event, self.ticks, &self.camera);
        if (event.@"type" == c.SDL_KEYDOWN) {
            for (INPUT_MAPPING) |map| {
                if (event.key.keysym.sym == map.key) self.inputs.get_key(map.input).set_down(self.ticks);
            }
        } else if (event.@"type" == c.SDL_KEYUP) {
            for (INPUT_MAPPING) |map| {
                if (event.key.keysym.sym == map.key) self.inputs.get_key(map.input).set_release();
            }
        }
    }

    pub fn update(self: *Self, ticks: u32, arena: std.mem.Allocator) void {
        self.ticks = ticks;
        self.arena = arena;
        const prev_state = self.state;
        self.handle_mouse_inputs_coroutines();
        if (prev_state != self.state) helpers.debug_print("state change from {s} to {s}\n", .{ @tagName(prev_state), @tagName(self.state) });
    }

    pub fn handle_mouse_inputs_coroutines(self: *Self) void {
        if (self.active_coroutine) |frame| {
            if (SUPER_DEBUG_COROUTINES2) {
                // not the most effecient, but can work if required...
                for (self.coroutines.coroutines) |coro| {
                    if (coro.frame == frame) std.debug.print("in {s}\n", .{coro.name});
                }
            }
            resume frame;
        } else {
            // this is the behaviour of .neutral state. If we want, we can make it a coroutine as well...
            if (self.inputs.mouse.l_button.is_clicked) {
                const mouse_pos = self.inputs.mouse.current_pos;
                var index: ?usize = null;
                for (self.groups.items) |group, i| {
                    if (group.contains_point(mouse_pos)) {
                        // we don't break because we want to repect z ordering.
                        index = i;
                    }
                }
                if (index) |i| {
                    const offset = mouse_pos.subtracted(self.groups.items[i].position).negated();
                    var coro = self.coroutines.new_coroutine(Self.group_clicked_mode);
                    var bytes = @alignCast(@alignOf(@Frame(Self.group_clicked_mode)), coro.data);
                    _ = @asyncCall(bytes, {}, self.group_clicked_mode, .{ coro, i, offset });
                }
            }
        }
    }

    // This doesn't compile -> error: runtime value cannot be passed to comptime arg
    // syntax sugar...
    fn start_coroutine(self: *Self, fn_def: anytype, func: anytype, data: anytype) void {
        var coro = self.coroutines.new_coroutine(fn_def);
        var bytes = @alignCast(@alignOf(@Frame(fn_def)), coro.data);
        // TODO (31 May 2022 sam): How can we pass in coro along with the data that we are being passed?
        // self.coro = coro; // ugly.
        _ = @asyncCall(bytes, {}, func, data);
    }

    inline fn debug_enter_coroutine(self: *Self, str: []const u8) void {
        _ = self;
        if (DEBUG_COROUTINES) helpers.debug_print("entering {s}\n", .{str});
    }

    inline fn debug_leave_coroutine(self: *Self, str: []const u8) void {
        _ = self;
        if (DEBUG_COROUTINES) helpers.debug_print("leaving  {s}\n", .{str});
    }

    fn group_clicked_mode(self: *Self, coro: *Coroutine, group_index: usize, offset: Vector2) void {
        // if we move the mouse while it is still down, we are dragging the group
        // if we click again without moving in the timeframe, we are selecting the group
        // if we do neither, and the timeframe passed, we go back to neutral.
        self.debug_enter_coroutine(@src().fn_name);
        defer self.debug_leave_coroutine(@src().fn_name);
        const prev_coro = self.active_coroutine;
        defer self.active_coroutine = prev_coro;
        defer coro.done = true;
        coro.frame = @frame();
        coro.name = @src().fn_name;
        self.active_coroutine = @frame();
        const last_click_ticks = self.ticks;
        while (true) {
            suspend {}
            if (SUPER_DEBUG_COROUTINES) std.debug.print("in {s}\n", .{@src().fn_name});
            if (!self.inputs.mouse.l_moved() and self.inputs.mouse.l_button.is_clicked and (self.ticks - last_click_ticks) < DOUBLE_CLICK_TICKS) {
                var new_coro = self.coroutines.new_coroutine(Self.group_selected_mode);
                var bytes = @alignCast(@alignOf(@Frame(Self.group_selected_mode)), new_coro.data);
                _ = @asyncCall(bytes, {}, self.group_selected_mode, .{ new_coro, group_index });
            } else if (self.inputs.mouse.l_moved() and self.inputs.mouse.l_button.is_down) {
                var new_coro = self.coroutines.new_coroutine(Self.group_dragged_mode);
                var bytes = @alignCast(@alignOf(@Frame(Self.group_dragged_mode)), new_coro.data);
                _ = @asyncCall(bytes, {}, self.group_dragged_mode, .{ new_coro, group_index, offset });
            } else if (self.ticks - last_click_ticks > DOUBLE_CLICK_TICKS) {
                // we are still in this state, and not clicked again in time, go back to neutral
                break;
            }
        }
    }

    fn group_dragged_mode(self: *Self, coro: *Coroutine, group_index: usize, offset: Vector2) void {
        // if we release the mouse, go back to neutral.
        // if we move the mouse, move the group
        self.debug_enter_coroutine(@src().fn_name);
        defer self.debug_leave_coroutine(@src().fn_name);
        const prev_coro = self.active_coroutine;
        defer self.active_coroutine = prev_coro;
        defer coro.done = true;
        coro.frame = @frame();
        coro.name = @src().fn_name;
        self.active_coroutine = @frame();
        while (true) {
            suspend {}
            if (SUPER_DEBUG_COROUTINES) std.debug.print("in {s}\n", .{@src().fn_name});
            const mouse_pos = self.inputs.mouse.current_pos;
            const group = &self.groups.items[group_index];
            if (self.inputs.mouse.l_button.is_down) {
                // move the group to the mouse position
                group.position = mouse_pos.added(offset);
                group.recalculate_bounding_box();
            } else {
                // we have released the mouse, go back to neutral
                break;
            }
        }
    }

    fn group_selected_mode(self: *Self, coro: *Coroutine, group_index: usize) void {
        // if we click outside the bounds of the active_group, go back to neutral
        // if we click on a shape in bounds, go to shape_clicked
        self.debug_enter_coroutine(@src().fn_name);
        defer self.debug_leave_coroutine(@src().fn_name);
        const prev_coro = self.active_coroutine;
        defer self.active_coroutine = prev_coro;
        defer coro.done = true;
        coro.frame = @frame();
        coro.name = @src().fn_name;
        self.active_coroutine = @frame();
        self.groups.items[group_index].set_active(true);
        // we benefit from cleanups with defer.
        defer self.groups.items[group_index].set_active(false);
        const group = &self.groups.items[group_index];
        while (true) {
            suspend {}
            if (SUPER_DEBUG_COROUTINES) std.debug.print("in {s}\n", .{@src().fn_name});
            const mouse_pos = self.inputs.mouse.current_pos;
            if (self.inputs.mouse.l_button.is_clicked) {
                if (!group.contains_point(mouse_pos)) {
                    // clicked outside bounds. go back to neutral
                    break;
                } else {
                    // if we click on a shape, go to shape_clicked
                    var index: ?usize = null;
                    for (group.shapes.items) |shape, i| {
                        if (shape.contains_point(mouse_pos.subtracted(group.position))) {
                            index = i;
                        }
                    }
                    if (index) |i| {
                        const offset = mouse_pos.subtracted(group.shapes.items[i].position).negated();
                        var new_coro = self.coroutines.new_coroutine(Self.shape_clicked_mode);
                        var bytes = @alignCast(@alignOf(@Frame(Self.shape_clicked_mode)), new_coro.data);
                        _ = @asyncCall(bytes, {}, self.shape_clicked_mode, .{ new_coro, group_index, i, offset });
                    }
                }
            }
        }
    }

    fn shape_clicked_mode(self: *Self, coro: *Coroutine, group_index: usize, shape_index: usize, offset: Vector2) void {
        // if we click again without moving in the timeframe, shape_selected
        // if we move the mouse without releasing the go to dragging
        // if we wait for too long, go back to group_selected
        self.debug_enter_coroutine(@src().fn_name);
        defer self.debug_leave_coroutine(@src().fn_name);
        const prev_coro = self.active_coroutine;
        defer self.active_coroutine = prev_coro;
        defer coro.done = true;
        coro.frame = @frame();
        coro.name = @src().fn_name;
        self.active_coroutine = @frame();
        const last_click_ticks = self.ticks;
        const group = &self.groups.items[group_index];
        const shape = &group.shapes.items[shape_index];
        _ = shape;
        while (true) {
            suspend {}
            if (SUPER_DEBUG_COROUTINES) std.debug.print("in {s}\n", .{@src().fn_name});
            if (!self.inputs.mouse.l_moved() and self.inputs.mouse.l_button.is_clicked and (self.ticks - last_click_ticks) < DOUBLE_CLICK_TICKS) {
                var new_coro = self.coroutines.new_coroutine(Self.shape_selected_mode);
                var bytes = @alignCast(@alignOf(@Frame(Self.shape_selected_mode)), new_coro.data);
                _ = @asyncCall(bytes, {}, self.shape_selected_mode, .{ new_coro, group_index, shape_index });
            } else if (self.inputs.mouse.l_moved() and self.inputs.mouse.l_button.is_down) {
                var new_coro = self.coroutines.new_coroutine(Self.shape_dragged_mode);
                var bytes = @alignCast(@alignOf(@Frame(Self.shape_dragged_mode)), new_coro.data);
                _ = @asyncCall(bytes, {}, self.shape_dragged_mode, .{ new_coro, group_index, shape_index, offset });
            } else if (self.ticks - last_click_ticks > DOUBLE_CLICK_TICKS) {
                // we are still in this state, and not clicked again in time, go back to neutral
                break;
            }
        }
    }

    fn shape_dragged_mode(self: *Self, coro: *Coroutine, group_index: usize, shape_index: usize, offset: Vector2) void {
        // if we release the mouse, go back to neutral.
        // if we move the mouse, move the group
        self.debug_enter_coroutine(@src().fn_name);
        defer self.debug_leave_coroutine(@src().fn_name);
        const prev_coro = self.active_coroutine;
        defer self.active_coroutine = prev_coro;
        defer coro.done = true;
        coro.frame = @frame();
        coro.name = @src().fn_name;
        self.active_coroutine = @frame();
        while (true) {
            suspend {}
            if (SUPER_DEBUG_COROUTINES) std.debug.print("in {s}\n", .{@src().fn_name});
            const mouse_pos = self.inputs.mouse.current_pos;
            const group = &self.groups.items[group_index];
            const shape = &group.shapes.items[shape_index];
            if (self.inputs.mouse.l_button.is_down) {
                // move the group to the mouse position
                shape.position = mouse_pos.added(offset);
                group.recalculate_bounding_box();
            } else {
                // we have released the mouse, go back to neutral
                break;
            }
        }
    }

    fn shape_selected_mode(self: *Self, coro: *Coroutine, group_index: usize, shape_index: usize) void {
        // if we click outside the bounds of the active_group, go back to neutral
        // if we click on a shape in bounds, go to shape_clicked
        self.debug_enter_coroutine(@src().fn_name);
        defer self.debug_leave_coroutine(@src().fn_name);
        const prev_coro = self.active_coroutine;
        defer self.active_coroutine = prev_coro;
        defer coro.done = true;
        coro.frame = @frame();
        coro.name = @src().fn_name;
        self.active_coroutine = @frame();
        self.groups.items[group_index].shapes.items[shape_index].set_active(true);
        // we benefit from cleanups with defer.
        defer self.groups.items[group_index].shapes.items[shape_index].set_active(false);
        const group = &self.groups.items[group_index];
        const shape = &group.shapes.items[shape_index];
        while (true) {
            suspend {}
            if (SUPER_DEBUG_COROUTINES) std.debug.print("in {s}\n", .{@src().fn_name});
            const mouse_pos = self.inputs.mouse.current_pos;
            if (self.inputs.mouse.l_button.is_clicked) {
                if (!shape.contains_point(mouse_pos)) {
                    // clicked outside shape. deselect shape
                    break;
                } else {
                    // clicked in the shape.
                }
            }
        }
    }

    pub fn handle_mouse_inputs_state_machine(self: *Self) void {
        const mouse_pos = self.inputs.mouse.current_pos;
        defer {
            if (self.inputs.mouse.l_button.is_clicked) self.last_click_ticks = self.ticks;
        }
        switch (self.state) {
            .neutral => {
                // if we click on a group, go to group_clicked
                if (self.inputs.mouse.l_button.is_clicked) {
                    var index: ?usize = null;
                    for (self.groups.items) |group, i| {
                        if (group.contains_point(mouse_pos)) {
                            // we don't break because we want to repect z ordering.
                            index = i;
                        }
                    }
                    if (index) |i| {
                        self.last_group_index = i;
                        self.last_group_offset = mouse_pos.subtracted(self.groups.items[i].position).negated();
                        self.state = .group_clicked;
                    }
                }
            },
            .group_clicked => {
                // if we move the mouse while it is still down, we are dragging the group
                // if we click again without moving in the timeframe, we are selecting the group
                // if we do neither, and the timeframe passed, we go back to neutral.
                std.debug.assert(self.last_group_index != null);
                const index = self.last_group_index.?;
                const group = &self.groups.items[index];
                _ = group;
                if (!self.inputs.mouse.l_moved() and self.inputs.mouse.l_button.is_clicked and (self.ticks - self.last_click_ticks) < DOUBLE_CLICK_TICKS) {
                    self.last_group_index = null;
                    self.active_group_index = index;
                    self.groups.items[index].set_active(true);
                    self.state = .group_selected;
                } else if (self.inputs.mouse.l_moved() and self.inputs.mouse.l_button.is_down) {
                    self.state = .group_dragged;
                } else if (self.ticks - self.last_click_ticks > DOUBLE_CLICK_TICKS) {
                    // we are still in this state, and not clicked again in time, go back to neutral
                    self.last_group_index = null;
                    self.state = .neutral;
                }
            },
            .group_dragged => {
                // if we release the mouse, go back to neutral.
                std.debug.assert(self.last_group_index != null);
                const index = self.last_group_index.?;
                const group = &self.groups.items[index];
                if (!self.inputs.mouse.l_button.is_down) {
                    // we have released the mouse, go back to neutral
                    self.last_group_index = null;
                    self.state = .neutral;
                } else {
                    // move the group to the mouse position
                    group.position = mouse_pos.added(self.last_group_offset);
                    group.recalculate_bounding_box();
                }
            },
            .group_selected => {
                // if we click outside the bounds of the active_group, go back to neutral
                // if we click on a shape in bounds, go to shape_clicked
                std.debug.assert(self.active_group_index != null);
                const agi = self.active_group_index.?;
                const group = &self.groups.items[agi];
                if (self.inputs.mouse.l_button.is_clicked) {
                    if (!group.contains_point(mouse_pos)) {
                        // clicked outside bounds. go back to neutral
                        group.set_active(false);
                        self.active_group_index = null;
                        self.state = .neutral;
                    } else {
                        // if we click on a shape, go to shape_clicked
                        var index: ?usize = null;
                        for (group.shapes.items) |shape, i| {
                            if (shape.contains_point(mouse_pos.subtracted(group.position))) {
                                index = i;
                            }
                        }
                        if (index) |i| {
                            self.last_shape_index = i;
                            self.state = .shape_clicked;
                            self.last_shape_offset = mouse_pos.subtracted(group.shapes.items[i].position).negated();
                        }
                    }
                }
            },
            .shape_clicked => {
                // if we click again without moving in the timeframe, shape_selected
                // if we move the mouse without releasing the go to dragging
                // if we wait for too long, go back to group_selected
                std.debug.assert(self.active_group_index != null);
                std.debug.assert(self.last_shape_index != null);
                const agi = self.active_group_index.?;
                const lsi = self.last_shape_index.?;
                const group = &self.groups.items[agi];
                const shape = &group.shapes.items[lsi];
                if (!self.inputs.mouse.l_moved() and self.inputs.mouse.l_button.is_clicked and (self.ticks - self.last_click_ticks) < DOUBLE_CLICK_TICKS) {
                    // shape is selected
                    self.last_shape_index = null;
                    self.active_shape_index = lsi;
                    shape.set_active(true);
                    self.state = .shape_selected;
                } else if (self.inputs.mouse.l_moved() and self.inputs.mouse.l_button.is_down) {
                    // shape is dragged
                    self.state = .shape_dragged;
                } else if (self.ticks - self.last_click_ticks > DOUBLE_CLICK_TICKS) {
                    // back to group_selected
                    self.last_shape_index = null;
                    self.state = .group_selected;
                }
            },
            .shape_dragged => {
                // if we release the mouse, go back to group_selected.
                std.debug.assert(self.active_group_index != null);
                std.debug.assert(self.last_shape_index != null);
                const agi = self.active_group_index.?;
                const lsi = self.last_shape_index.?;
                const group = &self.groups.items[agi];
                const shape = &group.shapes.items[lsi];
                if (!self.inputs.mouse.l_button.is_down) {
                    // we have released the mouse, go back to neutral
                    self.last_group_index = null;
                    self.state = .group_selected;
                } else {
                    // move the group to the mouse position
                    shape.position = mouse_pos.added(self.last_shape_offset);
                    group.recalculate_bounding_box();
                }
            },
            .shape_selected => {
                // if we click outside the bounds of the shape, go back to group_selected
                std.debug.assert(self.active_group_index != null);
                std.debug.assert(self.active_shape_index != null);
                const agi = self.active_group_index.?;
                const asi = self.active_shape_index.?;
                const group = &self.groups.items[agi];
                const shape = &group.shapes.items[asi];
                if (self.inputs.mouse.l_button.is_clicked) {
                    if (shape.contains_point(mouse_pos.subtracted(group.position))) {
                        // clicked in the shape
                    } else {
                        // clicked outside, deselect shape
                        shape.set_active(false);
                        self.active_shape_index = null;
                        self.state = .group_selected;
                    }
                }
            },
        }
    }

    pub fn handle_mouse_inputs_plain(self: *Self) void {
        const mouse_pos = self.inputs.mouse.current_pos;
        if (self.inputs.mouse.l_button.is_clicked) {
            defer self.last_click_ticks = self.ticks;
            if (self.active_group_index) |agi| {
                // a group is active
                const group = &self.groups.items[agi];
                if (group.bounding_box_contains_point(mouse_pos)) {
                    // we have clicked in the bounds of the active group
                    if (self.active_shape_index) |asi| {
                        _ = asi;
                        const shape = &group.shapes.items[asi];
                        if (shape.contains_point(mouse_pos.subtracted(group.position))) {
                            // the click was in the active shape
                        } else {
                            // the click was outside the active shape.
                            shape.set_active(false);
                            self.last_shape_index = null;
                            self.active_shape_index = null;
                        }
                    } else {
                        // see if we are double clicking or dragging a shape
                        var index: ?usize = null;
                        for (group.shapes.items) |shape, i| {
                            if (shape.contains_point(mouse_pos.subtracted(group.position))) {
                                index = i;
                            }
                        }
                        if (index) |i| {
                            defer {
                                self.last_shape_index = i;
                                self.last_shape_offset = self.inputs.mouse.current_pos.subtracted(group.shapes.items[i].position).negated();
                            }
                            // this click was on a shape. see if it was a double click.
                            if (self.last_shape_index) |lsi| {
                                if (lsi == i and (self.ticks - self.last_click_ticks) < DOUBLE_CLICK_TICKS) {
                                    self.active_shape_index = i;
                                    group.shapes.items[i].set_active(true);
                                }
                            }
                        } else {
                            // the current click was not on any shape
                            self.last_shape_index = null;
                            self.active_shape_index = null;
                        }
                    }
                } else {
                    // we have clicked outside the bounds of the active group
                    group.set_active(false);
                    self.active_group_index = null;
                    self.last_group_index = null;
                    self.active_shape_index = null;
                }
            } else {
                // no active group currently
                // see if we are double clicking or dragging a group
                var index: ?usize = null;
                for (self.groups.items) |group, i| {
                    if (group.contains_point(mouse_pos)) {
                        // we don't break because we want to repect z ordering.
                        index = i;
                    }
                }
                if (index) |i| {
                    defer {
                        self.last_group_index = i;
                        self.last_group_offset = self.inputs.mouse.current_pos.subtracted(self.groups.items[i].position).negated();
                    }
                    // this click was on a group. see if it was a double click.
                    if (self.last_group_index) |lgi| {
                        if (lgi == i and (self.ticks - self.last_click_ticks) < DOUBLE_CLICK_TICKS) {
                            self.active_group_index = i;
                            self.groups.items[i].set_active(true);
                        }
                    }
                } else {
                    // the current click was not on any group.
                    self.last_group_index = null;
                }
            }
        }
        if (self.inputs.mouse.l_button.is_down and self.inputs.mouse.l_moved()) {
            if (self.active_group_index) |agi| {
                const group = &self.groups.items[agi];
                if (self.last_shape_index) |lsi| {
                    // we are dragging around last_shape_index
                    group.shapes.items[lsi].position = mouse_pos.added(self.last_shape_offset);
                    group.recalculate_bounding_box();
                }
            } else {
                // no active group. so if there is a last_group_index, it means we should move that.
                if (self.last_group_index) |lgi| {
                    // we are dragging around last_group index
                    self.groups.items[lgi].position = mouse_pos.added(self.last_group_offset);
                } else {
                    // no last group index. So we should be creating a selection box.
                }
            }
        }
    }

    pub fn end_frame(self: *Self) void {
        self.inputs.reset();
    }
};
