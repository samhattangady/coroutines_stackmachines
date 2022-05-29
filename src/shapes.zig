// Shapes is the library for managing shapes and things related to that one.
const std = @import("std");
const c = @import("platform.zig");

const helpers = @import("helpers.zig");
const Vector2 = helpers.Vector2;
const Vector3 = helpers.Vector3;
const Vector4_gl = helpers.Vector4_gl;

// const colors = @import("colors.zig");

pub const Vertex = struct {
    position: Vector2 = .{},
};

pub const Shape = struct {
    const Self = @This();
    /// Position is relative to the ShapeGroup position
    position: Vector2 = .{},
    /// Vertices that create the shape. All vertices are relative to the Shape position
    vertices: std.ArrayList(Vertex),
    indices: std.ArrayList(c_uint),
    color: Vector4_gl = .{},
    is_active: bool = false,
    bounding_box: [2]Vector2 = [2]Vector2{ .{ .x = 100000, .y = 100000 }, .{ .x = -100000, .y = -100000 } },
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .vertices = std.ArrayList(Vertex).init(allocator),
            .indices = std.ArrayList(c_uint).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.vertices.deinit();
        self.indices.deinit();
    }

    pub fn add_vertex(self: *Self, vertex: Vertex) void {
        // If the same position is being added again, don't add it.
        if (self.vertices.items.len > 0) {
            const last_vertex = self.vertices.items[self.vertices.items.len - 1];
            if (last_vertex.position.is_equal(vertex.position)) return;
        }
        self.vertices.append(vertex) catch unreachable;
        self.bounding_box[0].x = std.math.min(self.bounding_box[0].x, vertex.position.x);
        self.bounding_box[0].y = std.math.min(self.bounding_box[0].y, vertex.position.y);
        self.bounding_box[1].x = std.math.max(self.bounding_box[1].x, vertex.position.x);
        self.bounding_box[1].y = std.math.max(self.bounding_box[1].y, vertex.position.y);
    }

    pub fn add_vertex_pos(self: *Self, pos: Vector2) void {
        self.add_vertex(.{ .position = pos });
    }

    pub fn set_active(self: *Self, active: bool) void {
        self.is_active = active;
    }

    /// Returns whether a point lies inside of the shape
    /// Using ray casting method = https://en.wikipedia.org/wiki/Point_in_polygon
    /// group_point is the position relative the the position of the ShapeGroup
    // TODO (01 May 2021 sam): There are some edge cases that we're not yet taken care of
    pub fn contains_point(self: *const Self, group_point: Vector2) bool {
        const point = Vector2.subtract(group_point, self.position);
        if (!helpers.point_in_bounding_box(point, self.bounding_box)) return false;
        var intersections: usize = 0;
        var i: usize = 0;
        while (i < self.vertices.items.len) : (i += 1) {
            // if a point is equal, it is not contained.
            if (point.is_equal_to(self.vertices.items[i].position)) return false;
            const j = if (i == self.vertices.items.len - 1) 0 else i + 1;
            if (helpers.x_ray_line_segment_intersects(point, self.vertices.items[i].position, self.vertices.items[j].position)) {
                intersections += 1;
            }
        }
        return (intersections % 2 != 0);
    }

    pub fn is_internal_diagonal(self: *Self, p1: Vector2, p2: Vector2) bool {
        // if it intersects with any of the lines, then it is not.
        const q1 = Vector2.lerp(p1, p2, 0.1);
        const q2 = Vector2.lerp(p1, p2, 0.9);
        const mid = Vector2.lerp(p1, p2, 0.3145);
        if (!self.contains_point(mid)) {
            return false;
        }
        var j: usize = 0;
        while (j < self.vertices.items.len) : (j += 1) {
            const k = if (j == self.vertices.items.len - 1) 0 else j + 1;
            const v1 = self.vertices.items[j].position;
            const v2 = self.vertices.items[k].position;
            if (helpers.line_segments_intersect(q1, q2, v1, v2)) |_| {
                return false;
            }
        }
        return true;
    }

    pub fn recalculate_bounding_box(self: *Self) void {
        var minx: f32 = 10000.0;
        var miny: f32 = 10000.0;
        var maxx: f32 = -10000.0;
        var maxy: f32 = -10000.0;
        for (self.vertices.items) |vertex| {
            minx = std.math.min(vertex.position.x, minx);
            maxx = std.math.max(vertex.position.x, maxx);
            miny = std.math.min(vertex.position.y, miny);
            maxy = std.math.max(vertex.position.y, maxy);
        }
        self.bounding_box[0] = .{ .x = minx, .y = miny };
        self.bounding_box[1] = .{ .x = maxx, .y = maxy };
    }

    pub fn set_position(self: *Self, position: Vector2) void {
        self.position = position;
        self.recalculate_bounding_box();
    }

    /// Returns the index of the closest vertex. Also returns the distance in the dist_sqr_ptr pointer.
    pub fn get_closest_vertex_distance(self: *const Self, group_point: Vector2, dist_sqr_ptr: *f32) usize {
        var closest_sqr: f32 = 10000000;
        var closest_idx: usize = 0;
        var i: usize = 0;
        const point = Vector2.subtract(group_point, self.position);
        while (i < self.vertices.items.len) : (i += 1) {
            const dist_sqr = point.distance_to_sqr(self.vertices.items[i].position);
            if (dist_sqr < closest_sqr) {
                closest_sqr = dist_sqr;
                closest_idx = i;
            }
        }
        dist_sqr_ptr.* = closest_sqr;
        return closest_idx;
    }

    /// Returns the closest point along the outline as well as the closest vertex (if sent in params)
    pub fn get_closest_point(self: *const Self, group_point: Vector2, vertex_index: ?*usize) Vector2 {
        var closest_dist: f32 = 10000000;
        var closest_idx: usize = 0;
        var closest_point = Vector2{};
        const point = Vector2.subtract(group_point, self.position);
        for (self.vertices.items) |_, i| {
            const j = if (i == self.vertices.items.len - 1) 0 else i + 1;
            const v1 = self.vertices.items[i].position;
            const v2 = self.vertices.items[j].position;
            const on_seg = point.closest_point_on_line_segment(v1, v2);
            const dist_sqr = point.distance_to_sqr(on_seg);
            if (dist_sqr < closest_dist) {
                closest_dist = dist_sqr;
                closest_idx = i;
                closest_point = on_seg;
            }
        }
        if (vertex_index) |index| index.* = closest_idx;
        return closest_point.added(self.position);
    }

    pub fn tesselate(self: *Self, arena: std.mem.Allocator) void {
        helpers.tesselate_vertices(Vertex, &self.vertices, &self.indices, arena);
    }
};

