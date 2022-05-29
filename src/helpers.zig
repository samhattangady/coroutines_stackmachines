const std = @import("std");
const c = @import("platform.zig");

const constants = @import("constants.zig");
pub const PI = std.math.pi;
pub const HALF_PI = PI / 2.0;
pub const TWO_PI = PI * 2.0;
const TESSELATION_DEBUG = true;

pub const Vector2 = struct {
    const Self = @This();
    x: f32 = 0.0,
    y: f32 = 0.0,

    pub fn lerp(v1: Vector2, v2: Vector2, t: f32) Vector2 {
        return Vector2{
            .x = lerpf(v1.x, v2.x, t),
            .y = lerpf(v1.y, v2.y, t),
        };
    }

    /// We assume that v lies along the line v1-v2 (can be outside the segment)
    /// So we don't check both x and y unlerp. We just return the first one that we find.
    pub fn unlerp(v1: Vector2, v2: Vector2, v: Vector2) f32 {
        if (v1.x != v2.x) {
            return unlerpf(v1.x, v2.x, v.x);
        } else if (v1.y != v2.y) {
            return unlerpf(v1.y, v2.y, v.y);
        } else {
            return 0;
        }
    }

    pub fn ease(v1: Vector2, v2: Vector2, t: f32) Vector2 {
        return Vector2{
            .x = easeinoutf(v1.x, v2.x, t),
            .y = easeinoutf(v1.y, v2.y, t),
        };
    }

    pub fn add(v1: Vector2, v2: Vector2) Vector2 {
        return Vector2{
            .x = v1.x + v2.x,
            .y = v1.y + v2.y,
        };
    }

    pub fn added(v1: *const Vector2, v2: Vector2) Vector2 {
        return Vector2.add(v1.*, v2);
    }

    pub fn add3(v1: Vector2, v2: Vector2, v3: Vector2) Vector2 {
        return Vector2{
            .x = v1.x + v2.x + v3.x,
            .y = v1.y + v2.y + v3.y,
        };
    }

    pub fn subtract(v1: Vector2, v2: Vector2) Vector2 {
        return Vector2{
            .x = v1.x - v2.x,
            .y = v1.y - v2.y,
        };
    }

    pub fn subtracted(v1: *const Vector2, v2: Vector2) Vector2 {
        return Vector2.subtract(v1.*, v2);
    }

    pub fn distance(v1: Vector2, v2: Vector2) f32 {
        return @sqrt(((v2.x - v1.x) * (v2.x - v1.x)) + ((v2.y - v1.y) * (v2.y - v1.y)));
    }

    pub fn distance_sqr(v1: Vector2, v2: Vector2) f32 {
        return ((v2.x - v1.x) * (v2.x - v1.x)) + ((v2.y - v1.y) * (v2.y - v1.y));
    }

    pub fn distance_to_sqr(v1: *const Vector2, v2: Vector2) f32 {
        return ((v2.x - v1.x) * (v2.x - v1.x)) + ((v2.y - v1.y) * (v2.y - v1.y));
    }

    pub fn length(v1: Vector2) f32 {
        return @sqrt((v1.x * v1.x) + (v1.y * v1.y));
    }

    pub fn length_sqr(v1: Vector2) f32 {
        return (v1.x * v1.x) + (v1.y * v1.y);
    }

    pub fn scale(v1: Vector2, t: f32) Vector2 {
        return Vector2{
            .x = v1.x * t,
            .y = v1.y * t,
        };
    }

    pub fn scaled(v1: *const Vector2, t: f32) Vector2 {
        return Vector2{
            .x = v1.x * t,
            .y = v1.y * t,
        };
    }

    pub fn scale_anchor(v1: *const Vector2, anchor: Vector2, f: f32) Vector2 {
        const translated = Vector2.subtract(v1.*, anchor);
        return Vector2.add(anchor, Vector2.scale(translated, f));
    }

    pub fn scale_vec(v1: Vector2, v2: Vector2) Vector2 {
        return Vector2{
            .x = v1.x * v2.x,
            .y = v1.y * v2.y,
        };
    }

    pub fn negated(v1: *const Vector2) Vector2 {
        return Vector2{
            .x = -v1.x,
            .y = -v1.y,
        };
    }

    pub fn subtract_half(v1: Vector2, v2: Vector2) Vector2 {
        return Vector2{
            .x = v1.x - (0.5 * v2.x),
            .y = v1.y - (0.5 * v2.y),
        };
    }

    pub fn normalize(v1: Vector2) Vector2 {
        const l = Vector2.length(v1);
        return Vector2{
            .x = v1.x / l,
            .y = v1.y / l,
        };
    }

    /// Gives the clockwise angle in radians from first vector to second vector
    /// Assumes vectors are normalized
    pub fn angle_cw(v1: Vector2, v2: Vector2) f32 {
        std.debug.assert(!v1.is_nan());
        std.debug.assert(!v2.is_nan());
        const dot_product = std.math.clamp(Vector2.dot(v1, v2), -1, 1);
        var a = std.math.acos(dot_product);
        std.debug.assert(!is_nanf(a));
        const winding = Vector2.cross_z(v1, v2);
        std.debug.assert(!is_nanf(winding));
        if (winding < 0) a = TWO_PI - a;
        return a;
    }

    pub fn dot(v1: Vector2, v2: Vector2) f32 {
        std.debug.assert(!is_nanf(v1.x));
        std.debug.assert(!is_nanf(v1.y));
        std.debug.assert(!is_nanf(v2.x));
        std.debug.assert(!is_nanf(v2.y));
        return v1.x * v2.x + v1.y * v2.y;
    }

    /// Returns the z element of the 3d cross product of the two vectors. Useful to find the
    /// winding of the points
    pub fn cross_z(v1: Vector2, v2: Vector2) f32 {
        return (v1.x * v2.y) - (v1.y * v2.x);
    }

    pub fn equals(v1: Vector2, v2: Vector2) bool {
        return v1.x == v2.x and v1.y == v2.y;
    }

    pub fn is_equal(v1: *const Vector2, v2: Vector2) bool {
        return v1.x == v2.x and v1.y == v2.y;
    }

    pub fn is_equal_to(v1: *const Vector2, v2: Vector2) bool {
        return v1.x == v2.x and v1.y == v2.y;
    }

    pub fn reflect(v1: Vector2, surface: Vector2) Vector2 {
        // Since we're reflecting off the surface, we first need to find the component
        // of v1 that is perpendicular to the surface. We then need to "reverse" that
        // component. Or we can just subtract double the negative of that from v1.
        // TODO (25 Apr 2021 sam): See if this can be done without normalizing. @@Performance
        const n_surf = Vector2.normalize(surface);
        const v1_par = Vector2.scale(n_surf, Vector2.dot(v1, n_surf));
        const v1_perp = Vector2.subtract(v1, v1_par);
        return Vector2.subtract(v1, Vector2.scale(v1_perp, 2.0));
    }

    pub fn from_int(x: i32, y: i32) Vector2 {
        return Vector2{ .x = @intToFloat(f32, x), .y = @intToFloat(f32, y) };
    }

    pub fn from_usize(x: usize, y: usize) Vector2 {
        return Vector2{ .x = @intToFloat(f32, x), .y = @intToFloat(f32, y) };
    }

    pub fn rotate(v: Vector2, a: f32) Vector2 {
        const cosa = @cos(a);
        const sina = @sin(a);
        return Vector2{
            .x = (cosa * v.x) - (sina * v.y),
            .y = (sina * v.x) + (cosa * v.y),
        };
    }

    pub fn rotate_deg(v: Vector2, d: f32) Vector2 {
        const a = d * std.math.pi / 180.0;
        const cosa = @cos(a);
        const sina = @sin(a);
        return Vector2{
            .x = (cosa * v.x) - (sina * v.y),
            .y = (sina * v.x) + (cosa * v.y),
        };
    }

    /// If we have a line v1-v2, where v1 is 0 and v2 is 1, this function
    /// returns what value the point p has. It is assumed that p lies along
    /// the line.
    pub fn get_fraction(v1: Vector2, v2: Vector2, p: Vector2) f32 {
        const len = Vector2.distance(v1, v2);
        const p_len = Vector2.distance(v1, p);
        return p_len / len;
    }

    pub fn rotate_about_point(v1: Vector2, anchor: Vector2, a: f32) Vector2 {
        const adjusted = Vector2.subtract(v1, anchor);
        const rotated = Vector2.rotate(adjusted, a);
        return Vector2.add(anchor, rotated);
    }

    pub fn rotate_about_point_deg(v1: Vector2, anchor: Vector2, a: f32) Vector2 {
        const adjusted = Vector2.subtract(v1, anchor);
        const rotated = Vector2.rotate_deg(adjusted, a);
        return Vector2.add(anchor, rotated);
    }

    pub fn is_zero(v1: *const Vector2) bool {
        return v1.x == 0 and v1.y == 0;
    }

    pub fn is_nan(v1: *const Vector2) bool {
        return is_nanf(v1.x) or is_nanf(v1.y);
    }

    pub fn get_perp(v1: Vector2, v2: Vector2) Vector2 {
        const line = Vector2.subtract(v2, v1);
        const perp = Vector2.normalize(Vector2{ .x = line.y, .y = -line.x });
        return perp;
    }
};

