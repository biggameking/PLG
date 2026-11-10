// Pal sprites: real pixel art — a 24x20 pixel buffer per body plan,
// shaded with hue-shifted palette ramps (outline/shade/base/light/spec),
// checkerboard dithering on fluffy species, baked to a tiny canvas then
// blitted 3x nearest-neighbor. Silhouette + palette + parts per species
// keeps 100+ species distinguishable.
import { Pal } from "./types.ts";
import { Species } from "../data/species.ts";
import { ELEMENT_COLOR } from "../data/elements.ts";
import { Renderer, CELL_W, CELL_H } from "../engine/renderer.ts";
import { hash2 } from "../engine/rng.ts";

const W = 40, H = 32;
const SCALE = 3;      // screen px per sprite pixel (pals)
const HUMAN_SCALE = 2; // player draws smaller so monsters tower

// pixel indices: 1 primary, 2 secondary, 3 accent, 4 dark, 5 white
type Pix = Uint8Array; // W*H

function newPix(): Pix { return new Uint8Array(W * H); }
function set(b: Pix, x: number, y: number, c: number): void {
  if (x >= 0 && x < W && y >= 0 && y < H) b[y * W + x] = c;
}
function rect(b: Pix, x0: number, y0: number, x1: number, y1: number, c: number): void {
  for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) set(b, x, y, c);
}
function ellipse(b: Pix, cx: number, cy: number, rx: number, ry: number, c: number): void {
  for (let y = Math.floor(cy - ry); y <= cy + ry; y++)
    for (let x = Math.floor(cx - rx); x <= cx + rx; x++) {
      const dx = (x - cx) / rx, dy = (y - cy) / ry;
      if (dx * dx + dy * dy <= 1) set(b, x, y, c);
    }
}
function disc(b: Pix, cx: number, cy: number, r: number, c: number): void { ellipse(b, cx, cy, r, r, c); }
// scatter spikes along top edge of body
function spikes(b: Pix, x0: number, x1: number, y: number, c: number): void {
  for (let x = x0; x <= x1; x++) { set(b, x, y - ((x - x0) % 2), c); set(b, x, y - 1 - ((x - x0) % 2), c); }
}

