const rl = @import("raylib.zig");
const std = @import("std");

// Define Car struct
const Car = struct {
    texture: rl.Texture2D,
    position: rl.Vector2,
    speed: i32,
};

// Define Pear struct
const Pear = struct {
    position: rl.Vector2,
    velocity: rl.Vector2,
    lifetime: f32,
};

const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 640;

fn drawGrassTexture(texture: rl.Texture2D, offset: f32, side: enum { Left, Right }) void {
    const x = if (side == .Left) 0 else @as(f32, @floatFromInt(@divFloor(SCREEN_WIDTH * 2, 3)));
    rl.DrawTextureRec(texture, rl.Rectangle{ .x = 0, .y = offset, .width = @as(f32, @floatFromInt(@divFloor(SCREEN_WIDTH, 3))), .height = @as(f32, @floatFromInt(SCREEN_HEIGHT)) }, rl.Vector2{ .x = x, .y = -offset }, rl.WHITE);
    rl.DrawTextureRec(texture, rl.Rectangle{ .x = 0, .y = 0, .width = @as(f32, @floatFromInt(@divFloor(SCREEN_WIDTH, 3))), .height = offset }, rl.Vector2{ .x = x, .y = @as(f32, @floatFromInt(SCREEN_HEIGHT)) - offset }, rl.WHITE);
}

// Enhanced collision detection using AABB (Axis-Aligned Bounding Box) algorithm
fn checkCollisionAABB(rect1: rl.Rectangle, rect2: rl.Rectangle) bool {
    return rect1.x < rect2.x + rect2.width and
        rect1.x + rect1.width > rect2.x and
        rect1.y < rect2.y + rect2.height and
        rect1.y + rect1.height > rect2.y;
}

// Enhanced collision detection using SAT (Separating Axis Theorem) algorithm
fn checkCollisionSAT(rect1: rl.Rectangle, rect2: rl.Rectangle) bool {
    const axes = [_]rl.Vector2{
        rl.Vector2{ .x = 1, .y = 0 }, // X-axis
        rl.Vector2{ .x = 0, .y = 1 }, // Y-axis
    };

    for (axes) |axis| {
        const proj1 = projectRectangle(rect1, axis);
        const proj2 = projectRectangle(rect2, axis);

        if (!overlap(proj1, proj2)) {
            return false;
        }
    }

    return true;
}

// Helper function to project a rectangle onto an axis
fn projectRectangle(rect: rl.Rectangle, axis: rl.Vector2) [2]f32 {
    const corners = [_]rl.Vector2{
        rl.Vector2{ .x = rect.x, .y = rect.y },
        rl.Vector2{ .x = rect.x + rect.width, .y = rect.y },
        rl.Vector2{ .x = rect.x, .y = rect.y + rect.height },
        rl.Vector2{ .x = rect.x + rect.width, .y = rect.y + rect.height },
    };

    var min = std.math.inf(f32);
    var max = -std.math.inf(f32);

    for (corners) |corner| {
        const dot = corner.x * axis.x + corner.y * axis.y;
        min = @min(min, dot);
        max = @max(max, dot);
    }

    return [2]f32{ min, max };
}

// Helper function to check if two projections overlap
fn overlap(proj1: [2]f32, proj2: [2]f32) bool {
    return proj1[0] <= proj2[1] and proj1[1] >= proj2[0];
}