pub const Vector2i = struct {
    x: i32,
    y: i32,
};

pub const Camera = struct {
    const Self = @This();
    size_updated: bool = true,
    origin: Vector2 = .{},
    window_size: Vector2 = .{ .x = constants.DEFAULT_WINDOW_WIDTH * constants.DEFAULT_USER_WINDOW_SCALE, .y = constants.DEFAULT_WINDOW_HEIGHT * constants.DEFAULT_USER_WINDOW_SCALE },
    zoom_factor: f32 = 1.0,
    window_scale: f32 = constants.DEFAULT_USER_WINDOW_SCALE,
    // This is used to store the window scale in case the user goes full screen and wants
    // to come back to windowed.
    user_window_scale: f32 = constants.DEFAULT_USER_WINDOW_SCALE,

    pub fn world_pos_to_screen(self: *const Self, pos: Vector2) Vector2 {
        const tmp1 = Vector2.subtract(pos, self.origin);
        // TODO (20 Oct 2021 sam): Why is this zoom_factor? and not combined
        return Vector2.scale(tmp1, self.zoom_factor);
    }

    pub fn screen_pos_to_world(self: *const Self, pos: Vector2) Vector2 {
        // TODO (10 Jun 2021 sam): I wish I knew why this were the case. But I have no clue. Jiggle and
        // test method got me here for the most part.
        // pos goes from (0,0) to (x,y) where x and y are the actual screen
        // sizes. (pixel size on screen as per OS)
        // we need to map this to a rect where the 0,0 maps to origin
        // and x,y maps to origin + w/zoom*scale
        const scaled = Vector2.scale(pos, 1.0 / (self.zoom_factor * self.combined_zoom()));
        return Vector2.add(scaled, self.origin);
    }

    pub fn render_size(self: *const Self) Vector2 {
        // TODO (27 Apr 2021 sam): See whether this causes any performance issues? Is it better to store
        // as a member variable, or is it okay to calculate as a method everytime? @@Performance
        return Vector2.scale(self.window_size, 1.0 / self.combined_zoom());
    }

    pub fn combined_zoom(self: *const Self) f32 {
        return self.zoom_factor * self.window_scale;
    }

    pub fn world_size_to_screen(self: *const Self, size: Vector2) Vector2 {
        return Vector2.scale(size, self.zoom_factor);
    }

    pub fn screen_size_to_world(self: *const Self, size: Vector2) Vector2 {
        return Vector2.scale(size, 1.0 / (self.zoom_factor * self.zoom_factor));
    }

    // TODO (10 May 2021 sam): There is some confusion here when we move from screen to world. In some
    // cases, we want to maintain the positions for rendering, in which case we need the zoom_factor
    // squared. In other cases, we don't need that. This is a little confusing to me, so we need to
    // sort it all out properly.
    // (02 Jun 2021 sam): I think it has something to do with window_scale and combined_zoom as well.
    // In some cases, we want to use zoom factor, in other cases, combined_zoom, and that needs to be
    // properly understood as well.
    pub fn screen_vec_to_world(self: *const Self, size: Vector2) Vector2 {
        return Vector2.scale(size, 1.0 / self.zoom_factor);
    }

    pub fn ui_pos_to_world(self: *const Self, pos: Vector2) Vector2 {
        const scaled = Vector2.scale(pos, 1.0 / (self.zoom_factor * self.zoom_factor));
        return Vector2.add(scaled, self.origin);
    }

    pub fn world_units_to_screen(self: *const Self, unit: f32) f32 {
        return unit * self.zoom_factor;
    }

    pub fn screen_units_to_world(self: *const Self, unit: f32) f32 {
        return unit / self.zoom_factor;
    }
};

