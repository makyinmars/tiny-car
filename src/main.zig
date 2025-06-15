const rl = @import("raylib");
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

const GameState = enum {
    MainMenu,
    Playing,
    Paused,
    GameOver,
};

fn drawGrassTexture(texture: rl.Texture2D, offset: f32, side: enum { Left, Right }) void {
    const x = if (side == .Left) 0 else @as(f32, @floatFromInt(@divFloor(SCREEN_WIDTH * 2, 3)));
    rl.drawTextureRec(texture, rl.Rectangle{ .x = 0, .y = offset, .width = @as(f32, @floatFromInt(@divFloor(SCREEN_WIDTH, 3))), .height = @as(f32, @floatFromInt(SCREEN_HEIGHT)) }, rl.Vector2{ .x = x, .y = -offset }, rl.Color.white);
    rl.drawTextureRec(texture, rl.Rectangle{ .x = 0, .y = 0, .width = @as(f32, @floatFromInt(@divFloor(SCREEN_WIDTH, 3))), .height = offset }, rl.Vector2{ .x = x, .y = @as(f32, @floatFromInt(SCREEN_HEIGHT)) - offset }, rl.Color.white);
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
            rl.playSound(carCrash);

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

fn drawRoundedRect(x: i32, y: i32, width: i32, height: i32, roundness: f32, color: rl.Color) void {
    rl.drawRectangleRounded(rl.Rectangle{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = @floatFromInt(width), .height = @floatFromInt(height) }, roundness, 16, color);
}

fn drawProgressBar(x: i32, y: i32, width: i32, height: i32, current: f32, max: f32, bgColor: rl.Color, fillColor: rl.Color) void {
    // Background
    drawRoundedRect(x, y, width, height, 0.5, bgColor);

    // Fill
    const fillWidth = @as(i32, @intFromFloat((current / max) * @as(f32, @floatFromInt(width))));
    if (fillWidth > 0) {
        drawRoundedRect(x, y, fillWidth, height, 0.5, fillColor);
    }

    // Border
    rl.drawRectangleRoundedLines(rl.Rectangle{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = @floatFromInt(width), .height = @floatFromInt(height) }, 0.5, 16, rl.Color.white);
}

fn drawGameStats(score: i32, lives: i32) !void {
    const hudX = 15;
    const hudY = 15;
    const hudWidth = 200;
    const hudHeight = 120;

    // Main HUD background with gradient effect
    const bgColor = rl.Color{ .r = 20, .g = 25, .b = 35, .a = 200 };
    const borderColor = rl.Color{ .r = 100, .g = 150, .b = 255, .a = 255 };

    drawRoundedRect(hudX, hudY, hudWidth, hudHeight, 0.3, bgColor);
    rl.drawRectangleRoundedLines(rl.Rectangle{ .x = @floatFromInt(hudX), .y = @floatFromInt(hudY), .width = @floatFromInt(hudWidth), .height = @floatFromInt(hudHeight) }, 0.3, 16, borderColor);

    // Title
    rl.drawText("GAME STATS", hudX + 10, hudY + 10, 14, rl.Color.white);

    // Score section
    rl.drawText("SCORE", hudX + 10, hudY + 35, 12, rl.Color.light_gray);
    var scoring: [20]u8 = undefined;
    const scoreText = try std.fmt.bufPrintZ(&scoring, "{d}/1000", .{score});
    rl.drawText(scoreText, hudX + 60, hudY + 35, 12, rl.Color.white);

    // Score progress bar
    const scoreColor = if (score >= 1000) rl.Color.green else if (score >= 500) rl.Color.yellow else rl.Color.orange;
    drawProgressBar(hudX + 10, hudY + 52, hudWidth - 20, 8, @floatFromInt(score), 1000.0, rl.Color{ .r = 50, .g = 50, .b = 50, .a = 255 }, scoreColor);

    // Lives section
    rl.drawText("LIVES", hudX + 10, hudY + 70, 12, rl.Color.light_gray);
    var livesScoring: [20]u8 = undefined;
    const livesText = try std.fmt.bufPrintZ(&livesScoring, "{d}/9", .{lives});
    rl.drawText(livesText, hudX + 50, hudY + 70, 12, rl.Color.white);

    // Lives progress bar (hearts-like visualization)
    const livesColor = if (lives >= 7) rl.Color.green else if (lives >= 4) rl.Color.yellow else rl.Color.red;
    drawProgressBar(hudX + 10, hudY + 87, hudWidth - 20, 8, @floatFromInt(@max(lives, 0)), 9.0, rl.Color{ .r = 50, .g = 50, .b = 50, .a = 255 }, livesColor);

    // Draw individual life indicators
    const heartSpacing = 15;
    const heartStartX = hudX + 10;
    const heartY = hudY + 100;

    var i: i32 = 0;
    while (i < 9) : (i += 1) {
        const heartColor = if (i < lives) rl.Color.red else rl.Color{ .r = 60, .g = 60, .b = 60, .a = 255 };
        rl.drawText("♥", heartStartX + i * heartSpacing, heartY, 12, heartColor);
    }

    // FPS in top right corner with better styling
    drawRoundedRect(SCREEN_WIDTH - 70, 15, 55, 25, 0.3, rl.Color{ .r = 0, .g = 0, .b = 0, .a = 150 });
    rl.drawFPS(SCREEN_WIDTH - 65, 20);
}

fn drawButton(x: i32, y: i32, width: i32, height: i32, text: [:0]const u8, isHovered: bool) void {
    const buttonColor = if (isHovered)
        rl.Color{ .r = 100, .g = 150, .b = 255, .a = 255 }
    else
        rl.Color{ .r = 70, .g = 120, .b = 200, .a = 255 };

    const borderColor = if (isHovered)
        rl.Color{ .r = 150, .g = 200, .b = 255, .a = 255 }
    else
        rl.Color{ .r = 100, .g = 150, .b = 255, .a = 255 };

    drawRoundedRect(x, y, width, height, 0.3, buttonColor);
    rl.drawRectangleRoundedLines(rl.Rectangle{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = @floatFromInt(width), .height = @floatFromInt(height) }, 0.3, 16, borderColor);

    const textWidth = rl.measureText(text, 16);
    const textX = x + @divFloor(width - textWidth, 2);
    const textY = y + @divFloor(height - 16, 2);
    rl.drawText(text, textX, textY, 16, rl.Color.white);
}

fn drawGameOverScreen(gameWon: bool, score: i32, lives: i32) !void {
    // Dark overlay with fade effect
    rl.drawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, rl.Color{ .r = 0, .g = 0, .b = 0, .a = 180 });

    // Main modal
    const modalWidth = 400;
    const modalHeight = 300;
    const modalX = @divFloor(SCREEN_WIDTH - modalWidth, 2);
    const modalY = @divFloor(SCREEN_HEIGHT - modalHeight, 2);

    // Modal background
    const modalBg = rl.Color{ .r = 30, .g = 35, .b = 45, .a = 240 };
    const modalBorder = rl.Color{ .r = 100, .g = 150, .b = 255, .a = 255 };

    drawRoundedRect(modalX, modalY, modalWidth, modalHeight, 0.2, modalBg);
    rl.drawRectangleRoundedLines(rl.Rectangle{ .x = @floatFromInt(modalX), .y = @floatFromInt(modalY), .width = @floatFromInt(modalWidth), .height = @floatFromInt(modalHeight) }, 0.2, 16, modalBorder);

    // Title
    const titleText = if (gameWon) "🏆 VICTORY! 🏆" else "💥 GAME OVER 💥";
    const titleColor = if (gameWon) rl.Color.yellow else rl.Color.red;
    const titleSize = 32;
    const titleWidth = rl.measureText(titleText, titleSize);
    rl.drawText(titleText, modalX + @divFloor(modalWidth - titleWidth, 2), modalY + 20, titleSize, titleColor);

    // Stats section
    const statsY = modalY + 80;
    rl.drawText("FINAL SCORE", modalX + 20, statsY, 16, rl.Color.light_gray);

    var scoreBuffer: [20]u8 = undefined;
    const finalScoreText = try std.fmt.bufPrintZ(&scoreBuffer, "{d} / 1000", .{score});
    rl.drawText(finalScoreText, modalX + modalWidth - 120, statsY, 16, rl.Color.white);

    rl.drawText("LIVES REMAINING", modalX + 20, statsY + 25, 16, rl.Color.light_gray);

    var livesBuffer: [20]u8 = undefined;
    const finalLivesText = try std.fmt.bufPrintZ(&livesBuffer, "{d} / 9", .{@max(lives, 0)});
    rl.drawText(finalLivesText, modalX + modalWidth - 120, statsY + 25, 16, rl.Color.white);

    // Performance rating
    const ratingY = statsY + 60;
    rl.drawText("PERFORMANCE", modalX + 20, ratingY, 16, rl.Color.light_gray);

    const rating = if (gameWon) "EXCELLENT!" else if (score >= 500) "GOOD!" else if (score >= 250) "FAIR" else "NEEDS IMPROVEMENT";

    const ratingColor = if (gameWon) rl.Color.green else if (score >= 500) rl.Color.yellow else if (score >= 250) rl.Color.orange else rl.Color.red;

    rl.drawText(rating, modalX + modalWidth - 150, ratingY, 16, ratingColor);

    // Buttons
    const buttonWidth = 120;
    const buttonHeight = 40;
    const buttonY = modalY + modalHeight - 70;

    // Play Again button
    drawButton(modalX + 40, buttonY, buttonWidth, buttonHeight, "PLAY AGAIN", false);

    // Quit button
    drawButton(modalX + modalWidth - 160, buttonY, buttonWidth, buttonHeight, "QUIT", false);

    // Instructions
    rl.drawText("Press SPACE to Play Again or ESC to Quit", modalX + 20, modalY + modalHeight - 25, 12, rl.Color.light_gray);
}

