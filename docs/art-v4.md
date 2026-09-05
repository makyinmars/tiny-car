# Tiny Car v4 encounter art and sound

The built-in ImageGen tool generated the two new atlases on September 5, 2026. The game loads the selected RGBA outputs directly, preserving their alpha channels. The existing car atlas supplied the style reference. Source rectangles in `src/render.zig` follow occupied alpha bounds with a two-pixel guard.

| Asset | Atlas | Presentation | Collision body |
| --- | --- | --- | --- |
| `resources/textures/open-wheel.png` | 1254 × 1254; two vehicles | 38 × 88 pixels, orange/carbon and ivory/teal | 38 × 88, with the shared two-pixel inset |
| `resources/textures/pedestrians.png` | 1536 × 1024; three appearances × four poses | Constant 0.11 scale; roughly 20–33 × 20–26 pixels | 18 × 18, with a two-pixel inset around the torso |

The pedestrian rows wear terracotta, turquoise, and mustard clothing, with different hair, skin, and headwear. Each row supplies a raised-hand warning, crouched preparation, and two alternating strides. Frames change on simulation ticks. Right-side pedestrians face inward; retreating pedestrians face outward. Hops add a small visual arc over a grounded shadow. Contact produces a retreat, orbiting stars, and “WHOOPS!” feedback.

Open-wheel silhouettes include exposed tires, wings, suspension, and a helmet. Their longer body is shared with the collision system. Shadows use the actual silhouettes and the same downward/rightward offset as existing vehicles. Signals remain amber; the approach cue is cyan and includes words and arrows. The browser repeats the warnings as text outside the scaled canvas.

`scripts/generate-encounter-audio.py` reproduces all four original 22,050 Hz, mono, 16-bit PCM sounds:

- `open-wheel.wav`: seamless two-second harmonic engine loop with a 185 Hz fundamental, distinct from the player's 55 Hz loop. Pitch, distance, and passing direction affect presentation only.
- `pedestrian-alert.wav`: two ascending warning notes.
- `fast-alert.wav`: a higher two-note approach cue.
- `whoops.wav`: a short elastic tone for pedestrian contact.

`build.zig` registers every resource. Emscripten preloads the entire `resources` directory. Rendering and audio use no simulation random numbers.

## Generation prompts

Mode: built-in ImageGen; no API/CLI fallback or hand-painted replacement assets. The pedestrian generation needed camera and background corrections; rejected RGB sheets are not shipped.

Open-wheel atlas (style reference: `resources/textures/cars.png`):

```text
Use case: stylized-concept. Asset type: production transparent sprite sheet for Tiny Car, a detailed top-down racing game. Generate TWO unbranded Formula One-style open-wheel race cars on a genuinely transparent background, arranged side by side in one horizontal row with wide clear gutters, both noses pointing straight UP, exact orthographic overhead view. Left car bright papaya orange with black carbon wings and turquoise accents; right car ivory and deep teal with copper accents. Each car has four clearly exposed black slick tires, narrow long nose, wide front wing, visible helmet in open cockpit, rear wing and fine suspension details. Match the supplied reference's polished detailed painted/realistic miniature game art, sharp silhouette, subtle upper-left highlights and material texture, no perspective tilt. Entire vehicles visible, equal scale. No ground, no background color, no text, no logos, no ambient glow or cast shadows (engine draws shadow separately). Canvas 1024x1024, two isolated cars centered at x=256 and 768, each about 310px wide by 700px tall. Reference image is only style reference, do not reproduce its closed-wheel cars.
```

Pedestrian atlas initial generation (same style reference):

```text
Use case: stylized-concept. Asset type: transparent animation sprite atlas for a detailed top-down racing game. Create exactly TWELVE isolated pedestrian animation frames arranged in a strict 4 columns x 3 rows evenly spaced grid on a genuinely transparent 1536x1024 background. Orthographic directly overhead camera (see crown of head, shoulders, arms and shoes, no front-facing portraits). Every person is facing RIGHT, moving to the right; all frames identical scale and centered in each cell. Row 1: adult with terracotta jacket, dark trousers, dark brown hair, medium skin. Row 2: adult with turquoise sports jacket, navy shorts, light skin, light cap. Row 3: adult with mustard yellow hoodie, charcoal trousers, dark skin, dark curly hair. Each row repeats exactly the same character for four animation poses: column 1 idle looking toward right with one hand raised to signal intent; column 2 crouching/preparing to dash, knees bent and arms drawn back; column 3 running/jumping right with left arm forward and legs apart; column 4 running right with right arm forward and opposite leg stride. Detailed realistic miniature game art with cloth folds and subtle upper-left lighting, match supplied cars reference style. Clean transparent silhouettes, feet/arms/head complete and separated from other cells by generous empty gutters. No text, no grid lines, no background, no props, no cars, no cast shadows (renderer adds shadows). Humans seen from precisely above so their projected footprint is compact, NOT tall standing character side view. Reference image is style reference only.
```

Camera correction:

```text
Correct this pedestrian sprite sheet. Keep the same THREE adult appearances and 4-column x 3-row layout, but change the CAMERA TO EXACTLY VERTICAL OVERHEAD, a 90-degree bird's-eye view: mainly the crown of the head, round shoulders, bent arms and feet projecting slightly beyond the body. We should not see large backs or full tall leg lengths; projected human footprint should be compact like a person viewed from a drone straight above. All characters face and travel RIGHT. Four poses per row: raised-hand warning, crouched preparation, dash left foot, dash right foot. Same costumes: terracotta jacket brown hair; turquoise jacket light cap; mustard hoodie dark curls. Detailed realistic painted miniature top-down game art, upper-left highlights. CRITICAL: deliver actual RGBA transparency with zero-alpha empty pixels. Remove the entire gray/white checkerboard; do NOT draw checker squares, white background, gradients, or shadows. Keep each pose isolated in its cell with large transparent margins, equal head size in all 12 frames. No other objects, labels, or grid lines.
```

Final alpha correction:

```text
Use case: background-extraction. Remove the entire checkerboard background from this sprite sheet and make the empty space genuinely transparent in the output alpha channel. Preserve all 12 human sprites in precisely the same 4x3 arrangement, same colors, poses, positions, sizes, and fine edges. The checkerboard is a fake background that must be deleted, not reproduced. Output a transparent PNG cutout sprite atlas, no white or checkerboard background. Do not change the people.
```