pub const Vector2_gl = extern struct {
    x: c.GLfloat = 0.0,
    y: c.GLfloat = 0.0,
};

pub const Vector3_gl = extern struct {
    x: c.GLfloat = 0.0,
    y: c.GLfloat = 0.0,
    z: c.GLfloat = 0.0,
};

pub const Vector4_gl = extern struct {
    const Self = @This();
    x: c.GLfloat = 0.0,
    y: c.GLfloat = 0.0,
    z: c.GLfloat = 0.0,
    w: c.GLfloat = 0.0,

    pub fn lerp(v1: Vector4_gl, v2: Vector4_gl, t: f32) Vector4_gl {
        return Vector4_gl{
            .x = lerpf(v1.x, v2.x, t),
            .y = lerpf(v1.y, v2.y, t),
            .z = lerpf(v1.z, v2.z, t),
            .w = lerpf(v1.w, v2.w, t),
        };
    }

    pub fn equals(v1: Vector4_gl, v2: Vector4_gl) bool {
        return v1.x == v2.x and v1.y == v2.y and v1.z == v2.z and v1.w == v2.w;
    }

    /// Returns black and white version of the color
    pub fn bw(v1: *const Vector4_gl) Vector4_gl {
        const col = (v1.x + v1.y + v1.z) / 3.0;
        return Vector4_gl{
            .x = col,
            .y = col,
            .z = col,
            .w = v1.w,
        };
    }

    pub fn with_alpha(v1: *const Vector4_gl, a: f32) Vector4_gl {
        return Vector4_gl{ .x = v1.x, .y = v1.y, .z = v1.z, .w = a };
    }

    pub fn is_equal_to(v1: *const Vector4_gl, v2: Vector4_gl) bool {
        return Vector4_gl.equals(v1.*, v2);
    }

    pub fn json_serialize(self: *const Self, js: *JsonSerializer) !void {
        try js.beginObject();
        try js.objectField("x");
        try js.emitNumber(self.x);
        try js.objectField("y");
        try js.emitNumber(self.y);
        try js.objectField("z");
        try js.emitNumber(self.z);
        try js.objectField("w");
        try js.emitNumber(self.w);
        try js.endObject();
    }

    pub fn json_load(self: *Self, js: std.json.Value) void {
        self.x = @floatCast(f32, js.Object.get("x").?.Float);
        self.y = @floatCast(f32, js.Object.get("y").?.Float);
        self.z = @floatCast(f32, js.Object.get("z").?.Float);
        self.w = @floatCast(f32, js.Object.get("w").?.Float);
    }
};