// ---- body plans: each draws into a 40x32 buffer; f = walk frame 0/1 ----
// legs get +1/-1 px per frame; heads face right (dir>0), flipped on draw.
const PLANS: Record<string, (b: Pix, f: number) => void> = {
  quadruped(b, f) {
    const s = f ? 1 : 0;
    // legs with hoof accents
    rect(b, 8, 24 + s, 10, 30 + s, 1); rect(b, 14, 24 + (1 - s), 16, 30 + (1 - s), 1);
    rect(b, 22, 24 + (1 - s), 24, 30 + (1 - s), 1); rect(b, 28, 24 + s, 30, 30 + s, 1);
    rect(b, 8, 30 + s, 10, 31 + s, 3); rect(b, 14, 30 + (1 - s), 16, 31 + (1 - s), 3);
    rect(b, 22, 30 + (1 - s), 24, 31 + (1 - s), 3); rect(b, 28, 30 + s, 30, 31 + s, 3);
    ellipse(b, 18, 19, 12, 7, 1);                    // body
    ellipse(b, 17, 22, 8, 4, 2);                     // belly
    disc(b, 29, 11, 6, 1);                           // head
    rect(b, 24, 3, 26, 8, 3); rect(b, 25, 5, 25, 7, 4); // ear L + inner
    rect(b, 32, 3, 34, 8, 3); rect(b, 33, 5, 33, 7, 4); // ear R + inner
    set(b, 29, 9, 4); set(b, 30, 8, 5); set(b, 30, 10, 4); // eye + glint
    set(b, 34, 13, 4); set(b, 34, 14, 4);            // nostril + mouth
    rect(b, 5, 15, 7, 19, 3); set(b, 4, 17, 5);      // tail + tuft tip
    set(b, 12, 15, 2); set(b, 15, 17, 2); set(b, 10, 20, 2); // flank marks
  },
  kitty(b, f) {
    const s = f ? 1 : 0;
    rect(b, 12, 24 + s, 14, 30 + s, 1); rect(b, 24, 24 + (1 - s), 26, 30 + (1 - s), 1);
    rect(b, 12, 30 + s, 14, 31 + s, 3); rect(b, 24, 30 + (1 - s), 26, 31 + (1 - s), 3); // paws
    ellipse(b, 17, 20, 10, 6, 1);                    // body
    ellipse(b, 17, 22, 7, 3, 2);                     // belly
    disc(b, 28, 11, 5, 1);                           // head
    rect(b, 23, 4, 25, 8, 3); set(b, 24, 6, 4);      // ear L (triangle-ish) + inner
    rect(b, 31, 4, 33, 8, 3); set(b, 32, 6, 4);      // ear R + inner
    rect(b, 5, 6, 7, 15, 3); set(b, 5, 4, 5); set(b, 6, 4, 3); // upright tail + white tip
    set(b, 28, 10, 4); set(b, 29, 9, 5); set(b, 29, 11, 4);  // eye + glint
    set(b, 32, 13, 4); set(b, 33, 13, 4);            // nose
    set(b, 33, 15, 4);                               // mouth hint
    set(b, 13, 16, 3); set(b, 16, 15, 3); set(b, 19, 16, 3); // back stripes
  },
  bird(b, f) {
    const s = f ? 1 : 0;
    rect(b, 16, 26 + s, 17, 29 + s, 4); rect(b, 15, 30 + s, 18, 30 + s, 4); // leg L + foot
    rect(b, 21, 26 + (1 - s), 22, 29 + (1 - s), 4); rect(b, 20, 30 + (1 - s), 23, 30 + (1 - s), 4); // leg R + foot
    ellipse(b, 19, 18, 9, 9, 1);                     // round body
    ellipse(b, 19, 21, 6, 5, 2);                     // belly
    ellipse(b, 14, 17, 4, 6, 2);                     // wing
    set(b, 13, 21, 3); set(b, 13, 22, 3); set(b, 15, 23, 3);   // wing tip feathers
    disc(b, 21, 7, 5, 1);                            // head on top
    rect(b, 26, 6, 30, 9, 3); set(b, 31, 7, 3);      // beak + tip
    set(b, 21, 6, 4); set(b, 22, 5, 5); set(b, 22, 7, 4); // eye + glint
    set(b, 19, 1, 3); set(b, 21, 0, 3); set(b, 23, 1, 3); // crown tuft
    rect(b, 8, 15, 10, 21, 3); set(b, 8, 22, 3);     // tail feathers
  },
  mouse(b, f) {
    const s = f ? 1 : 0;
    rect(b, 14, 26 + s, 16, 29 + s, 1); rect(b, 20, 26 + (1 - s), 22, 29 + (1 - s), 1);
    rect(b, 14, 29 + s, 16, 30 + s, 3); rect(b, 20, 29 + (1 - s), 22, 30 + (1 - s), 3); // feet
    disc(b, 18, 20, 8, 1);                           // body
    disc(b, 18, 23, 5, 2);                           // belly
    disc(b, 26, 14, 5, 1);                           // head
    disc(b, 22, 7, 4, 3); disc(b, 22, 7, 2, 4);      // big ear L + inner
    disc(b, 30, 7, 4, 3); disc(b, 30, 7, 2, 4);      // big ear R + inner
    rect(b, 8, 22, 11, 24, 3); set(b, 7, 21, 3); set(b, 6, 20, 3); // curling thin tail
    set(b, 26, 13, 4); set(b, 27, 12, 5);            // eye + glint
    set(b, 30, 15, 4); set(b, 29, 17, 5);            // nose + bucktooth
    set(b, 15, 14, 2); set(b, 18, 12, 2);            // back shading marks
  },
  hedgehog(b, f) {
    const s = f ? 1 : 0;
    rect(b, 11, 27 + s, 13, 30 + s, 2); rect(b, 22, 27 + (1 - s), 24, 30 + (1 - s), 2); // feet
    ellipse(b, 19, 21, 13, 7, 1);                    // body
    ellipse(b, 19, 24, 9, 3, 2);                     // belly
    // two quill rows along the back
    for (let x = 8; x <= 30; x++) { set(b, x, 15 - (x % 3), 3); set(b, x, 14 - (x % 3), 3); }
    for (let x = 11; x <= 27; x++) set(b, x, 11 - (x % 3), 3);
    disc(b, 31, 19, 5, 1);                           // snout head
    set(b, 31, 17, 4); set(b, 32, 16, 5);            // eye + glint
    set(b, 35, 20, 4); set(b, 35, 21, 4);            // nose
    set(b, 33, 23, 4);                               // mouth
  },
  deer(b, f) {
    const s = f ? 1 : 0;
    rect(b, 8, 24 + s, 10, 30 + s, 1); rect(b, 14, 24 + (1 - s), 16, 30 + (1 - s), 1);
    rect(b, 23, 24 + (1 - s), 25, 30 + (1 - s), 1); rect(b, 29, 24 + s, 31, 30 + s, 1);
    rect(b, 8, 30 + s, 10, 31 + s, 4); rect(b, 14, 30 + (1 - s), 16, 31 + (1 - s), 4); // hooves
    rect(b, 23, 30 + (1 - s), 25, 31 + (1 - s), 4); rect(b, 29, 30 + s, 31, 31 + s, 4);
    ellipse(b, 18, 19, 11, 7, 1);                    // body
    ellipse(b, 17, 22, 8, 4, 2);                     // belly
    disc(b, 29, 11, 5, 1);                           // head
    rect(b, 32, 12, 34, 14, 2);                      // snout
    set(b, 34, 13, 4);                               // nose
    // branching antlers
    rect(b, 25, 2, 26, 6, 3); set(b, 24, 1, 3); set(b, 23, 2, 3); set(b, 27, 2, 3); set(b, 28, 1, 3);
    rect(b, 31, 2, 32, 6, 3); set(b, 30, 1, 3); set(b, 33, 2, 3); set(b, 34, 1, 3);
    set(b, 29, 9, 4); set(b, 30, 8, 5);              // eye + glint
    set(b, 5, 16, 3); set(b, 4, 15, 3);              // stub tail
    set(b, 11, 15, 2); set(b, 15, 13, 2); set(b, 19, 15, 2); set(b, 13, 18, 2); // flank spots
  },
  boar(b, f) {
    const s = f ? 1 : 0;
    rect(b, 8, 24 + s, 10, 30 + s, 1); rect(b, 14, 24 + (1 - s), 16, 30 + (1 - s), 1);
    rect(b, 23, 24 + (1 - s), 25, 30 + (1 - s), 1); rect(b, 30, 24 + s, 32, 30 + s, 1);
    rect(b, 8, 30 + s, 10, 31 + s, 4); rect(b, 14, 30 + (1 - s), 16, 31 + (1 - s), 4); // hooves
    rect(b, 23, 30 + (1 - s), 25, 31 + (1 - s), 4); rect(b, 30, 30 + s, 32, 31 + s, 4);
    ellipse(b, 18, 20, 12, 7, 1);                    // body
    ellipse(b, 17, 23, 9, 4, 2);                     // belly
    rect(b, 10, 11, 25, 14, 3);                      // mane ridge
    for (let x = 10; x <= 25; x += 2) set(b, x, 10, 3); // mane spikes
    rect(b, 27, 13, 34, 20, 1);                      // head block
    rect(b, 33, 16, 36, 19, 2);                      // snout
    set(b, 35, 17, 4);                               // nostril
    set(b, 30, 20, 5); set(b, 31, 20, 5); set(b, 30, 21, 5); // tusk
    set(b, 30, 14, 4); set(b, 31, 13, 5);            // eye + glint
    set(b, 28, 12, 3);                               // small ear
    set(b, 5, 16, 3); set(b, 4, 15, 3); set(b, 5, 14, 3); // curly tail
  },
  cow(b, f) {
    const s = f ? 1 : 0;
    rect(b, 8, 24 + s, 10, 30 + s, 1); rect(b, 14, 24 + (1 - s), 16, 30 + (1 - s), 1);
    rect(b, 23, 24 + (1 - s), 25, 30 + (1 - s), 1); rect(b, 29, 24 + s, 31, 30 + s, 1);
    rect(b, 8, 30 + s, 10, 31 + s, 4); rect(b, 14, 30 + (1 - s), 16, 31 + (1 - s), 4); // hooves
    rect(b, 23, 30 + (1 - s), 25, 31 + (1 - s), 4); rect(b, 29, 30 + s, 31, 31 + s, 4);
    ellipse(b, 18, 20, 12, 7, 1);                    // body
    ellipse(b, 17, 23, 9, 4, 2);                     // belly
    disc(b, 30, 10, 5, 1);                           // head
    rect(b, 25, 3, 27, 6, 3); rect(b, 33, 3, 35, 6, 3); // horns
    set(b, 24, 9, 2); set(b, 35, 9, 2);              // ears
    rect(b, 31, 13, 34, 16, 2);                      // muzzle
    set(b, 33, 14, 4); set(b, 34, 14, 4);            // nostrils
    set(b, 30, 9, 4); set(b, 31, 8, 5);              // eye + glint
    disc(b, 12, 16, 3, 2); disc(b, 20, 21, 2, 2); disc(b, 9, 21, 2, 2); // spots
    rect(b, 5, 15, 6, 22, 3); set(b, 5, 23, 3); set(b, 6, 23, 3); // tail + tuft
    set(b, 19, 27, 3); set(b, 21, 27, 3);            // udder hint
  },
  monkey(b, f) {
    const s = f ? 1 : 0;
    rect(b, 15, 26 + s, 17, 30 + s, 1); rect(b, 19, 26 + (1 - s), 21, 30 + (1 - s), 1);
    rect(b, 15, 30 + s, 17, 31 + s, 3); rect(b, 19, 30 + (1 - s), 21, 31 + (1 - s), 3); // feet
    ellipse(b, 18, 18, 8, 8, 1);                     // upright body
    disc(b, 18, 20, 4, 2);                           // belly patch
    rect(b, 10, 15 + s, 12, 21 + s, 1); set(b, 11, 22 + s, 3);  // arm L + hand
    rect(b, 25, 15 + (1 - s), 27, 21 + (1 - s), 1); set(b, 26, 22 + (1 - s), 3); // arm R + hand
    disc(b, 18, 7, 5, 1);                            // head on top
    disc(b, 18, 8, 3, 2);                            // face mask
    disc(b, 13, 6, 2, 3); disc(b, 23, 6, 2, 3);      // round ears
    set(b, 17, 6, 4); set(b, 18, 5, 5); set(b, 20, 6, 4); // eyes + glint
    set(b, 18, 10, 4);                               // mouth
    // curled tail
    set(b, 9, 22, 3); set(b, 8, 21, 3); set(b, 8, 19, 3); set(b, 9, 18, 3); set(b, 11, 19, 3); set(b, 10, 20, 3);
  },
  blob(b, f) {
    const s = f ? 1 : 0;
    ellipse(b, 19, 22, 12, 8, 1);                    // wide base
    ellipse(b, 19, 15 + s, 9, 7, 1);                 // upper dome squishes
    ellipse(b, 19, 24, 8, 4, 2);                     // belly
    set(b, 15, 14 + s, 4); set(b, 16, 13 + s, 5);    // eye L + glint
    set(b, 23, 14 + s, 4); set(b, 24, 13 + s, 5);    // eye R + glint
    rect(b, 17, 18 + s, 21, 19 + s, 4);              // droopy mouth
    set(b, 18, 7 + s, 3); set(b, 19, 8 + s, 3); set(b, 19, 6 + s, 3); // top drip
    set(b, 8, 20, 1); set(b, 7, 19, 1);              // arm stub L
    set(b, 30, 20, 1); set(b, 31, 19, 1);            // arm stub R
    set(b, 13, 30, 1); set(b, 19, 30, 1); set(b, 25, 30, 1); // drips at base
  },
  serpent(b, f) {
    // S-curve body: discs along a sine path, thicker at head
    const pts: [number, number, number][] = [[6, 26, 4], [11, 23 + f, 5], [17, 19, 5], [24, 15 - f, 5], [30, 10, 6]];
    for (const [x, y, r] of pts) disc(b, x, y, r, 1);
    disc(b, 30, 9, 6, 1);                            // head
    rect(b, 25, 1, 27, 5, 3); set(b, 31, 0, 3); set(b, 32, 1, 3); // crest horns
    set(b, 30, 7, 4); set(b, 31, 6, 5);              // eye + glint
    set(b, 34, 10, 4); set(b, 34, 12, 5);            // nostril + fang
    set(b, 2, 26, 3); set(b, 1, 25, 3);              // tail tip
    ellipse(b, 17, 21, 10, 4, 2);                    // belly shade
    set(b, 13, 20, 3); set(b, 26, 13, 3);            // side fins/accents
    set(b, 10, 24, 2); set(b, 21, 17, 2);            // scale marks
  },
  human(b, f) {
    const s = f ? 1 : 0;
    rect(b, 15, 25 + s, 17, 30 + s, 2);              // leg L (pants)
    rect(b, 21, 25 + (1 - s), 23, 30 + (1 - s), 2);  // leg R
    rect(b, 15, 30 + s, 17, 31 + s, 4);              // boot L
    rect(b, 21, 30 + (1 - s), 23, 31 + (1 - s), 4);  // boot R
    ellipse(b, 19, 17, 7, 7, 1);                     // torso (tunic)
    ellipse(b, 19, 22, 6, 4, 1);                     // tunic skirt
    rect(b, 14, 23, 24, 24, 4);                      // belt
    rect(b, 11, 14 + s, 13, 20 + s, 1); set(b, 12, 21 + s, 3);       // arm L + hand
    rect(b, 25, 14 + (1 - s), 27, 20 + (1 - s), 1); set(b, 26, 21 + (1 - s), 3); // arm R + hand
    disc(b, 19, 6, 5, 3);                            // head (skin)
    rect(b, 14, 0, 24, 4, 4);                        // hair cap
    set(b, 15, 5, 4); set(b, 14, 6, 4);              // sideburn
    set(b, 21, 5, 4); set(b, 22, 5, 5);              // eye + glint
    set(b, 22, 8, 4);                                // mouth hint
  },
  ghost(b, f) {
    const s = f ? 1 : 0;
    ellipse(b, 19, 14 + s, 11, 9, 1);                // dome
    // wavy trailing bottom with dangling tips
    for (let x = 9; x <= 29; x++) set(b, x, 22 + s + ((x % 2) ? 1 : 0), 1);
    for (let x = 10; x <= 28; x += 2) set(b, x, 23 + s + ((x % 4) ? 1 : 0), 1);
    set(b, 11, 25 + s, 1); set(b, 19, 25 + s, 1); set(b, 26, 25 + s, 1); // drip tips
    disc(b, 15, 13 + s, 2, 4); set(b, 16, 12 + s, 5); // big eye L
    disc(b, 23, 13 + s, 2, 4); set(b, 24, 12 + s, 5); // big eye R
    set(b, 19, 17 + s, 4); set(b, 20, 17 + s, 4);    // mouth
    set(b, 13, 16 + s, 2); set(b, 25, 16 + s, 2);    // blush marks
    set(b, 7, 15 + s, 3); set(b, 6, 14 + s, 3);      // wisp L
    set(b, 31, 15 + s, 3); set(b, 32, 14 + s, 3);    // wisp R
  },
};