fn drawRoad(scrollOffset: f32) void {
    const roadX = @divFloor(SCREEN_WIDTH, 3);
    const roadWidth = @divFloor(SCREEN_WIDTH, 3);

    // Draw main road surface with texture effect
    const roadColor = rl.Color{ .r = 60, .g = 60, .b = 65, .a = 255 };
    rl.drawRectangle(roadX, 0, roadWidth, SCREEN_HEIGHT, roadColor);

    // Draw road shoulders (edges)
    const shoulderColor = rl.Color{ .r = 80, .g = 80, .b = 80, .a = 255 };
    rl.drawRectangle(roadX - 5, 0, 5, SCREEN_HEIGHT, shoulderColor);
    rl.drawRectangle(roadX + roadWidth, 0, 5, SCREEN_HEIGHT, shoulderColor);

    // Draw white side lines (road edges)
    rl.drawRectangle(roadX - 2, 0, 2, SCREEN_HEIGHT, rl.Color.white);
    rl.drawRectangle(roadX + roadWidth, 0, 2, SCREEN_HEIGHT, rl.Color.white);

    // Draw center dashed line
    const lineColor = rl.Color.yellow;
    const dashLength = 30;
    const dashGap = 20;
    const lineWidth = 3;
    const centerX = roadX + @divFloor(roadWidth, 2) - @divFloor(lineWidth, 2);

    // Calculate animation based on scroll offset
    const animatedOffset = @mod(scrollOffset * 2, @as(f32, @floatFromInt(dashLength + dashGap)));

    var y: i32 = -dashLength + @as(i32, @intFromFloat(animatedOffset));
    while (y < SCREEN_HEIGHT + dashLength) : (y += dashLength + dashGap) {
        if (y >= -dashLength and y <= SCREEN_HEIGHT) {
            const drawY = @max(y, 0);
            const drawHeight = @min(y + dashLength, SCREEN_HEIGHT) - drawY;
            if (drawHeight > 0) {
                rl.drawRectangle(centerX, drawY, lineWidth, drawHeight, lineColor);
            }
        }
    }

    // Draw lane dividers (subtle dashed lines)
    const laneColor = rl.Color{ .r = 200, .g = 200, .b = 200, .a = 120 };
    const laneDashLength = 15;
    const laneDashGap = 25;
    const laneWidth = 1;

    // Left lane divider
    const leftLaneX = roadX + @divFloor(roadWidth, 4);
    var laneY: i32 = -laneDashLength + @as(i32, @intFromFloat(animatedOffset * 0.7));
    while (laneY < SCREEN_HEIGHT + laneDashLength) : (laneY += laneDashLength + laneDashGap) {
        if (laneY >= -laneDashLength and laneY <= SCREEN_HEIGHT) {
            const drawY = @max(laneY, 0);
            const drawHeight = @min(laneY + laneDashLength, SCREEN_HEIGHT) - drawY;
            if (drawHeight > 0) {
                rl.drawRectangle(leftLaneX, drawY, laneWidth, drawHeight, laneColor);
            }
        }
    }

    // Right lane divider
    const rightLaneX = roadX + 3 * @divFloor(roadWidth, 4);
    laneY = -laneDashLength + @as(i32, @intFromFloat(animatedOffset * 0.7));
    while (laneY < SCREEN_HEIGHT + laneDashLength) : (laneY += laneDashLength + laneDashGap) {
        if (laneY >= -laneDashLength and laneY <= SCREEN_HEIGHT) {
            const drawY = @max(laneY, 0);
            const drawHeight = @min(laneY + laneDashLength, SCREEN_HEIGHT) - drawY;
            if (drawHeight > 0) {
                rl.drawRectangle(rightLaneX, drawY, laneWidth, drawHeight, laneColor);
            }
        }
    }
}