pub fn lerpf(start: f32, end: f32, t: f32) f32 {
    return (start * (1.0 - t)) + (end * t);
}

pub fn unlerpf(start: f32, end: f32, t: f32) f32 {
    // TODO (09 Jun 2021 sam): This should work even if start > end
    if (end == t) return 1.0;
    return (t - start) / (end - start);
}

pub fn is_nanf(f: f32) bool {
    return f != f;
}

pub fn easeinoutf(start: f32, end: f32, t: f32) f32 {
    // Bezier Blend as per StackOverflow : https://stackoverflow.com/a/25730573/5453127
    // t goes between 0 and 1.
    const x = t * t * (3.0 - (2.0 * t));
    return start + ((end - start) * x);
}

pub const SingleInput = struct {
    is_down: bool = false,
    is_clicked: bool = false, // For one frame when key is pressed
    is_released: bool = false, // For one frame when key is released
    down_from: u32 = 0,

    pub fn reset(self: *SingleInput) void {
        self.is_clicked = false;
        self.is_released = false;
    }

    pub fn set_down(self: *SingleInput, ticks: u32) void {
        self.is_down = true;
        self.is_clicked = true;
        self.down_from = ticks;
    }

    pub fn set_release(self: *SingleInput) void {
        self.is_down = false;
        self.is_released = true;
    }
};

pub const MouseButton = enum {
    left,
    right,
    middle,

    pub fn from_js(b: i32) MouseButton {
        return switch (b) {
            0 => .left,
            1 => .middle,
            2 => .right,
            else => .left,
        };
    }
};

pub const MouseEventType = enum {
    button_up,
    button_down,
    scroll,
    movement,
};

pub const MouseEvent = union(MouseEventType) {
    button_up: MouseButton,
    button_down: MouseButton,
    scroll: i32,
    movement: Vector2i,
};