interface SpriteDef { plan: keyof typeof PLANS; colors: [string, string, string]; fluff?: number }

const SPRITES: Record<string, SpriteDef> = {
  fenjelly:     { plan: "quadruped", colors: ["#ede0c8", "#d8c9ab", "#f2a0b5"], fluff: 0.55 },
  puffmite:     { plan: "kitty",     colors: ["#f2a0b5", "#e085a0", "#ffffff"], fluff: 0.3 },
  fenlump:     { plan: "bird",      colors: ["#f5f2ea", "#e8e0cc", "#e64533"], fluff: 0.25 },
  cindlump:    { plan: "kitty",     colors: ["#e8963c", "#c97e2a", "#ffd54f"], fluff: 0.3 },
  corlmite:   { plan: "bird",      colors: ["#4d9de0", "#2b5d8a", "#e8d44d"] },
  marlump:     { plan: "bird",      colors: ["#3f94c8", "#2b5d8a", "#ffd54f"], fluff: 0.15 },
  dozantler: { plan: "deer",      colors: ["#d4b96e", "#b8945a", "#8a6d4d"] },
  sprigmelt:     { plan: "mouse",     colors: ["#4caf50", "#3d9143", "#9acd32"] },
  briargoo:      { plan: "monkey",    colors: ["#9acd32", "#7a9d2a", "#d4b96e"], fluff: 0.2 },
  voltgoo:     { plan: "mouse",     colors: ["#e8d44d", "#c9b23a", "#ff9a3c"], fluff: 0.2 },
  faradlump:     { plan: "hedgehog",  colors: ["#e8e05c", "#c9bf45", "#8a6d4d"], fluff: 0.4 },
  loammelt:       { plan: "serpent",   colors: ["#b8935f", "#96794d", "#8fd1a0"] },
  shademite:    { plan: "blob",      colors: ["#6fa8d1", "#5a8db0", "#4d6f8a"] },
  shadelump:    { plan: "ghost",     colors: ["#c678dd", "#a45ec0", "#e08ee8"], fluff: 0.25 },
  shademelt:         { plan: "kitty",     colors: ["#a8b5c4", "#8a98a8", "#e8d44d"] },
  loampuff:     { plan: "boar",      colors: ["#d1813c", "#a96a2f", "#f5eee0"], fluff: 0.3 },
  nibjelly:      { plan: "kitty",     colors: ["#f5eee0", "#d8d0be", "#e8963c"], fluff: 0.45 },
  piplump:   { plan: "cow",       colors: ["#ede0c8", "#c9b89e", "#e8d44d"], fluff: 0.2 },
  quackbill:       { plan: "bird",      colors: ["#4dd0e1", "#35a8b8", "#e8d44d"], fluff: 0.2 },
  $player:     { plan: "human",     colors: ["#d17b3c", "#4d9de0", "#e8c9a0"] },
};

