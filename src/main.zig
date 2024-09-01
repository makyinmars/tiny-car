const std = @import("std");
const rl = @import("raylib");

const keyboard = rl.KeyboardKey;
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

// Structure to represent a car
pub const Car = struct {
    name: []const u8,
    color: Color,
    speed: f32,
    x: f32,
    y: f32,

    pub fn new(name: []const u8, color: Color, speed: f32, x: f32, y: f32) Car {
        return Car{
            .name = name,
            .color = color,
            .speed = speed,
            .x = x,
            .y = y,
        };
    }

    pub fn moveUp(self: *Car) void {
        self.y -= self.speed;
    }

    pub fn moveDown(self: *Car) void {
        self.y += self.speed;
    }

    pub fn moveLeft(self: *Car) void {
        self.x -= self.speed;
    }

    pub fn moveRight(self: *Car) void {
        self.x += self.speed;
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
    //

    // Initialize car
    var skyCar = Car.new("Sky", Color.new(173, 216, 230, 255), 5.0, 100.0, 100.0);

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

        rl.drawCircleV(rl.Vector2{ .x = skyCar.x, .y = skyCar.y }, 20, skyCar.color.toRaylibColor());
        rl.drawText(@ptrCast(skyCar.name), 20, 20, 10, rl.Color.black);

        //----------------------------------------------------------------------------------
    }
}