pub const MouseState = struct {
    const Self = @This();
    current_pos: Vector2 = .{},
    previous_pos: Vector2 = .{},
    l_down_pos: Vector2 = .{},
    r_down_pos: Vector2 = .{},
    m_down_pos: Vector2 = .{},
    l_button: SingleInput = .{},
    r_button: SingleInput = .{},
    m_button: SingleInput = .{},
    wheel_y: i32 = 0,

    pub fn reset_mouse(self: *Self) void {
        self.previous_pos = self.current_pos;
        self.l_button.reset();
        self.r_button.reset();
        self.m_button.reset();
        self.wheel_y = 0;
    }

    pub fn l_single_pos_click(self: *Self) bool {
        if (self.l_button.is_released == false) return false;
        if (self.l_down_pos.distance_to_sqr(self.current_pos) == 0) return true;
        return false;
    }

    pub fn l_moved(self: *Self) bool {
        return (self.l_down_pos.distance_to_sqr(self.current_pos) > 0);
    }

    pub fn movement(self: *Self) Vector2 {
        return Vector2.subtract(self.previous_pos, self.current_pos);
    }

    pub fn handle_input(self: *Self, event: c.SDL_Event, ticks: u32, camera: *Camera) void {
        switch (event.@"type") {
            c.SDL_MOUSEBUTTONDOWN, c.SDL_MOUSEBUTTONUP => {
                const button = switch (event.button.button) {
                    c.SDL_BUTTON_LEFT => &self.l_button,
                    c.SDL_BUTTON_RIGHT => &self.r_button,
                    c.SDL_BUTTON_MIDDLE => &self.m_button,
                    else => &self.l_button,
                };
                const pos = switch (event.button.button) {
                    c.SDL_BUTTON_LEFT => &self.l_down_pos,
                    c.SDL_BUTTON_RIGHT => &self.r_down_pos,
                    c.SDL_BUTTON_MIDDLE => &self.m_down_pos,
                    else => &self.l_down_pos,
                };
                if (event.@"type" == c.SDL_MOUSEBUTTONDOWN) {
                    // This specific line just feels a bit off. I don't intuitively get it yet.
                    pos.* = self.current_pos;
                    self.l_down_pos = self.current_pos;
                    button.is_down = true;
                    button.is_clicked = true;
                    button.down_from = ticks;
                }
                if (event.@"type" == c.SDL_MOUSEBUTTONUP) {
                    button.is_down = false;
                    button.is_released = true;
                }
            },
            c.SDL_MOUSEWHEEL => {
                self.wheel_y = event.wheel.y;
            },
            c.SDL_MOUSEMOTION => {
                self.current_pos = camera.screen_pos_to_world(Vector2.from_int(event.motion.x, event.motion.y));
            },
            else => {},
        }
    }

    pub fn web_handle_input(self: *Self, event: MouseEvent, ticks: u32, camera: *Camera) void {
        switch (event) {
            .button_down, .button_up => |but| {
                const button = switch (but) {
                    .left => &self.l_button,
                    .right => &self.r_button,
                    .middle => &self.m_button,
                };
                const pos = switch (but) {
                    .left => &self.l_down_pos,
                    .right => &self.r_down_pos,
                    .middle => &self.m_down_pos,
                };
                if (event == .button_down) {
                    // This specific line just feels a bit off. I don't intuitively get it yet.
                    pos.* = self.current_pos;
                    self.l_down_pos = self.current_pos;
                    button.is_down = true;
                    button.is_clicked = true;
                    button.down_from = ticks;
                }
                if (event == .button_up) {
                    button.is_down = false;
                    button.is_released = true;
                }
            },
            .scroll => |amount| {
                self.wheel_y = amount;
            },
            .movement => |pos| {
                self.current_pos = camera.screen_pos_to_world(Vector2.from_int(pos.x, pos.y));
            },
        }
    }
};

pub const EditableText = struct {
    const Self = @This();
    text: std.ArrayList(u8),
    is_active: bool = false,
    position: Vector2 = .{},
    size: Vector2 = .{ .x = 300 },
    cursor_index: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .text = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn set_text(self: *Self, str: []const u8) void {
        self.text.shrinkRetainingCapacity(0);
        self.text.appendSlice(str) catch unreachable;
        self.cursor_index = str.len;
    }

    pub fn deinit(self: *Self) void {
        self.text.deinit();
    }

    pub fn handle_inputs(self: *Self, keys: []u8) void {
        for (keys) |k| {
            switch (k) {
                8 => {
                    if (self.cursor_index > 0) {
                        _ = self.text.orderedRemove(self.cursor_index - 1);
                        self.cursor_index -= 1;
                    }
                },
                127 => {
                    if (self.cursor_index < self.text.items.len) {
                        _ = self.text.orderedRemove(self.cursor_index);
                    }
                },
                128 => {
                    if (self.cursor_index > 0) {
                        self.cursor_index -= 1;
                    }
                },
                129 => {
                    if (self.cursor_index < self.text.items.len) {
                        self.cursor_index += 1;
                    }
                },
                else => {
                    self.text.insert(self.cursor_index, k) catch unreachable;
                    self.cursor_index += 1;
                },
            }
        }
    }
};