function darken(hex: string, f: number): string { return shade(hex, f); }
function dim(hex: string): string { return darken(hex, 0.45); }
function shade(hex: string, f: number): string {
  const m = /^#(..)(..)(..)$/.exec(hex);
  if (!m) return hex;
  const c = (i: number) => Math.max(0, Math.min(255, Math.floor(parseInt(m[i], 16) * f)));
  return `rgb(${c(1)},${c(2)},${c(3)})`;
}

// ---- palette ramps with hue shifting (shadows → purple, lights → warm) ----
function hsl(hex: string): [number, number, number] {
  const m = /^#(..)(..)(..)$/.exec(hex); if (!m) return [0, 0, 0.5];
  const r = parseInt(m[1], 16) / 255, g = parseInt(m[2], 16) / 255, b = parseInt(m[3], 16) / 255;
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2;
  if (mx === mn) return [0, 0, l];
  const d = mx - mn;
  const s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
  const h = mx === r ? ((g - b) / d + 6) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [h * 60, s, l];
}
function rgb(h: number, s: number, l: number): [number, number, number] {
  h = ((h % 360) + 360) % 360; s = Math.max(0, Math.min(1, s)); l = Math.max(0, Math.min(1, l));
  const c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = l - c / 2;
  const [r, g, b] = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x] : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
  return [Math.round((r + m) * 255), Math.round((g + m) * 255), Math.round((b + m) * 255)];
}
interface Ramp { out: [number, number, number]; shade: [number, number, number]; base: [number, number, number]; light: [number, number, number]; spec: [number, number, number] }
const rampCache = new Map<string, Ramp>();
function ramp(hex: string): Ramp {
  let r = rampCache.get(hex);
  if (r) return r;
  const [h, s, l] = hsl(hex);
  r = {
    out: rgb(h + 25, Math.min(1, s * 1.1), l * 0.22),
    shade: rgb(h + 14, Math.min(1, s * 1.15), l * 0.55),
    base: rgb(h, s, l),
    light: rgb(h - 12, Math.min(1, s * 1.05), Math.min(0.88, l * 1.3)),
    spec: rgb(h - 25, s * 0.45, 0.93),
  };
  rampCache.set(hex, r);
  return r;
}
const DARK: Ramp = { out: rgb(230, 0.15, 0.06), shade: rgb(230, 0.15, 0.1), base: rgb(25, 0.12, 0.14), light: rgb(25, 0.1, 0.22), spec: rgb(30, 0.1, 0.4) };
const WHITE: Ramp = { out: rgb(220, 0.25, 0.3), shade: rgb(215, 0.2, 0.72), base: rgb(0, 0, 1), light: rgb(0, 0, 1), spec: rgb(0, 0, 1) };