fn drawSpeedometer(speed: i32, maxSpeed: i32) void {
    const speedoX = SCREEN_WIDTH - 120;
    const speedoY = SCREEN_HEIGHT - 120;
    const speedoRadius = 45;
    const centerX = speedoX + speedoRadius;
    const centerY = speedoY + speedoRadius;

    // Background circle
    const bgColor = rl.Color{ .r = 30, .g = 35, .b = 45, .a = 200 };
    rl.drawCircle(centerX, centerY, @floatFromInt(speedoRadius), bgColor);
    rl.drawCircleLines(centerX, centerY, @floatFromInt(speedoRadius), rl.Color{ .r = 100, .g = 150, .b = 255, .a = 255 });

    // Speed arc (background)
    const arcColor = rl.Color{ .r = 50, .g = 50, .b = 50, .a = 255 };
    rl.drawCircleSector(rl.Vector2{ .x = @floatFromInt(centerX), .y = @floatFromInt(centerY) }, @floatFromInt(speedoRadius - 10), 225, 495, 20, arcColor);

    // Speed arc (current speed)
    const speedPercent = @as(f32, @floatFromInt(speed)) / @as(f32, @floatFromInt(maxSpeed));
    const speedAngle = 225 + (speedPercent * 270); // 270 degree range
    const speedColor = if (speed >= @as(i32, @intFromFloat(@as(f32, @floatFromInt(maxSpeed)) * 0.8))) rl.Color.red else if (speed >= @as(i32, @intFromFloat(@as(f32, @floatFromInt(maxSpeed)) * 0.6))) rl.Color.yellow else rl.Color.green;

    rl.drawCircleSector(rl.Vector2{ .x = @floatFromInt(centerX), .y = @floatFromInt(centerY) }, @floatFromInt(speedoRadius - 10), 225, speedAngle, 20, speedColor);

    // Speed needle
    const needleAngle = (225 + (speedPercent * 270)) * std.math.pi / 180.0;
    const needleLength = @as(f32, @floatFromInt(speedoRadius - 15));
    const needleEndX = @as(i32, @intFromFloat(@as(f32, @floatFromInt(centerX)) + needleLength * @cos(needleAngle)));
    const needleEndY = @as(i32, @intFromFloat(@as(f32, @floatFromInt(centerY)) + needleLength * @sin(needleAngle)));

    rl.drawLineEx(rl.Vector2{ .x = @floatFromInt(centerX), .y = @floatFromInt(centerY) }, rl.Vector2{ .x = @floatFromInt(needleEndX), .y = @floatFromInt(needleEndY) }, 3, rl.Color.white);

    // Center dot
    rl.drawCircle(centerX, centerY, 4, rl.Color.white);

    // Speed text
    var speedBuffer: [10]u8 = undefined;
    const speedText = std.fmt.bufPrintZ(&speedBuffer, "{d}", .{speed}) catch "?";
    const textWidth = rl.measureText(speedText, 14);
    rl.drawText(speedText, centerX - @divFloor(textWidth, 2), centerY + 15, 14, rl.Color.white);

    // "MPH" label
    rl.drawText("MPH", centerX - 12, centerY + 30, 8, rl.Color.light_gray);
}