// We load multiple fonts into the same texture, but the API doesn't process that perfectly,
// and treats it as a smaller / narrower texture instead. So we have to wrangle the t0 and t1
// values a little bit.
pub fn tex_remap(y_in: f32, y_height: usize, y_padding: usize) f32 {
    const pixel = @floatToInt(usize, y_in * @intToFloat(f32, y_height));
    const total_height = y_height + y_padding;
    return @intToFloat(f32, pixel + y_padding) / @intToFloat(f32, total_height);
}

pub fn debug_print(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
}

pub const WasmText = extern struct {
    text: [*]const u8,
    len: u32,
};

pub fn handle_text(str: [:0]const u8) if (constants.WEB_BUILD) WasmText else [:0]const u8 {
    if (constants.WEB_BUILD) {
        return WasmText{ .text = str.ptr, .len = @intCast(u32, str.len) };
    } else {
        return str;
    }
}

const JSON_SERIALIZER_MAX_DEPTH = 32;
pub const JsonWriter = std.io.Writer(*JsonStream, JsonStreamError, JsonStream.write);
pub const JsonStreamError = error{JsonWriteError};
pub const JsonSerializer = std.json.WriteStream(JsonWriter, JSON_SERIALIZER_MAX_DEPTH);
pub const JsonStream = struct {
    const Self = @This();
    buffer: std.ArrayList(u8),

    pub fn new(allocator: std.mem.Allocator) Self {
        return Self{
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    pub fn writer(self: *Self) JsonWriter {
        return .{ .context = self };
    }

    pub fn write(self: *Self, bytes: []const u8) JsonStreamError!usize {
        self.buffer.appendSlice(bytes) catch unreachable;
        return bytes.len;
    }

    pub fn save_data_to_file(self: *Self, filepath: []const u8) !void {
        // TODO (08 Dec 2021 sam): See whether we want to add a hash or base64 encoding
        const file = try std.fs.cwd().createFile(filepath, .{});
        defer file.close();
        _ = try file.writeAll(self.buffer.items);
        if (false) {
            debug_print("saving to file {s}\n", .{filepath});
        }
    }

    pub fn serializer(self: *Self) JsonSerializer {
        return std.json.writeStream(self.writer(), JSON_SERIALIZER_MAX_DEPTH);
    }
};

// TODO (12 May 2022 sam): Check if std has anything for this?
fn c_strlen(str: [*]const u8) usize {
    c.console_log("checking ctrlen");
    c.console_log(str);
    var size: usize = 0;
    while (true) : (size += 1) {
        if (str[size] == 0) break;
    }
    return size;
}

/// this reads the file into a buffer alloced by allocator. data to be freed by the
/// caller.
pub fn read_file_contents(path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (!constants.WEB_BUILD) {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const file_size = try file.getEndPos();
        const data = try file.readToEndAlloc(allocator, file_size);
        return data;
    } else {
        const raw_size = c.readWebFileSize(path.ptr);
        if (raw_size < 0) {
            return error.FileNotFound;
        }
        const size = @intCast(usize, raw_size);
        {
            var buffer: [100]u8 = undefined;
            const message = std.fmt.bufPrint(&buffer, "contents_size = {d}", .{size}) catch unreachable;
            c.consoleLogS(message.ptr, message.len);
        }
        var data = try allocator.alloc(u8, size + 1);
        {
            var i: usize = 0;
            while (i < size) : (i += 1) {
                data[i] = '_';
            }
            data[size] = 0;
        }
        c.consoleLogS(data.ptr, data.len - 1);
        const success = c.readWebFile(path.ptr, data.ptr, size);
        if (!success) {
            // not success.
            return error.FileReadFailed;
        }
        c.console_log(data.ptr);
        return data;
    }
}

/// this reads the file into a buffer alloced by allocator. data to be freed by the
/// caller.
/// writable file data is saved in html5 storage on web,
pub fn read_writable_file_contents(path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (!constants.WEB_BUILD) {
        return read_file_contents(path, allocator);
    } else {
        const raw_size = c.readStorageFileSize(path.ptr);
        if (raw_size < 0) {
            return error.FileNotFound;
        }
        const size = @intCast(usize, raw_size);
        var data = try allocator.alloc(u8, size + 1);
        data[size] = 0;
        const success = c.readStorageFile(path.ptr, data.ptr, size);
        if (!success) {
            // not success.
            return error.FileReadFailed;
        }
        return data;
    }
}

/// writable file data is saved in html5 storage on web,
pub fn write_writable_file_contents(path: []const u8, contents: []const u8) !void {
    if (!constants.WEB_BUILD) {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        _ = try file.writeAll(contents);
    } else {
        // TODO (16 May 2022 sam): do the error handling?
        _ = c.writeStorageFile(path.ptr, contents.ptr);
    }
}

pub fn point_in_bounding_box(p1: Vector2, bounding_box: [2]Vector2) bool {
    const minx = bounding_box[0].x;
    const miny = bounding_box[0].y;
    const maxx = bounding_box[1].x;
    const maxy = bounding_box[1].y;
    return (p1.x >= minx and p1.x <= maxx and p1.y >= miny and p1.y <= maxy);
}

pub fn line_segment_in_bounding_box(p1: Vector2, p2: Vector2, bounding_box: [2]Vector2) bool {
    // If either (or both) point is in the box, then yes, it is inside... duh.
    return (point_in_bounding_box(p1, bounding_box) or point_in_bounding_box(p2, bounding_box));
}

pub fn x_ray_line_segment_intersects(point: Vector2, p1: Vector2, p2: Vector2) bool {
    // Specfically pick a random angle so that we don't have issues. axis alignment seems to cause issues.
    const other = Vector2.add(point, Vector2{ .x = 109340, .y = 123543 });
    if (line_segments_intersect(point, other, p1, p2)) |_| {
        return true;
    }
    return false;
}

pub fn line_segments_intersect(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) ?Vector2 {
    // sometimes it looks like single points are being passed in
    if (Vector2.equals(p1, p2) and Vector2.equals(p2, p3) and Vector2.equals(p3, p4)) {
        debug_print("same point check here...\n", .{});
        return p1;
    }
    if (Vector2.equals(p1, p2) or Vector2.equals(p3, p4)) {
        // debug_print("both lines are points...\n", .{});
        return null;
    }
    const t = ((p1.x - p3.x) * (p3.y - p4.y)) - ((p1.y - p3.y) * (p3.x - p4.x));
    const u = ((p2.x - p1.x) * (p1.y - p3.y)) - ((p2.y - p1.y) * (p1.x - p3.x));
    const d = ((p1.x - p2.x) * (p3.y - p4.y)) - ((p1.y - p2.y) * (p3.x - p4.x));
    // TODO (24 Apr 2021 sam): There is an performance improvement here where the division is not
    // necessary. Be careful of the negative signs when figuring that all out.  @@Performance
    const td = t / d;
    const ud = u / d;
    if (td >= 0.0 and td <= 1.0 and ud >= 0.0 and ud <= 1.0) {
        var s = t / d;
        if (d == 0) {
            s = 0;
            debug_print("nan intersection -> {d},{d} - {d},{d} and {d},{d} - {d},{d}\n", .{ p1.x, p1.y, p2.x, p2.y, p3.x, p3.y, p4.x, p4.y });
        }
        return Vector2{
            .x = p1.x + s * (p2.x - p1.x),
            .y = p1.y + s * (p2.y - p1.y),
        };
    } else {
        return null;
    }
}

// TODO (23 Jun 2021 sam): Pass in which field of T contains the position value, and figure out
// how to use that.
/// Tesselates vertices of type T. T needs to have a .position field, The allocator should be an
/// arena allocator, as this function will not deallocate the memory it creates. It expects the
/// caller to handle all of that.
/// TODO (22 Jun 2021 sam): Use this in Shape. It needs an extra allocator though, and maybe that's
/// not the best thing (though to be fair, there are already a couple of lists in there that need
/// allocation, so maybe an allocator is useful in any case)
pub fn tesselate_vertices(comptime T: type, vertices: *std.ArrayList(T), indices: *std.ArrayList(c_uint), allocator: std.mem.Allocator) void {
    indices.clearRetainingCapacity();
    debug_print("tesselating\t", .{});
    switch (vertices.items.len) {
        0, 1, 2 => {
            return;
        },
        3 => {
            indices.appendSlice(&[3]c_uint{ 0, 1, 2 }) catch unreachable;
        },
        else => {
            // TODO (17 May 2021 sam): Move to Monotone polygon tesselation. @@Performance
            // Ear Clipping Algorithm.
            var verts = std.ArrayList(c_uint).initCapacity(allocator, vertices.items.len) catch unreachable;
            defer verts.deinit();
            var polygon = std.ArrayList(Vector2).initCapacity(allocator, vertices.items.len) catch unreachable;
            defer polygon.deinit();
            for (vertices.items) |v, i| {
                verts.append(@intCast(c_uint, i)) catch unreachable;
                polygon.append(v.position) catch unreachable;
            }
            // Variable to control for infinite loops.
            var k: usize = 0;
            while (verts.items.len > 3) : (k += 1) {
                // To prevent infinite loops.
                if (k > 15) {
                    if (TESSELATION_DEBUG) debug_print("tessellation wala infinite loop\n", .{});
                    break;
                }
                for (verts.items) |_, j| {
                    if (j + 2 >= verts.items.len) break;
                    const j1 = @intCast(c_uint, j);
                    const j2 = if (j1 + 1 >= verts.items.len) ((j1 + 1) - verts.items.len) else j1 + 1;
                    const j3 = if (j1 + 2 >= verts.items.len) ((j1 + 2) - verts.items.len) else j1 + 2;
                    std.debug.assert(j1 < verts.items.len);
                    std.debug.assert(j2 < verts.items.len);
                    std.debug.assert(j3 < verts.items.len);
                    const v0 = vertices.items[verts.items[j1]].position;
                    // const v1 = vertices.items[verts.items[j2]].position;
                    const v2 = vertices.items[verts.items[j3]].position;
                    // if v0-v2 lies inside the shape, then this is a ear. We can the clip it,
                    // remove v1 from the vertices, and continue
                    if (line_segment_in_polygon(v0, v2, polygon.items)) {
                        indices.appendSlice(&[3]c_uint{ verts.items[j1], verts.items[j2], verts.items[j3] }) catch unreachable;
                        _ = verts.orderedRemove(j2);
                        k = 0;
                        // break;
                    }
                }
            }
            std.debug.assert(verts.items.len >= 3);
            indices.appendSlice(&[3]c_uint{ verts.items[0], verts.items[1], verts.items[2] }) catch unreachable;
        },
    }
    debug_print("done -> {any}\n", .{indices.items});
}

/// Checks that a line_segment is entirely inside the shape. Meant to be used as an
/// internal diagonal check, so if the two points are also part of the polygon and
/// the line is inside the shape, it will return true.
pub fn line_segment_in_polygon(p1: Vector2, p2: Vector2, polygon: []Vector2) bool {
    // We select points slightly inside the line segment in case we are checking
    // points that are part of the polygon
    const q1 = Vector2.lerp(p1, p2, 0.01);
    const q2 = Vector2.lerp(p1, p2, 0.99);
    // There will be no intersections even if the line is fully outside the shape,
    // so we just check a random point to make sure that we don't have that false positive
    const mid = Vector2.lerp(p1, p2, 0.3145);
    if (!point_in_polygon(mid, polygon)) {
        return false;
    }
    var j: usize = 0;
    while (j < polygon.len) : (j += 1) {
        const k = if (j == polygon.len - 1) 0 else j + 1;
        const v1 = polygon[j];
        const v2 = polygon[k];
        if (line_segments_intersect(q1, q2, v1, v2)) |_| {
            return false;
        }
    }
    return true;
}

/// Returns whether a point lies inside of the shape
/// Using ray casting method = https://en.wikipedia.org/wiki/Point_in_polygon
// TODO (01 May 2021 sam): There are some edge cases that we're not yet taken care of
pub fn point_in_polygon(point: Vector2, polygon: []const Vector2) bool {
    var max_x: f32 = -100000;
    var max_y: f32 = -100000;
    var min_x: f32 = 100000;
    var min_y: f32 = 100000;
    for (polygon) |vert| {
        max_x = std.math.max(vert.x, max_x);
        max_y = std.math.max(vert.y, max_y);
        min_x = std.math.min(vert.x, min_x);
        min_y = std.math.min(vert.y, min_y);
    }
    if (!point_in_bounding_box(point, .{ .{ .x = min_x, .y = min_y }, .{ .x = max_x, .y = max_y } })) return false;
    var intersections: usize = 0;
    var i: usize = 0;
    while (i < polygon.len) : (i += 1) {
        const j = if (i == polygon.len - 1) 0 else i + 1;
        if (x_ray_line_segment_intersects(point, polygon[i], polygon[j])) {
            intersections += 1;
        }
    }
    return (intersections % 2 != 0);
}