pub const ShapeGroup = struct {
    const Self = @This();
    shapes: std.ArrayList(Shape),
    is_active: bool = false,
    position: Vector2 = .{},
    bounding_box: [2]Vector2 = [2]Vector2{ .{ .x = 100000, .y = 100000 }, .{ .x = -100000, .y = -100000 } },
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .shapes = std.ArrayList(Shape).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.shapes.items) |*shape| shape.deinit();
        self.shapes.deinit();
    }

    pub fn add_shape(self: *Self, shape: Shape) void {
        self.shapes.append(shape) catch unreachable;
        self.recalculate_bounding_box();
    }

    pub fn set_active(self: *Self, active: bool) void {
        if (!active) {
            for (self.shapes.items) |*shape| shape.set_active(false);
        }
        self.is_active = active;
    }

    pub fn tesselate(self: *Self, arena: std.mem.Allocator) void {
        for (self.shapes.items) |*shape| shape.tesselate(arena);
    }

    /// Gets the index of the shape if we click on it. Additionally if shape_index is not null,
    /// we also check for the given shape_index, if we are within range of a vertex. This is
    /// so that we can move a vertex even when clicking outside of the shape.
    pub fn get_shape_index(self: *const Self, point: Vector2, shape_index: ?usize, range: f32) ?usize {
        if (shape_index) |si| {
            const index = self.get_shape_vertex_index(si, point, range);
            if (index != null) return si;
        }
        if (!helpers.point_in_bounding_box(point, self.bounding_box)) return null;
        var i = self.shapes.items.len - 1;
        while (true) : (i -= 1) {
            if (self.shapes.items[i].contains_point(point)) return i;
            if (i == 0) break;
        }
        return null;
    }

    pub fn get_shape_closest_point(self: *const Self, point: Vector2, shape_index: usize, vertex_index: ?*usize) Vector2 {
        std.debug.assert(shape_index < self.shapes.items.len);
        return self.shapes.items[shape_index].get_closest_point(point, vertex_index);
    }

    pub fn get_shape_vertex_index(self: *const Self, shape_index: usize, point: Vector2, range: f32) ?usize {
        std.debug.assert(shape_index < self.shapes.items.len);
        var dist_sqr: f32 = 0.0;
        const closest_vertex = self.shapes.items[shape_index].get_closest_vertex_distance(point, &dist_sqr);
        if (dist_sqr < (range * range)) {
            return closest_vertex;
        } else {
            return null;
        }
    }

    pub fn contains_point(self: *const Self, world_point: Vector2) bool {
        if (!self.bounding_box_contains_point(world_point)) return false;
        const point = world_point.subtracted(self.position);
        // TODO (08 Mar 2022 sam): Check bounding box here as well.
        return self.get_shape_index(point, null, 0) != null;
    }

    pub fn bounding_box_contains_point(self: *const Self, world_point: Vector2) bool {
        const point = world_point.subtracted(self.position);
        return helpers.point_in_bounding_box(point, self.bounding_box);
    }

    pub fn recalculate_bounding_box(self: *Self) void {
        var minx: f32 = 10000.0;
        var miny: f32 = 10000.0;
        var maxx: f32 = -10000.0;
        var maxy: f32 = -10000.0;
        for (self.shapes.items) |shape| {
            minx = std.math.min(shape.position.x + shape.bounding_box[0].x, minx);
            maxx = std.math.max(shape.position.x + shape.bounding_box[1].x, maxx);
            miny = std.math.min(shape.position.y + shape.bounding_box[0].y, miny);
            maxy = std.math.max(shape.position.y + shape.bounding_box[1].y, maxy);
        }
        self.bounding_box[0] = .{ .x = minx, .y = miny };
        self.bounding_box[1] = .{ .x = maxx, .y = maxy };
    }

    pub fn debug_print(self: *Self) void {
        helpers.debug_print("ShapeGroup has {d} shapes\n", .{self.shapes.items.len});
        for (self.shapes.items) |shape, i| {
            helpers.debug_print("  Shape {d} has {d} vertices\n", .{ i, shape.vertices.items.len });
            helpers.debug_print("  Color -> ({d}, {d}, {d}, {d})\n", .{ shape.color.x, shape.color.y, shape.color.z, shape.color.w });
            for (shape.vertices.items) |vertex, j| {
                helpers.debug_print("    vertex{d}: ({d}, {d})\n", .{ j, vertex.position.x, vertex.position.y });
            }
        }
    }
};
