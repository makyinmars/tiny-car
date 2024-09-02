const std = @import("std");
const rl = @import("raylib");

const MAX_BUILDINGS = 100;

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

pub const Item = struct {
    x: f32,
    y: f32,
    item_type: u32,

    // Create a new Item with given position and category
    pub fn new(x: f32, y: f32, item_type: u32) Item {
        return Item{
            .x = x,
            .y = y,
            .item_type = item_type,
        };
    }

    // Draw the Item based on its category
    pub fn draw(self: *const Item) void {
        if (self.item_type == 0) {
            // Draw a green circle to represent a tree
            rl.drawCircleV(rl.Vector2{ .x = self.x, .y = self.y }, 10, Color.new(0, 128, 0, 255).toRaylibColor());
        } else if (self.item_type == 1) {
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

    rl.initWindow(screenWidth, screenHeight, "Tiny Car Game");
    defer rl.closeWindow(); // Close window and OpenGL context
    //

    var player = Car.new("Sky", Color.new(173, 216, 230, 255), 5.0, 400.0, 280.0);
    var buildings: [MAX_BUILDINGS]struct { image: rl.Image, position: rl.Vector2 } = undefined;
    // var buildColors: [MAX_BUILDINGS]rl.Color = undefined;

    var building_textures: [3]rl.Texture2D = undefined;
    building_textures[0] = rl.loadTexture("resources/textures/cyberpunk_street_background.png");
    building_textures[1] = rl.loadTexture("resources/textures/cyberpunk_street_midground.png");
    building_textures[2] = rl.loadTexture("resources/textures/cyberpunk_street_foreground.png");
    defer {
        for (building_textures) |texture| {
            rl.unloadTexture(texture);
        }
    }

    var spacing: i32 = 0;

    // Initialize buildings and their colors
    for (0..buildings.len) |i| {
        const texture_index = rl.getRandomValue(0, 2);
        buildings[i].image = rl.loadImageFromTexture(building_textures[texture_index]);
        buildings[i].position = rl.Vector2{
            .x = @as(f32, @floatFromInt(-6000 + spacing)),
            .y = @as(f32, @floatFromInt(screenHeight - 130 - rl.getRandomValue(100, 300))),
        };
        spacing += @as(i32, @intFromFloat(buildings[i].image.width));
        // // Set random width and height for each building
        // buildings[i].width = @as(f32, @floatFromInt(rl.getRandomValue(50, 200)));
        // buildings[i].height = @as(f32, @floatFromInt(rl.getRandomValue(100, 800)));
        //
        // // Position buildings vertically, leaving space at the bottom
        // buildings[i].y = screenHeight - 130 - buildings[i].height;
        //
        // // Position buildings horizontally, starting from -6000 and spacing them out
        // buildings[i].x = @as(f32, @floatFromInt(-6000 + spacing));
        //
        // // Increase spacing for the next building
        // spacing += @as(i32, @intFromFloat(buildings[i].width));
        //
        // // Assign a random color to each building
        // buildColors[i] = rl.Color{
        //     .r = @as(u8, @intCast(rl.getRandomValue(200, 240))),
        //     .g = @as(u8, @intCast(rl.getRandomValue(200, 240))),
        //     .b = @as(u8, @intCast(rl.getRandomValue(200, 250))),
        //     .a = 255,
        // };
    }

    // Potential improvements:
    // 1. Use a more diverse color palette for buildings
    // 2. Vary building types (e.g., add some taller, narrower buildings)
    // 3. Implement a more sophisticated spacing algorithm to prevent overlaps
    // 4. Add some randomness to the vertical positioning of buildings
    // 5. Consider using a seed for random generation to create reproducible layouts

    var camera = rl.Camera2D{
        .target = rl.Vector2{ .x = player.x + 20, .y = player.y + 20 },
        .offset = rl.Vector2{ .x = screenWidth / 2, .y = screenHeight / 2 },
        .rotation = 0,
        .zoom = 1,
    };

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        if (rl.isKeyDown(rl.KeyboardKey.key_l)) {
            player.moveRight();
            for (0..buildings.len) |i| {
                buildings[i].x -= player.speed;
            }
        } else if (rl.isKeyDown(rl.KeyboardKey.key_h)) {
            player.moveLeft();
            for (0..buildings.len) |i| {
                buildings[i].x += player.speed;
            }
        }

        if (rl.isKeyDown(rl.KeyboardKey.key_k)) {
            player.moveUp();
        } else if (rl.isKeyDown(rl.KeyboardKey.key_j)) {
            player.moveDown();
        }

        if (rl.isKeyDown(rl.KeyboardKey.key_right)) {
            player.x += 2;
        } else if (rl.isKeyDown(rl.KeyboardKey.key_left)) {
            player.x -= 2;
        }

        // Camera target follows player
        camera.target = rl.Vector2.init(player.x + 20, player.y + 20);

        // Camera rotation controls
        if (rl.isKeyDown(rl.KeyboardKey.key_a)) {
            camera.rotation -= 1;
        } else if (rl.isKeyDown(rl.KeyboardKey.key_s)) {
            camera.rotation += 1;
        }

        // Limit camera rotation to 80 degrees (-40 to 40)
        camera.rotation = rl.math.clamp(camera.rotation, -40, 40);

        // Camera zoom controls
        camera.zoom += rl.getMouseWheelMove() * 0.05;

        camera.zoom = rl.math.clamp(camera.zoom, 0.1, 3.0);

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.ray_white);

        {
            rl.beginMode2D(camera);
            defer rl.endMode2D();

            rl.drawRectangle(-6000, 320, 13000, 8000, rl.Color.dark_gray);

            for (buildings) |building| {
                rl.drawTextureV(rl.loadTextureFromImage(building.image), building.position, rl.Color.white);
            }

            // Draw car body
            rl.drawRectangleV(rl.Vector2{ .x = player.x - 15, .y = player.y - 20 }, rl.Vector2{ .x = 30, .y = 40 }, player.color.toRaylibColor());
            // Draw car roof
            rl.drawTriangle(rl.Vector2{ .x = player.x - 15, .y = player.y - 20 }, rl.Vector2{ .x = player.x + 15, .y = player.y - 20 }, rl.Vector2{ .x = player.x, .y = player.y - 30 }, player.color.toRaylibColor());
        }

        rl.drawText("SCREEN AREA", 640, 10, 20, rl.Color.red);

        rl.drawRectangle(0, 0, screenWidth, 5, rl.Color.red);
        rl.drawRectangle(0, 5, 5, screenHeight - 10, rl.Color.red);
        rl.drawRectangle(screenWidth - 5, 5, 5, screenHeight - 10, rl.Color.red);
        rl.drawRectangle(0, screenHeight - 5, screenWidth, 5, rl.Color.red);

        rl.drawRectangle(10, 10, 250, 113, rl.fade(rl.Color.sky_blue, 0.5));
        rl.drawRectangleLines(10, 10, 250, 113, rl.Color.blue);

        rl.drawText("Free 2d camera controls:", 20, 20, 10, rl.Color.black);
        rl.drawText("- Right/Left to move Offset", 40, 40, 10, rl.Color.dark_gray);
        rl.drawText("- Mouse Wheel to Zoom in-out", 40, 60, 10, rl.Color.dark_gray);
        rl.drawText("- A / S to Rotate", 40, 80, 10, rl.Color.dark_gray);
        rl.drawText("- R to reset Zoom and Rotation", 40, 100, 10, rl.Color.dark_gray);
    }
}