// Enhanced collision detection with spatial partitioning using Quadtree
const Quadtree = struct {
    bounds: rl.Rectangle,
    objects: std.ArrayList(rl.Rectangle),
    nodes: [4]?*Quadtree,

    fn init(bounds: rl.Rectangle) Quadtree {
        return Quadtree{
            .bounds = bounds,
            .objects = std.ArrayList(rl.Rectangle).init(std.heap.page_allocator),
            .nodes = [4]?*Quadtree{ null, null, null, null },
        };
    }

    fn insert(self: *Quadtree, rect: rl.Rectangle) !void {
        if (!checkCollisionAABB(rect, self.bounds)) {
            return;
        }

        if (self.objects.items.len < 4) {
            try self.objects.append(rect);
            return;
        }

        if (self.nodes[0] == null) {
            const subWidth = self.bounds.width / 2;
            const subHeight = self.bounds.height / 2;
            const x = self.bounds.x;
            const y = self.bounds.y;

            self.nodes[0] = try std.heap.page_allocator.create(Quadtree);
            self.nodes[0].?.* = Quadtree.init(rl.Rectangle{ .x = x, .y = y, .width = subWidth, .height = subHeight });

            self.nodes[1] = try std.heap.page_allocator.create(Quadtree);
            self.nodes[1].?.* = Quadtree.init(rl.Rectangle{ .x = x + subWidth, .y = y, .width = subWidth, .height = subHeight });

            self.nodes[2] = try std.heap.page_allocator.create(Quadtree);
            self.nodes[2].?.* = Quadtree.init(rl.Rectangle{ .x = x, .y = y + subHeight, .width = subWidth, .height = subHeight });

            self.nodes[3] = try std.heap.page_allocator.create(Quadtree);
            self.nodes[3].?.* = Quadtree.init(rl.Rectangle{ .x = x + subWidth, .y = y + subHeight, .width = subWidth, .height = subHeight });
        }

        for (self.nodes) |node| {
            try node.?.insert(rect);
        }
    }

    fn query(self: *Quadtree, rect: rl.Rectangle, found: *std.ArrayList(rl.Rectangle)) !void {
        if (!checkCollisionAABB(rect, self.bounds)) {
            return;
        }

        for (self.objects.items) |obj| {
            if (checkCollisionAABB(rect, obj)) {
                try found.append(obj);
            }
        }

        if (self.nodes[0] != null) {
            for (self.nodes) |node| {
                try node.?.query(rect, found);
            }
        }
    }
};

// Replace the existing collision detection in handleCarCollision with the enhanced version
fn handleCarCollision(playerCar: *Car, otherCar: rl.Vector2, otherCarSize: rl.Vector2, vulnerable: *bool, lives: *i32, carCrash: rl.Sound, pears: *std.ArrayList(Pear), rand: std.Random) !void {
    const rec1 = rl.Rectangle{
        .x = playerCar.position.x,
        .y = playerCar.position.y,
        .width = @floatFromInt(playerCar.texture.width),
        .height = @floatFromInt(playerCar.texture.height),
    };

    const rec2 = rl.Rectangle{
        .x = otherCar.x,
        .y = otherCar.y,
        .width = otherCarSize.x,
        .height = otherCarSize.y,
    };

    if (checkCollisionSAT(rec1, rec2)) {
        if (vulnerable.*) {
            lives.* -= 1;
            vulnerable.* = false;
            rl.PlaySound(carCrash);

            try pears.append(Pear{
                .position = rl.Vector2{
                    .x = playerCar.position.x,
                    .y = playerCar.position.y,
                },
                .velocity = rl.Vector2{
                    .x = rand.float(f32) * 200 - 100,
                    .y = rand.float(f32) * 100 + 50,
                },
                .lifetime = 3.0,
            });
        }
        playerCar.position.y -= @as(f32, @floatFromInt(playerCar.texture.height)) - 10;
    }
}

fn updateCarPosition(carPos: *rl.Vector2, carSpeed: *f32, rand: std.Random, carsTextures: rl.Texture2D) void {
    carPos.y += carSpeed.*;

    if (carPos.y > @as(f32, @floatFromInt(SCREEN_HEIGHT))) {
        carPos.y = -@as(f32, @floatFromInt(carsTextures.height));

        carPos.x = @as(f32, @floatFromInt(SCREEN_WIDTH)) / 3 +
            rand.float(f32) * @as(f32, @floatFromInt(SCREEN_WIDTH)) / 3;

        carSpeed.* = @as(f32, @floatFromInt(rand.intRangeAtMost(i32, 6, 10)));
    }
}

fn drawGameStats(score: i32, lives: i32) !void {
    rl.DrawRectangle(10, 10, 100, 75, rl.SKYBLUE);
    rl.DrawRectangleLines(10, 10, 100, 75, rl.SKYBLUE);

    rl.DrawFPS(710, 10);
    rl.DrawText("Game Stats", 20, 20, 10, rl.BLACK);

    var scoring: [20]u8 = undefined;
    const scoreText = try std.fmt.bufPrintZ(&scoring, "Score: {d}/1000", .{score});
    rl.DrawText(scoreText, 20, 40, 10, rl.DARKGRAY);
    var livesScoring: [20]u8 = undefined;
    const livesText = try std.fmt.bufPrintZ(&livesScoring, "Lives: {d}/9", .{lives});
    rl.DrawText(livesText, 20, 60, 10, rl.DARKGRAY);
}

