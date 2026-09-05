# Tiny Car v3 art

The built-in ImageGen tool generated all four PNG assets on September 5, 2026. The project uses the generated RGBA files directly. The alpha channel supplies transparent vehicle and tree silhouettes. No background removal or hand-drawn replacement changes the generated art.

The renderer draws the six vehicles at the same 38 by 72 pixel size. The first sprite is the player. Five other sprites supply traffic colors and body shapes. Four tree crowns vary roadside silhouettes. All source rectangles live in `src/render.zig` and include a small edge guard around the occupied alpha bounds.

| Asset | File size in pixels | Use |
| --- | --- | --- |
| `resources/textures/cars.png` | 1536 × 1024 | Player and five traffic vehicles |
| `resources/textures/trees.png` | 1254 × 1254 | Four tree crowns |
| `resources/textures/grass.png` | 1254 × 1254 | Ground material |
| `resources/textures/road.png` | 1254 × 1254 | Asphalt material |

Grass and asphalt tiles alternate reflection at runtime. Adjacent tiles share the same edge pixels. This removes hard joins and works without repeating non-power-of-two textures in WebGL. The renderer applies quiet color tints and uses bilinear filtering. Shadows share the silhouettes and point down and right, consistent with light from the upper left.

The old standalone player sprite and pear texture are removed. The player now uses the vehicle atlas. The old long speeding recording is replaced by `resources/sound/engine.wav`, a two-second synthesized harmonic loop. `scripts/generate-engine.py` reproduces that loop. The existing brake and crash recordings remain.

## Generation prompts

These are the prompts supplied to the built-in tool. Requested image dimensions are hints. The table above lists the actual output dimensions.

### Vehicle atlas

```text
Use case: stylized-concept. Asset type: production sprite atlas for a polished top-down 2D driving game, with true transparent alpha background. Create exactly SIX recognizable modern passenger vehicles in a precise 3 columns by 2 rows atlas. Canvas 1536 wide by 1024 high, each cell 512 square. All cars centered in their cell, all noses point straight UP, exact orthographic overhead camera, no perspective, no side views. Consistent vehicle footprint about 200 pixels wide and 380 pixels long within each cell, fully separated with ample transparent margin. Order left to right then next row: vermilion red sport coupe with a pale cream single racing stripe (player); desaturated blue sedan; warm ivory hatchback; muted yellow station wagon; sage green compact SUV; silver gray coupe. Detailed premium hand-painted game illustration, crisp anti-aliased silhouettes, recognizable windshield and rear window, bonnet seams, mirrors, black tires, restrained highlights, tiny unlit red rear light lenses. Unified warm daylight from upper left. Rich material detail but legible at 38x70 pixels. No ground, no cast shadows, no checkerboard, no text, no numbers, no logos, no scenery. Transparent pixels everywhere outside vehicle silhouettes. All six are exactly top down at the same scale, front at top of image.
```

### Tree atlas

```text
Use case: stylized-concept. Production top-down game tree sprite atlas on TRUE TRANSPARENT BACKGROUND, exactly four individual tree crowns arranged a 2 by 2 grid on a 1024 square canvas, separated with ample transparent space. Orthographic directly overhead, no perspective. Each tree crown centered in its 512 square cell, about 380 pixels diameter. One rounded mature oak, one irregular maple, one dense blue-green pine crown, one light olive birch cluster. Premium detailed hand-painted game realism, smooth antialiased leaf silhouettes, varied organic clusters of visible leaves and tiny branches, unified soft warm daylight from upper left. Natural muted forest greens, distinct silhouettes, detailed but readable at 100 pixels. Match a refined hand-painted top-down racing game. No ground plane, no grass, no trunk extending sideways, no background colors, no glow, no shadows outside the tree, no checkerboard, no text, no photoreal aerial photographs. Transparent alpha everywhere outside the four tree silhouettes.
```

### Grass material

```text
Use case: stylized-concept. Asset type: seamless square 512x512 grass ground texture tile for a polished orthographic top-down driving game. Fine low contrast meadow grass in muted sage, olive and moss greens, tiny hand-painted blades and sparse tiny clover leaves, subtle natural variation at small scale. Detailed premium painted game art matching realistic hand-painted cars and trees. Uniform soft daylight from overhead upper-left but NO large shadows. Flat color distribution to all edges, perfectly tileable in both directions, edges match seamlessly. Every pixel filled with grass, no trees, no paths, no rocks, no flowers, no conspicuous tufts or clumps, no vignettes, no perspective, no photographic grain or muddy blurry photographic areas. Keep it quiet so traffic and road edges remain easy to see. Uniform seamless material tile, no borders.
```

### Asphalt material

```text
Use case: stylized-concept. Production seamless square asphalt material tile for a refined hand-painted top-down driving game. Uniform charcoal gray weathered tarmac with extremely subtle fine aggregate speckles, very faint narrow wear variation, dry smooth asphalt. Flat orthographic overhead lighting. Detailed hand-painted realism matching painted cars and foliage, not pixel art, not a photograph. Low contrast and quiet, clear hazards will be drawn above it. Perfect seamless repeat on all four edges, same brightness at every edge. Fill the entire image with asphalt only. NO road markings, no stripes, no road edges, no curbs, no potholes, no large cracks, no objects, no vignette, no dramatic light, no perspective, no borders. 512x512 square tile.
```
