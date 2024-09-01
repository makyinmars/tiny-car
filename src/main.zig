const std = @import("std");
const rl = @import("raylib");

const keyboard = rl.KeyboardKey;

// Structure to represent a car
pub const Car = struct {
    name: []const u8,
    color: Color,
    speed: f32,
    x: f32,
    y: f32,
    road: *const Road,

    pub fn new(name: []const u8, color: Color, speed: f32, x: f32, y: f32, road: *const Road) Car {
        return Car{
            .name = name,
            .color = color,
            .speed = speed,
            .x = x,
            .y = y,
            .road = road,
        };
    }

    pub fn moveUp(self: *Car) void {
        // Check if moving up would keep the car within the road's boundaries
        if (self.y - self.speed > self.road.y) {
            // Move the car up by subtracting the speed from its y-coordinate
            self.y -= self.speed;
        }
    }

    pub fn moveDown(self: *Car) void {
        // Check if moving down would keep the car within the road's boundaries
        if (self.y + self.speed < self.road.y + self.road.height) {
            // Move the car down by adding the speed to its y-coordinate
            self.y += self.speed;
        }
    }

    pub fn moveLeft(self: *Car) void {
        // Check if moving left would keep the car within the road's boundaries
        if (self.x - self.speed > self.road.x) {
            // Move the car left by subtracting the speed from its x-coordinate
            self.x -= self.speed;
        }
    }

    pub fn moveRight(self: *Car) void {
        // Check if moving right would keep the car within the road's boundaries
        if (self.x + self.speed < self.road.x + self.road.width) {
            // Move the car right by adding the speed to its x-coordinate
            self.x += self.speed;
        }
    }
};

// Structure to represent a color
pub const Color = struct {
    red: u8,
    green: u8,
    blue: u8,
    alpha: u8,

    pub fn new(red: u8, green: u8, blue: u8, alpha: u8) Color {
        return Color{
            .red = red,
            .green = green,
            .blue = blue,
            .alpha = alpha,
        };
    }

    pub fn toRaylibColor(self: *const Color) rl.Color {
        return rl.Color{
            .r = self.red,
            .g = self.green,
            .b = self.blue,
            .a = self.alpha,
        };
    }
};

pub const Road = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub fn new(x: f32, y: f32, width: f32, height: f32) Road {
        return Road{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        };
    }

    pub fn draw(self: *Road) void {
        rl.drawRectangleV(rl.Vector2{
            .x = self.x,
            .y = self.y,
        }, rl.Vector2{
            .x = self.x,
            .y = self.y,
        }, Color.new(100, 100, 100, 255).toRaylibColor());
    }
};

pub const Item = struct {
    x: f32,
    y: f32,
    itemType: u32,

    // Create a new Item with given position and category
    pub fn new(x: f32, y: f32, itemType: u32) Item {
        return Item{
            .x = x,
            .y = y,
            .itemType = itemType,
        };
    }

    // Draw the Item based on its category
    pub fn draw(self: *const Item) void {
        if (self.itemType == 0) {
            // Draw a green circle to represent a tree
            rl.drawCircleV(rl.Vector2{ .x = self.x, .y = self.y }, 10, Color.new(0, 128, 0, 255).toRaylibColor());
        } else if (self.itemType == 1) {
            // Draw a brown rectangle to represent a building
            rl.drawRectangleV(rl.Vector2{
                .x = self.x,
                .y = self.y,
            }, rl.Vector2{
                .x = self.x,
                .y = self.y,
            }, Color.new(128, 0, 0, 255).toRaylibColor());
        }
    }
};

pub fn main() anyerror!void {
    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 800;
    const screenHeight = 450;

    rl.initWindow(screenWidth, screenHeight, "raylib-zig [core] example - basic window");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    // Initialize road
    var mainRoad = Road.new(200.0, 100.0, 400.0, 200.0);

    // Initialize car
    var skyCar = Car.new("Sky", Color.new(173, 216, 230, 255), 5.0, 100.0, 100.0, &mainRoad);

    // Initialize items
    const items = [_]Item{
        Item.new(50.0, 150.0, 0), // Tree
        Item.new(650.0, 150.0, 0), // Tree
        Item.new(50.0, 250.0, 1), // Building
        Item.new(650.0, 250.0, 1), // Building
    };

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update

        if (rl.isKeyDown(keyboard.key_k)) {
            skyCar.moveUp();
        }

        if (rl.isKeyDown(keyboard.key_j)) {
            skyCar.moveDown();
        }

        if (rl.isKeyDown(keyboard.key_h)) {
            skyCar.moveLeft();
        }

        if (rl.isKeyDown(keyboard.key_l)) {
            skyCar.moveRight();
        }

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.light_gray);

        mainRoad.draw();
        for (items) |item| {
            item.draw();
        }

        rl.drawCircleV(rl.Vector2{ .x = skyCar.x, .y = skyCar.y }, 20, skyCar.color.toRaylibColor());
        rl.drawText(@ptrCast(skyCar.name), 20, 20, 10, rl.Color.black);

        //----------------------------------------------------------------------------------
    }
}
