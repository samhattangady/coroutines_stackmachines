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
    new_shape_group,
    new_shape,
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
        self.handle_mouse_inputs();
    }

    pub fn handle_mouse_inputs(self: *Self) void {
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