fn updatePears(pears: *std.ArrayList(Pear), deltaTime: f32) !void {
    var i: usize = 0;
    while (i < pears.items.len) {
        var pear = &pears.items[i];
        pear.position.x += pear.velocity.x * deltaTime;
        pear.position.y += pear.velocity.y * deltaTime;
        pear.velocity.y += 500 * deltaTime; // Add gravity
        pear.lifetime -= deltaTime;

        if (pear.lifetime <= 0 or pear.position.y > SCREEN_HEIGHT) {
            _ = pears.swapRemove(i);
        } else {
            i += 1;
        }
    }
}

pub fn main() anyerror!void {

    // Initialize window
    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Tiny Car Game");
    defer rl.CloseWindow(); // Ensure window is closed when function exits

    // Initialize Audio
    rl.InitAudioDevice();
    defer rl.CloseAudioDevice();

    rl.SetTargetFPS(60); // Set target frame rate

    // Load car texture
    const carTexture = rl.LoadTexture("resources/textures/car.png");
    defer rl.UnloadTexture(carTexture);

    // Load pear texture
    const pearTexture = rl.LoadTexture("resources/textures/pear.png");
    defer rl.UnloadTexture(pearTexture);

    // Initialize pears list
    var pears = std.ArrayList(Pear).init(std.heap.page_allocator);
    defer pears.deinit();

    // // Initialize player car
    var car = Car{ .texture = carTexture, .position = rl.Vector2{
        .x = @as(f32, @floatFromInt(SCREEN_WIDTH)) / 2 - @as(f32, @floatFromInt(carTexture.width)) / 2,
        .y = @as(f32, @floatFromInt(SCREEN_HEIGHT)) * 3 / 5,
    }, .speed = 2 };

    try std.io.getStdOut().writer().print("Car {any}/n", .{car});
    const speedMovement = 4;

    // Load trees texture
    const treesTexture = rl.LoadTexture("resources/textures/trees.png");
    defer rl.UnloadTexture(treesTexture);

    // Define source rectangles for trees
    var sourceRects = [_]rl.Rectangle{.{
        .width = 48,
        .height = 48,
        .x = 0,
        .y = 0,
    }} ** 3;
    for (&sourceRects, 0..) |*rect, i| {
        rect.x = @as(f32, @floatFromInt(i)) * rect.width;
    }

    // Randomize positions of trees
    const treesNum = rl.GetRandomValue(10, 27);
    var treesPos = try std.ArrayList(rl.Vector2).initCapacity(std.heap.page_allocator, @intCast(treesNum));
    defer treesPos.deinit();

    var i: usize = 0;

    while (i < treesNum) : (i += 1) {
        var pos = rl.Vector2{ .x = if (i < @divFloor(treesNum, 2))
            @as(f32, @floatFromInt(rl.GetRandomValue(1, SCREEN_WIDTH / 3)))
        else
            @as(f32, @floatFromInt(rl.GetRandomValue(2 * SCREEN_WIDTH / 3, SCREEN_WIDTH))), .y = @as(f32, @floatFromInt(rl.GetRandomValue(0, SCREEN_HEIGHT - @as(i32, treesTexture.height)))) };

        // Adjust tree position if it's too close to the edge
        if (i < @divFloor(treesNum, 2) and pos.x + @as(f32, @floatFromInt(treesTexture.width)) / 3 > @as(f32, @floatFromInt(SCREEN_WIDTH)) / 3) {
            pos.x -= @as(f32, @floatFromInt(treesTexture.width)) / 3;
        } else if (i >= @divFloor(treesNum, 2) and pos.x + @as(f32, @floatFromInt(treesTexture.width)) / 3 > @as(f32, @floatFromInt(SCREEN_WIDTH))) {
            pos.x -= @as(f32, @floatFromInt(treesTexture.width)) / 3;
        }

        try treesPos.append(pos);
    }

    // Load cars texture
    const carsTextures = rl.LoadTexture("resources/textures/cars.png");
    defer rl.UnloadTexture(carsTextures);

    // Load grass texture
    const grassTexture = rl.LoadTexture("resources/textures/grass.png");
    defer rl.UnloadTexture(grassTexture);

    // Variable to track grass scroll offset
    var grassScrollOffset: f32 = 0;

    // Load road texture
    const roadTexture = rl.LoadTexture("resources/textures/road.png");
    defer rl.UnloadTexture(roadTexture);

    // Define source rectangles for cars
    var sourcesRectsCars: [6]rl.Rectangle = [_]rl.Rectangle{.{ .width = 16, .height = 24, .x = 0, .y = 0 }} ** 6;
    var carsPos: [6]rl.Vector2 = [_]rl.Vector2{.{ .x = 0, .y = 0 }} ** 6;
    var carsSpeed: [6]f32 = [_]f32{0} ** 6;

    // Initialize random number generator
    var prng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    var rand = prng.random();

    // Initialize cars positions and speeds
    for (&sourcesRectsCars, 0..) |*rect, j| {
        rect.x = @as(f32, @floatFromInt(j)) * rect.width;

        carsPos[j].x = @as(f32, @floatFromInt(SCREEN_WIDTH)) / 3 +
            rand.float(f32) * @as(f32, @floatFromInt(SCREEN_WIDTH)) / 3;

        carsPos[j].y = @as(f32, @floatFromInt(rand.intRangeAtMost(i32, 0, SCREEN_HEIGHT - @as(i32, carsTextures.height))));
        carsSpeed[j] = @as(f32, @floatFromInt(rand.intRangeAtMost(i32, 6, 10)));
    }

    // Load audio
    const backgroundMusic = rl.LoadMusicStream("resources/sound/speeding.mp3");
    defer rl.UnloadMusicStream(backgroundMusic);

    const carBrake = rl.LoadSound("resources/sound/brake.mp3");
    defer rl.UnloadSound(carBrake);
    rl.SetSoundVolume(carBrake, 0.3); // Set volume to 30%

    const carCrash = rl.LoadSound("resources/sound/car-crash.mp3");
    defer rl.UnloadSound(carCrash);
    rl.SetSoundVolume(carCrash, 0.1); // Set volume to 30%

    // Define rectangle covering the entire screen
    const rmuteScreen = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = @as(f32, @floatFromInt(SCREEN_WIDTH)),
        .height = @as(f32, @floatFromInt(SCREEN_HEIGHT)),
    };

    // Initialize game state variables
    var lives: i32 = 9;
    var score: i32 = 0;
    var time: f64 = 0;
    var vulnerableTime: f64 = 0;
    var gaveOver: bool = false;
    var gameWon: bool = false;
    var vulnerable: bool = true;

    rl.PlayMusicStream(backgroundMusic);

    // Main game loop
    while (!rl.WindowShouldClose()) {
        // Update game state
        if (!gaveOver) {
            const deltaTime = rl.GetFrameTime();

            // Update grass scroll offset
            grassScrollOffset += @as(f32, @floatFromInt(car.speed));
            if (grassScrollOffset >= @as(f32, @floatFromInt(grassTexture.height))) {
                grassScrollOffset -= @as(f32, @floatFromInt(grassTexture.height));
            }

            // Update pears
            try updatePears(&pears, deltaTime);

            // Handle player input
            if (rl.IsKeyDown(rl.KEY_H)) {
                car.position.x = @max(car.position.x - @as(f32, @floatFromInt(car.speed)), @as(f32, @floatFromInt(SCREEN_WIDTH)) / 3);
            } else if (rl.IsKeyDown(rl.KEY_L)) {
                car.position.x = @min(car.position.x + @as(f32, @floatFromInt(car.speed)), @as(f32, @floatFromInt(SCREEN_WIDTH)) * 2 / 3 - @as(f32, @floatFromInt(car.texture.width)));
            } else if (rl.IsKeyDown(rl.KEY_K)) {
                car.position.y = @max(car.position.y - @as(f32, @floatFromInt(car.speed)), 0);
            } else if (rl.IsKeyDown(rl.KEY_J)) {
                rl.PlaySound(carBrake);
                car.position.y = @min(car.position.y + @as(f32, @floatFromInt(car.speed)), @as(f32, @floatFromInt(SCREEN_HEIGHT)) - @as(f32, @floatFromInt(car.texture.height)));
            }

            // Update trees positions
            for (treesPos.items) |*treePos| {
                treePos.y += @as(f32, @floatFromInt(car.speed));
                if (treePos.y > @as(f32, @floatFromInt(SCREEN_HEIGHT))) {
                    treePos.y = -@as(f32, @floatFromInt(treesTexture.height));
                }
            }

            // Update other cars positions and check for collisions
            for (&carsPos, 0..) |*carPos, k| {
                updateCarPosition(carPos, &carsSpeed[k], rand, carsTextures);

                // Check if the player's car has passed the other cars
                if (car.position.y < carPos.y + @as(f32, @floatFromInt(carsTextures.height)) and car.position.y + @as(f32, @floatFromInt(car.texture.height)) > carPos.y + @as(f32, @floatFromInt(carsTextures.height))) {
                    // Player's car has passed this car
                    score += 1;
                }

                try handleCarCollision(&car, carPos.*, rl.Vector2{ .x = @as(f32, @floatFromInt(carsTextures.width)) / 6, .y = @floatFromInt(carsTextures.height) }, &vulnerable, &lives, carCrash, &pears, rand);
            }

            // Handle vulnerability period after collision
            if (!vulnerable) {
                vulnerableTime += rl.GetFrameTime();
                if (vulnerableTime > 1) {
                    vulnerable = true;
                    vulnerableTime = 0;
                }
            }

            // Check for game over condition
            if (lives < 0) {
                gaveOver = true;
            }

            // Adjust car speed based on position
            if (car.position.x < @as(f32, @floatFromInt(SCREEN_WIDTH)) / 3 or car.position.x + @as(f32, @floatFromInt(car.texture.width)) > @as(f32, @floatFromInt(SCREEN_WIDTH)) * 2 / 3) {
                car.speed = speedMovement / 2;
            } else {
                car.speed = speedMovement;
            }

            // Update score
            time += rl.GetFrameTime();
            if (time > 1) {
                score += 1;
                time = 0;
            }

            // Check for win conditionmain
            if (score > 999) {
                gameWon = true;
                gaveOver = true;
            }
        }

        // Play background music
        rl.UpdateMusicStream(backgroundMusic);

        // Draw game elements
        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.WHITE);
        rl.DrawTexture(carTexture, @divFloor(SCREEN_WIDTH, 2) - @divFloor(carTexture.width, 2), @divFloor(SCREEN_HEIGHT, 2) - @divFloor(carTexture.height, 2), rl.WHITE);

        // Draw background

        // Draw grass textures
        drawGrassTexture(grassTexture, grassScrollOffset, .Left);
        drawGrassTexture(grassTexture, grassScrollOffset, .Right);

        // Draw road texture (middle)
        rl.DrawRectangle(@divFloor(SCREEN_WIDTH, 3), 0, @divFloor(SCREEN_WIDTH, 3), SCREEN_HEIGHT, rl.GRAY);

        // Draw player car
        if (!vulnerable) {
            const col = rl.Color{
                .r = 0,
                .g = 0,
                .b = 0,
                .a = 0,
            };
            rl.DrawTexture(car.texture, @intFromFloat(car.position.x), @intFromFloat(car.position.y), col);
        } else {
            rl.DrawTexture(car.texture, @intFromFloat(car.position.x), @intFromFloat(car.position.y), rl.WHITE);
        }

        // Draw other cars
        for (sourcesRectsCars, 0..) |sourceRectCar, m| {
            rl.DrawTextureRec(carsTextures, sourceRectCar, carsPos[m], rl.WHITE);
        }

        // Draw trees
        for (treesPos.items, 0..) |treePos, n| {
            rl.DrawTextureRec(treesTexture, sourceRects[n % 3], treePos, rl.WHITE);
        }

        // Draw pears
        for (pears.items) |pear| {
            const alpha = @as(u8, @intFromFloat(@min(pear.lifetime / 3.0, 1.0) * 255));
            const color = rl.Color{ .r = 255, .g = 255, .b = 255, .a = alpha };
            rl.DrawTexture(pearTexture, @intFromFloat(pear.position.x), @intFromFloat(pear.position.y), color);
        }

        try drawGameStats(score, lives);

        // Draw game over screen
        if (gaveOver) {
            const color = rl.Color{ .r = 0, .g = 0, .b = 0, .a = 180 };
            rl.DrawRectangle(@intFromFloat(rmuteScreen.x), @intFromFloat(rmuteScreen.y), @intFromFloat(rmuteScreen.width), @intFromFloat(rmuteScreen.height), color);
            if (gameWon) {
                rl.DrawText("You Won!!", @divFloor(SCREEN_WIDTH - rl.MeasureText("You Won!!", 90), 2), @divFloor(SCREEN_HEIGHT, 2) - 45, 90, rl.WHITE);
            } else {
                rl.DrawText("Game Over!!", @divFloor(SCREEN_WIDTH - rl.MeasureText("Game Over!!", 90), 2), @divFloor(SCREEN_HEIGHT, 2) - 45, 90, rl.WHITE);
            }
        }
    }
}