// cache: speciesId -> [frame0, frame1] canvases
const texCache = new Map<string, [HTMLCanvasElement, HTMLCanvasElement]>();

function buildTex(_r: Renderer, id: string, frame: number): HTMLCanvasElement {
  const def = SPRITES[id];
  const b = newPix();
  PLANS[def.plan](b, frame);
  const cvs = document.createElement("canvas");
  cvs.width = W; cvs.height = H;
  const c2 = cvs.getContext("2d")!;
  const img = c2.createImageData(W, H);
  const ramps = [ramp(def.colors[0]), ramp(def.colors[1]), ramp(def.colors[2]), DARK, WHITE];
  const at = (x: number, y: number) => (x < 0 || x >= W || y < 0 || y >= H ? 0 : b[y * W + x]);
  const fluff = def.fluff ?? 0;
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const c = at(x, y);
    if (!c) continue;
    const h = hash2(x * 7 + 3, y * 7 + 1, 31);
    const open = !at(x - 1, y) || !at(x + 1, y) || !at(x, y - 1) || !at(x, y + 1);
    const rp = ramps[c - 1];
    // light field: stronger top & upper-left, dimmer bottom-right
    const lf = (1 - y / H) * 0.62 + (1 - x / W) * 0.14 + (h - 0.5) * 0.16;
    let px: [number, number, number];
    if (open) px = rp.out;
    else if (lf > 0.8) px = rp.spec;
    else if (lf > 0.62) px = rp.light;
    else if (lf < 0.26) px = rp.shade;
    else {
      // dithered transitions + fur texture
      const nearHi = 0.62 - lf < 0.09, nearLo = lf - 0.26 < 0.09;
      const dither = ((x + y) % 2 === 0) && (nearHi || nearLo || h < fluff);
      px = dither ? (nearHi ? rp.light : rp.shade) : rp.base;
    }
    const o = (y * W + x) * 4;
    img.data[o] = px[0]; img.data[o + 1] = px[1]; img.data[o + 2] = px[2]; img.data[o + 3] = 255;
  }
  c2.putImageData(img, 0, 0);
  return cvs;
}