fn drawMainMenu() void {
    // Background
    rl.clearBackground(rl.Color{ .r = 20, .g = 25, .b = 35, .a = 255 });

    // Title
    const titleText = "🏎️ TINY CAR RACE 🏎️";
    const titleSize = 48;
    const titleWidth = rl.measureText(titleText, titleSize);
    rl.drawText(titleText, @divFloor(SCREEN_WIDTH - titleWidth, 2), 150, titleSize, rl.Color.yellow);

    // Subtitle
    const subtitleText = "Dodge Traffic • Collect Points • Survive!";
    const subtitleSize = 20;
    const subtitleWidth = rl.measureText(subtitleText, subtitleSize);
    rl.drawText(subtitleText, @divFloor(SCREEN_WIDTH - subtitleWidth, 2), 220, subtitleSize, rl.Color.light_gray);

    // Main menu buttons
    const buttonWidth = 200;
    const buttonHeight = 50;
    const buttonX = @divFloor(SCREEN_WIDTH - buttonWidth, 2);

    drawButton(buttonX, 300, buttonWidth, buttonHeight, "START GAME", false);
    drawButton(buttonX, 370, buttonWidth, buttonHeight, "CONTROLS", false);
    drawButton(buttonX, 440, buttonWidth, buttonHeight, "QUIT", false);

    // Instructions
    rl.drawText("Press SPACE to Start or ESC to Quit", @divFloor(SCREEN_WIDTH - rl.measureText("Press SPACE to Start or ESC to Quit", 16), 2), 520, 16, rl.Color.white);

    // Controls preview
    const controlsY = 570;
    rl.drawText("Controls: H/L = Left/Right, K/J = Up/Down", @divFloor(SCREEN_WIDTH - rl.measureText("Controls: H/L = Left/Right, K/J = Up/Down", 12), 2), controlsY, 12, rl.Color.gray);
}