function tex(r: Renderer, id: string, frame: number): HTMLCanvasElement | null {
  if (!SPRITES[id]) return null;
  let t = texCache.get(id);
  if (!t) { t = [buildTex(r, id, 0), buildTex(r, id, 1)]; texCache.set(id, t); }
  return t[frame];
}

const lastPos = new Map<number, { x: number; y: number }>();

/** Draw a pal's pixel-art sprite, anchored bottom-center at its position. */
export function drawPal(r: Renderer, p: Pal, sp: Species, camX: number, camY: number, time: number, asleep: boolean): void {
  const def = SPRITES[p.speciesId];
  if (!def) {
    r.tileAt(p.x - 0.5, p.y - 0.5, sp.glyph, asleep ? "#4d565c" : sp.color);
    return;
  }
  const prev = lastPos.get(p.uid);
  const moving = prev ? Math.hypot(p.x - prev.x, p.y - prev.y) > 0.02 : false;
  lastPos.set(p.uid, { x: p.x, y: p.y });
  const frame = moving ? Math.floor(time * 6 + p.uid) % 2 : 0;
  const img = tex(r, p.speciesId, frame)!;

  const dw = W * SCALE, dh = H * SCALE;
  const bob = moving && frame === 1 ? -4 : (asleep ? 3 : 0);
  const dx = p.x * CELL_W - dw / 2 - camX;
  const dy = p.y * CELL_H - dh + CELL_H - camY + bob;

  const ctx = r.ctx;
  ctx.save();
  ctx.imageSmoothingEnabled = false;
  if (asleep) ctx.globalAlpha = 0.55;
  if (p.dir < 0) {
    ctx.translate(dx + dw / 2, 0); ctx.scale(-1, 1); ctx.translate(-(dx + dw / 2), 0);
  }
  ctx.drawImage(img, dx, dy, dw, dh);
  ctx.restore();

  // element badge: small pixel orb w/ outline + shine, floating by the head
  const el = sp.elements[0];
  const col = ELEMENT_COLOR[el];
  const bx = p.x * CELL_W + (p.dir < 0 ? -dw / 2 - 6 : dw / 2 + 4) - camX;
  const by = dy - CELL_H * 0.55;
  ctx.save();
  ctx.globalAlpha = asleep ? 0.55 : 1;
  ctx.fillStyle = "#1a1d20";
  ctx.beginPath(); ctx.arc(bx + 5, by + 5, 5, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = col;
  ctx.beginPath(); ctx.arc(bx + 5, by + 5, 4, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = shade(col, 1.5);
  ctx.beginPath(); ctx.arc(bx + 3.5, by + 3.5, 1.5, 0, Math.PI * 2); ctx.fill();
  ctx.restore();
}

/** Draw the player as a pixel human, anchored bottom-center. */
export function drawHuman(r: Renderer, x: number, y: number, dir: number, camX: number, camY: number, time: number, moving: boolean): void {
  const frame = moving ? Math.floor(time * 6) % 2 : 0;
  const img = tex(r, "$player", frame)!;
  const dw = W * HUMAN_SCALE, dh = H * HUMAN_SCALE;
  const bob = moving && frame === 1 ? -3 : 0;
  const dx = x * CELL_W - dw / 2 - camX;
  const dy = y * CELL_H - dh + CELL_H - camY + bob;
  const ctx = r.ctx;
  ctx.save();
  ctx.imageSmoothingEnabled = false;
  if (dir < 0) {
    ctx.translate(dx + dw / 2, 0); ctx.scale(-1, 1); ctx.translate(-(dx + dw / 2), 0);
  }
  ctx.drawImage(img, dx, dy, dw, dh);
  ctx.restore();
}