fn drawPauseScreen() void {
    // Semi-transparent overlay
    rl.drawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, rl.Color{ .r = 0, .g = 0, .b = 0, .a = 150 });

    // Pause modal
    const modalWidth = 300;
    const modalHeight = 200;
    const modalX = @divFloor(SCREEN_WIDTH - modalWidth, 2);
    const modalY = @divFloor(SCREEN_HEIGHT - modalHeight, 2);

    const modalBg = rl.Color{ .r = 30, .g = 35, .b = 45, .a = 240 };
    const modalBorder = rl.Color{ .r = 100, .g = 150, .b = 255, .a = 255 };

    drawRoundedRect(modalX, modalY, modalWidth, modalHeight, 0.2, modalBg);
    rl.drawRectangleRoundedLines(rl.Rectangle{ .x = @floatFromInt(modalX), .y = @floatFromInt(modalY), .width = @floatFromInt(modalWidth), .height = @floatFromInt(modalHeight) }, 0.2, 16, modalBorder);

    // Title
    const titleText = "⏸️ PAUSED ⏸️";
    const titleSize = 36;
    const titleWidth = rl.measureText(titleText, titleSize);
    rl.drawText(titleText, modalX + @divFloor(modalWidth - titleWidth, 2), modalY + 30, titleSize, rl.Color.yellow);

    // Instructions
    const resumeText = "Press ESC to Resume";
    const resumeWidth = rl.measureText(resumeText, 16);
    rl.drawText(resumeText, modalX + @divFloor(modalWidth - resumeWidth, 2), modalY + 100, 16, rl.Color.white);

    const menuText = "Press M for Main Menu";
    const menuWidth = rl.measureText(menuText, 16);
    rl.drawText(menuText, modalX + @divFloor(modalWidth - menuWidth, 2), modalY + 130, 16, rl.Color.light_gray);
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
    rl.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Tiny Car Game");
    defer rl.closeWindow(); // Ensure window is closed when function exits

    // Initialize Audio
    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    rl.setTargetFPS(60); // Set target frame rate

    // Load car texture
    const carTexture = rl.loadTexture("resources/textures/car.png") catch |err| {
        std.log.err("Failed to load car texture: {}", .{err});
        return;
    };
    defer rl.unloadTexture(carTexture);

    // Load pear texture
    const pearTexture = rl.loadTexture("resources/textures/pear.png") catch |err| {
        std.log.err("Failed to load pear texture: {}", .{err});
        return;
    };
    defer rl.unloadTexture(pearTexture);

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
    const treesTexture = rl.loadTexture("resources/textures/trees.png") catch |err| {
        std.log.err("Failed to load trees texture: {}", .{err});
        return;
    };
    defer rl.unloadTexture(treesTexture);

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
    const treesNum = rl.getRandomValue(10, 27);
    var treesPos = try std.ArrayList(rl.Vector2).initCapacity(std.heap.page_allocator, @intCast(treesNum));
    defer treesPos.deinit();

    var i: usize = 0;

    while (i < treesNum) : (i += 1) {
        var pos = rl.Vector2{ .x = if (i < @divFloor(treesNum, 2))
            @as(f32, @floatFromInt(rl.getRandomValue(1, SCREEN_WIDTH / 3)))
        else
            @as(f32, @floatFromInt(rl.getRandomValue(2 * SCREEN_WIDTH / 3, SCREEN_WIDTH))), .y = @as(f32, @floatFromInt(rl.getRandomValue(0, SCREEN_HEIGHT - @as(i32, treesTexture.height)))) };

        // Adjust tree position if it's too close to the edge
        if (i < @divFloor(treesNum, 2) and pos.x + @as(f32, @floatFromInt(treesTexture.width)) / 3 > @as(f32, @floatFromInt(SCREEN_WIDTH)) / 3) {
            pos.x -= @as(f32, @floatFromInt(treesTexture.width)) / 3;
        } else if (i >= @divFloor(treesNum, 2) and pos.x + @as(f32, @floatFromInt(treesTexture.width)) / 3 > @as(f32, @floatFromInt(SCREEN_WIDTH))) {
            pos.x -= @as(f32, @floatFromInt(treesTexture.width)) / 3;
        }

        try treesPos.append(pos);
    }

    // Load cars texture
    const carsTextures = rl.loadTexture("resources/textures/cars.png") catch |err| {
        std.log.err("Failed to load cars texture: {}", .{err});
        return;
    };
    defer rl.unloadTexture(carsTextures);

    // Load grass texture
    const grassTexture = rl.loadTexture("resources/textures/grass.png") catch |err| {
        std.log.err("Failed to load grass texture: {}", .{err});
        return;
    };
    defer rl.unloadTexture(grassTexture);

    // Variable to track grass scroll offset
    var grassScrollOffset: f32 = 0;

    // Load road texture
    const roadTexture = rl.loadTexture("resources/textures/road.png") catch |err| {
        std.log.err("Failed to load road texture: {}", .{err});
        return;
    };
    defer rl.unloadTexture(roadTexture);

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
    const backgroundMusic = rl.loadMusicStream("resources/sound/speeding.mp3") catch |err| {
        std.log.err("Failed to load background music: {}", .{err});
        return;
    };
    defer rl.unloadMusicStream(backgroundMusic);

    const carBrake = rl.loadSound("resources/sound/brake.mp3") catch |err| {
        std.log.err("Failed to load brake sound: {}", .{err});
        return;
    };
    defer rl.unloadSound(carBrake);
    rl.setSoundVolume(carBrake, 0.3); // Set volume to 30%

    const carCrash = rl.loadSound("resources/sound/car-crash.mp3") catch |err| {
        std.log.err("Failed to load crash sound: {}", .{err});
        return;
    };
    defer rl.unloadSound(carCrash);
    rl.setSoundVolume(carCrash, 0.1); // Set volume to 30%

    // Initialize game state variables
    var gameState: GameState = GameState.MainMenu;
    var lives: i32 = 9;
    var score: i32 = 0;
    var time: f64 = 0;
    var vulnerableTime: f64 = 0;
    var gaveOver: bool = false;
    var gameWon: bool = false;
    var vulnerable: bool = true;

    rl.playMusicStream(backgroundMusic);

    // Main game loop
    while (!rl.windowShouldClose()) {
        // Handle input based on game state
        switch (gameState) {
            .MainMenu => {
                if (rl.isKeyPressed(rl.KeyboardKey.space)) {
                    gameState = GameState.Playing;
                }
            },
            .Playing => {
                // Update game state
                if (!gaveOver) {
                    const deltaTime = rl.getFrameTime();

                    // Update grass scroll offset
                    grassScrollOffset += @as(f32, @floatFromInt(car.speed));
                    if (grassScrollOffset >= @as(f32, @floatFromInt(grassTexture.height))) {
                        grassScrollOffset -= @as(f32, @floatFromInt(grassTexture.height));
                    }

                    // Update pears
                    try updatePears(&pears, deltaTime);

                    // Check for pause input
                    if (rl.isKeyPressed(rl.KeyboardKey.escape)) {
                        gameState = GameState.Paused;
                    }

                    // Handle player input
                    if (rl.isKeyDown(rl.KeyboardKey.h)) {
                        car.position.x = @max(car.position.x - @as(f32, @floatFromInt(car.speed)), @as(f32, @floatFromInt(SCREEN_WIDTH)) / 3);
                    } else if (rl.isKeyDown(rl.KeyboardKey.l)) {
                        car.position.x = @min(car.position.x + @as(f32, @floatFromInt(car.speed)), @as(f32, @floatFromInt(SCREEN_WIDTH)) * 2 / 3 - @as(f32, @floatFromInt(car.texture.width)));
                    } else if (rl.isKeyDown(rl.KeyboardKey.k)) {
                        car.position.y = @max(car.position.y - @as(f32, @floatFromInt(car.speed)), 0);
                    } else if (rl.isKeyDown(rl.KeyboardKey.j)) {
                        rl.playSound(carBrake);
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
                        vulnerableTime += rl.getFrameTime();
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
                    time += rl.getFrameTime();
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
            },
            .Paused => {
                // Handle pause input
                if (rl.isKeyPressed(rl.KeyboardKey.escape)) {
                    gameState = GameState.Playing;
                } else if (rl.isKeyPressed(rl.KeyboardKey.m)) {
                    gameState = GameState.MainMenu;
                    // Reset game state when returning to menu
                    gaveOver = false;
                    gameWon = false;
                    lives = 9;
                    score = 0;
                    time = 0;
                    vulnerableTime = 0;
                    vulnerable = true;

                    // Reset car position
                    car.position.x = @as(f32, @floatFromInt(SCREEN_WIDTH)) / 2 - @as(f32, @floatFromInt(carTexture.width)) / 2;
                    car.position.y = @as(f32, @floatFromInt(SCREEN_HEIGHT)) * 3 / 5;
                    car.speed = 2;

                    // Clear pears
                    pears.clearRetainingCapacity();

                    // Reset grass scroll
                    grassScrollOffset = 0;
                }
            },
            .GameOver => {
                // Game over is handled in drawing section
            },
        }

        // Play background music
        rl.updateMusicStream(backgroundMusic);

        // Draw game elements
        rl.beginDrawing();
        defer rl.endDrawing();

        switch (gameState) {
            .MainMenu => {
                drawMainMenu();
            },
            .Playing => {
                rl.clearBackground(rl.Color.white);
                rl.drawTexture(carTexture, @divFloor(SCREEN_WIDTH, 2) - @divFloor(carTexture.width, 2), @divFloor(SCREEN_HEIGHT, 2) - @divFloor(carTexture.height, 2), rl.Color.white);

                // Draw background

                // Draw grass textures
                drawGrassTexture(grassTexture, grassScrollOffset, .Left);
                drawGrassTexture(grassTexture, grassScrollOffset, .Right);

                // Draw enhanced road with lane markings
                drawRoad(grassScrollOffset);

                // Draw player car with blinking effect when vulnerable
                if (!vulnerable) {
                    // Blinking effect during invulnerability
                    const blinkSpeed = 8.0; // Blinks per second
                    const blinkTime = @mod(vulnerableTime * blinkSpeed, 1.0);
                    const shouldShow = blinkTime < 0.5;

                    if (shouldShow) {
                        // Draw with slight red tint during invulnerability
                        const invulnColor = rl.Color{ .r = 255, .g = 200, .b = 200, .a = 255 };
                        rl.drawTexture(car.texture, @intFromFloat(car.position.x), @intFromFloat(car.position.y), invulnColor);
                    }
                } else {
                    rl.drawTexture(car.texture, @intFromFloat(car.position.x), @intFromFloat(car.position.y), rl.Color.white);
                }

                // Draw other cars
                for (sourcesRectsCars, 0..) |sourceRectCar, m| {
                    rl.drawTextureRec(carsTextures, sourceRectCar, carsPos[m], rl.Color.white);
                }

                // Draw trees
                for (treesPos.items, 0..) |treePos, n| {
                    rl.drawTextureRec(treesTexture, sourceRects[n % 3], treePos, rl.Color.white);
                }

                // Draw pears
                for (pears.items) |pear| {
                    const alpha = @as(u8, @intFromFloat(@min(pear.lifetime / 3.0, 1.0) * 255));
                    const color = rl.Color{ .r = 255, .g = 255, .b = 255, .a = alpha };
                    rl.drawTexture(pearTexture, @intFromFloat(pear.position.x), @intFromFloat(pear.position.y), color);
                }

                try drawGameStats(score, lives);

                // Draw speedometer (convert car.speed to a reasonable range)
                const displaySpeed = car.speed * 10; // Scale up for better visual effect
                const maxDisplaySpeed = 80; // Maximum speed display
                drawSpeedometer(displaySpeed, maxDisplaySpeed);

                // Draw game over screen
                if (gaveOver) {
                    try drawGameOverScreen(gameWon, score, lives);

                    // Handle restart input
                    if (rl.isKeyPressed(rl.KeyboardKey.space)) {
                        // Reset game state
                        gaveOver = false;
                        gameWon = false;
                        gameState = GameState.Playing;
                        lives = 9;
                        score = 0;
                        time = 0;
                        vulnerableTime = 0;
                        vulnerable = true;

                        // Reset car position
                        car.position.x = @as(f32, @floatFromInt(SCREEN_WIDTH)) / 2 - @as(f32, @floatFromInt(carTexture.width)) / 2;
                        car.position.y = @as(f32, @floatFromInt(SCREEN_HEIGHT)) * 3 / 5;
                        car.speed = 2;

                        // Reset cars positions and speeds
                        for (&carsPos, 0..) |*carPos, j| {
                            carPos.x = @as(f32, @floatFromInt(SCREEN_WIDTH)) / 3 +
                                rand.float(f32) * @as(f32, @floatFromInt(SCREEN_WIDTH)) / 3;
                            carPos.y = @as(f32, @floatFromInt(rand.intRangeAtMost(i32, 0, SCREEN_HEIGHT - @as(i32, carsTextures.height))));
                            carsSpeed[j] = @as(f32, @floatFromInt(rand.intRangeAtMost(i32, 6, 10)));
                        }

                        // Clear pears
                        pears.clearRetainingCapacity();

                        // Reset grass scroll
                        grassScrollOffset = 0;
                    }
                }
            },
            .Paused => {
                // Draw the game background first (frozen)
                rl.clearBackground(rl.Color.white);
                rl.drawTexture(carTexture, @divFloor(SCREEN_WIDTH, 2) - @divFloor(carTexture.width, 2), @divFloor(SCREEN_HEIGHT, 2) - @divFloor(carTexture.height, 2), rl.Color.white);

                // Draw background
                drawGrassTexture(grassTexture, grassScrollOffset, .Left);
                drawGrassTexture(grassTexture, grassScrollOffset, .Right);
                drawRoad(grassScrollOffset);

                // Draw player car
                rl.drawTexture(car.texture, @intFromFloat(car.position.x), @intFromFloat(car.position.y), rl.Color.white);

                // Draw other cars
                for (sourcesRectsCars, 0..) |sourceRectCar, m| {
                    rl.drawTextureRec(carsTextures, sourceRectCar, carsPos[m], rl.Color.white);
                }

                // Draw trees
                for (treesPos.items, 0..) |treePos, n| {
                    rl.drawTextureRec(treesTexture, sourceRects[n % 3], treePos, rl.Color.white);
                }

                // Draw pears
                for (pears.items) |pear| {
                    const alpha = @as(u8, @intFromFloat(@min(pear.lifetime / 3.0, 1.0) * 255));
                    const color = rl.Color{ .r = 255, .g = 255, .b = 255, .a = alpha };
                    rl.drawTexture(pearTexture, @intFromFloat(pear.position.x), @intFromFloat(pear.position.y), color);
                }

                // Draw game stats and speedometer
                try drawGameStats(score, lives);
                const displaySpeed = car.speed * 10;
                const maxDisplaySpeed = 80;
                drawSpeedometer(displaySpeed, maxDisplaySpeed);

                // Draw pause overlay
                drawPauseScreen();
            },
            .GameOver => {
                // Game over state drawing would go here if we had a separate state
                // Currently handled within Playing state
            },
        }
    }
}
