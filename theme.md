# Society Management — Theme & Color Palette Reference

This document fully describes the visual identity of the **Society Management** Flutter app so it can be faithfully reproduced in a website (HTML/CSS/React/Vue/etc.).

All colors live in exactly one place in the app, `lib/theme/app_palette.dart`, under `AppPalette.light` and `AppPalette.dark`. Every widget reads from the active palette — there are **no hardcoded colors anywhere else**. The app ships with **Light**, **Dark** and **System** (follow device) modes, all driven by these two palettes.

---

## 1. Design philosophy

> **"A calm, neutral foundation layered under brand hues so the interface reads premium and professional instead of oversaturated."**

- **Low-contrast neutrals** (greys + hairlines) carry the layout: the canvas, cards and borders.
- **Brand color is used sparingly** for the most important interactive moments: the primary button, the selected nav item, focused input borders, the hero gradient.
- **Contain colour with alpha washes.** Icons and tags sit inside rounded containers tinted with the accent color at a low alpha (8–16%), never on saturated full-strength fills.
- **Two signature gradients** (linear, *top-left → bottom-right*) are used for identity moments: the hero balance card and the avatar.
- **Material 3** (`useMaterial3: true`) is the component language.

---

## 2. LIGHT MODE palette

### 2.1 Brand story
| Brand hue | Hex | Where it appears |
|---|---|---|
| Mint | `#E8FFCE` | Decorative circles on the hero card (12% alpha) |
| Aqua | `#ACFADF` | `secondaryContainer` wash; secondary icon accents |
| Periwinkle | `#94ADD7` | Secondary buttons, hero gradient **end**, stats |
| Violet | `#7C73C0` | **Primary** brand — buttons, links, focus states |
| Text navy | `#111844` | Intended dark-midnight brand; mirrored in dark mode canvas |

### 2.2 Full token table
| Token | Hex | Role |
|---|---|---|
| `canvas` | `#F3F4F8` | App background / scaffold |
| `card` | `#FFFFFF` | Cards, input fills, nav bar, bottom sheet |
| `cardMuted` | `#F1F2F7` | Muted chips and container surfaces |
| `hairline` | `#E6E8F0` | All borders, dividers, outlined buttons, outline variant |
| `primary` | `#7C73C0` | Primary buttons, links, selected states, switches |
| `onPrimary` | `#FFFFFF` | Text/icon on primary |
| `secondary` | `#94ADD7` | Secondary accents, secondaryContainer base |
| `onSecondary` | `#1B2340` | Text on secondary |
| `accent` | `#ACFADF` | Accent wash (secondaryContainer = 35% alpha of it) |
| `accentOn` | `#0E3A2E` | Text on accent wash |
| `mint` | `#E8FFCE` | Hero card decorative circles |
| `mintOn` | `#2C4A1E` | Text on mint |
| `textPrimary` | `#1E2240` | Headings, body, strong text |
| `textSecondary` | `#5E6480` | Subtitles, secondary body, icons (default) |
| `textTertiary` | `#9AA1BC` | Hints, timestamps, inactive nav labels |
| `success` | `#2F9E6E` | Positive status (e.g. safety notices) |
| `warning` | `#D99A2B` | Important / attention status |
| `danger` | `#D9534F` | Errors, destructive actions |
| `shadow` | `#16224D` | Soft card shadow (rendered at 4% alpha) |
| `heroStart` | `#7C73C0` | Hero gradient **start** |
| `heroEnd` | `#94ADD7` | Hero gradient **end** |

### 2.3 Categorical `featureColors` (service tiles)
8 desaturated accents assigned round-robin to grid tiles:

| Index | Hex |
|---|---|
| 0 | `#7C73C0` (violet) |
| 1 | `#5C8AD8` (blue) |
| 2 | `#2E9A8E` (teal) |
| 3 | `#7B61C4` (purple) |
| 4 | `#C98A3D` (amber) |
| 5 | `#C25E5E` (rust) |
| 6 | `#3F7FBF` (steel blue) |
| 7 | `#9B7AC0` (lavender) |

---

## 3. DARK MODE palette

### 3.1 Brand story
| Brand hue | Hex | Where it appears |
|---|---|---|
| Navy | `#111844` | **Canvas** — the whole app background |
| Indigo | `#4B5694` | Accent, avatar, hero gradient **start** |
| Steel | `#7288AE` | **Primary** brand in dark mode |
| Cream | `#EAE0CF` | Primary text and decorative circles |

Dark mode keeps the same architecture but inverts: deep navy surfaces, steel-blue primary, cream text. It is **not** a simple negative of light mode — it is a purpose-built night palette.

### 3.2 Full token table
| Token | Hex | Role |
|---|---|---|
| `canvas` | `#111844` | App background / scaffold |
| `card` | `#1C2557` | Cards, input fills, nav bar, bottom sheet |
| `cardMuted` | `#242F6A` | Muted chips and container surfaces |
| `hairline` | `#2B3574` | All borders and dividers |
| `primary` | `#7288AE` | Primary buttons, links, selected states |
| `onPrimary` | `#111844` | Text/icon on primary (dark on light button) |
| `secondary` | `#94ADD7` | Secondary accents |
| `onSecondary` | `#111844` | Text on secondary |
| `accent` | `#4B5694` | Accent wash (secondaryContainer = 35% alpha) |
| `accentOn` | `#EAE0CF` | Text on accent wash |
| `mint` | `#EAE0CF` | Hero card decorative circles |
| `mintOn` | `#1E2440` | Text on mint |
| `textPrimary` | `#EAE0CF` | Headings, body, strong text |
| `textSecondary` | `#AEB7DA` | Subtitles, secondary body, default icons |
| `textTertiary` | `#7E88B8` | Hints, timestamps, inactive nav |
| `success` | `#4FD0A0` | Positive status |
| `warning` | `#F0BD5E` | Important / attention |
| `danger` | `#F27084` | Errors, destructive actions |
| `shadow` | `#000000` | Card shadow (4% alpha) |
| `heroStart` | `#4B5694` | Hero gradient **start** |
| `heroEnd` | `#7288AE` | Hero gradient **end** |

### 3.3 Categorical `featureColors` (dark-tuned, brighter)
| Index | Hex |
|---|---|
| 0 | `#9A8CE8` |
| 1 | `#7BA4EC` |
| 2 | `#4CC3A6` |
| 3 | `#A58BE0` |
| 4 | `#E8B25E` |
| 5 | `#E77A7A` |
| 6 | `#6CA2FF` |
| 7 | `#BF9AE0` |

---

## 4. How colors are actually used (recipe patterns)

These are the exact composite treatments that make up the UI. Each pattern shows the resulting color-building rule so it can be recreated in CSS.

| Usage | Light | Dark |
|---|---|---|
| **Hero card** — `LinearGradient(top-left → bottom-right)` `heroStart → heroEnd` | `#7C73C0 → #94ADD7` | `#4B5694 → #7288AE` |
| **Hero decorative circles** | `mint` at **12%** alpha (`rgba(232,255,206,0.12)`) | `mint` at **12%** alpha (`rgba(234,224,207,0.12)`) |
| **Hero period pill** (top-left chip) | White at **18%** alpha, white text | Same |
| **Icon tile / avatar wash** (42px tile behind an icon) | `accent` at **14%** alpha, icon in full `accent` | Same rule |
| **Primary washed container** (e.g. notice count banner) | `primary` at **8%** bg + **18%** border | Same |
| **Avatar gradient** | `primary → secondary`, 2px card-color border | Same |
| **Card shadow** | `shadow` at **4%** alpha, blur 18px, offset (0, 6px) | Same (shadow = `#000`) |
| **Navigation bar** | `card` at **92%** alpha, top hairline border | Same |
| **Nav indicator** (pill behind selected icon) | `primary` at **16%** alpha | Same |
| **`primaryContainer`** | `primary` at **16%** alpha | Same |
| **`secondaryContainer`** | `accent` at **35%** alpha | Same |
| **Text on hero** | White, 80–85% alpha for secondary lines | Same |

> **Alpha convention (translated to CSS):** an accent color rendered at alpha **/100** — e.g. `#7C73C0` + 14% → `rgba(124, 115, 192, 0.14)`.

---

## 5. Typography

The type system is tuned from Material 3 with tighter, more confident values. Every size shares the same family (default Material `Roboto`; on your site pick one clean sans-serif — Inter, Roboto or system-ui).

| Style | Size | Weight | Letter-spacing | Line-height | Color (light) | Primary use |
|---|---|---|---|---|---|---|
| `headlineLarge` | 34px | **800** | -0.6px | 1.15 | `textPrimary` | Hero amount |
| `headlineMedium` | 26px | **700** | -0.4px | 1.2 | `textPrimary` | — |
| `headlineSmall` | 22px | **700** | -0.3px | 1.25 | `textPrimary` | Screen titles ("Notices") |
| `titleLarge` | 20px | **700** | -0.2px | 1.3 | `textPrimary` | App bar, minimal titles |
| `titleMedium` | 16px | **700** | 0 | 1.3 | `textPrimary` | Section headers, stat values |
| `titleSmall` | 14px | **600** | 0 | 1.35 | `textPrimary` | Card titles, list rows |
| `bodyLarge` | 16px | **400** | 0 | 1.45 | `textPrimary` | — |
| `bodyMedium` | 14px | **400** | 0 | 1.45 | `textPrimary` | Settings rows |
| `bodySmall` | 12.5px | **400** | 0 | 1.4 | `textSecondary` | Subtitles, card descriptions |
| `labelLarge` | 14px | **600** | 0.1px | — | `textPrimary` | Buttons |
| `labelMedium` | 12px | **600** | 0.2px | — | `textSecondary` | Tags, chips |
| `labelSmall` | 11px | **600** | 0.6px | — | `textTertiary` | Uppercase kickers (e.g. "SUNRISE HEIGHTS"), timestamps |

Style quirks worth copying:
- Hero-app amount uses `headlineLarge` at **800** weight with **tabular figures** (`font-variant-numeric: tabular-nums` in CSS) so numbers don't jump.
- Kicker / eyebrow text (e.g. "SUNRISE HEIGHTS", settings group titles) uses `labelSmall` weight **800**, uppercase, letter-spacing **1.2–1.6px**, in `primary`.
- Secondary body text drops to `textSecondary`; timestamps to `textTertiary`.

---

## 6. Shape & elevation language

Flat, soft, generous radii. **No hard boxes, no heavy shadows.**

| Element | Border radius |
|---|---|
| Buttons (primary/outlined), inputs | **14px** |
| Chips | **20px** (fully rounded) |
| Notice cards, banners, quick-contact tiles | **16px** |
| Service tiles, stat cards, list tiles | **18px** |
| Quick action rail, setting group cards (`Surface`) | **20px** |
| Hero balance card | **24px** |
| Avatar | **15px** |
| Dialogs | **20px** |
| Bottom sheet (top corners) | **24px** |

Depth is created almost entirely with hairline borders + a whisper of shadow:
- Border: `hairline`, 1px.
- Shadow: `shadow` color at **4%** alpha, **18px** blur, vertical (0, 6px) offset.
- Buttons and cards carry **0 elevation** by design.

---

## 7. Component-level recipes (light / dark both apply)

**Primary button** — bg `primary`, text `onPrimary`, radius 14px, height 48px, horizontal padding 20px, no shadow.

**Text button** — text `primary`, transparent bg, radius 12px, padding (12, 10).

**Outlined button** — text `textPrimary`, 1px `hairline` border, radius 14px, height 48px.

**Input field** — filled with `card` bg, radius 14px, 1px `hairline` border. Hint `textTertiary`, label `textSecondary`.
- Focused: border `primary`, 1.6px.
- Error: border `danger`.

**Navigation bar** — bg `card` @92% alpha, top hairline border, height 68px, NO elevation. Icon 22px. Selected = `primary` in `primary`@16% indicator pill with **700** label; unselected = `textTertiary` with **500** label.

**Segmented control** (theme picker) — selected segment solid `primary` with `onPrimary` text; unselected transparent with `textSecondary` text; 1px hairline border; radius 12px.

**Switch** — active thumb `primary`.

**Chip** — bg `cardMuted`, 1px hairline border, radius 20px, label `labelMedium`.

**Icon convention** — icons render at ~20–22px inside 34–46px rounded squares/circles filled with `accent` at 8–16% alpha.

**Notice tag chips** — pill with `accent` at **14%** bg, accent-colored 10–11px text. Tag mapping:
- `important` → `warning`
- `safety` → `success`
- `event` → `primary`
- default → `secondary`

**Stat cards** — hairline-bordered `Surface`, icon tile in `accent`@14%, value `titleMedium` 700 tabular, label `bodySmall`.

---

## 8. Layout & spacing

- Page content padding: **20px** horizontal, 16px top, 32px bottom.
- Section gaps: 12–16px between blocks; 26px before new section headers; 10px between list cards.
- Cards/tiles: 12px grid gap in the 2-column service grid, tiles **138px** tall.
- Screen titles: `headlineSmall` (800) followed by a `bodySmall` subtitle line.
- Section headers: `titleMedium` title left, `TextButton` action ("See all") right.

---

## 9. Dark-mode gotchas

- `onPrimary` flips to **dark navy** (`#111844`) — the primary button becomes light-steel with dark text.
- Primary text is **cream** (`#EAE0CF`), never the light-mode navy text.
- `featureColors` are brighter/lighter than light mode so they hold up on the navy canvas.
- Hero gradient inverts to **indigo → steel**, still ending with white text and white "Pay now" button (button text = `heroStart`).
- System default = follows device brightness.

---

## 10. Quick reference — all hex values

**Light mode**
```
canvas      #F3F4F8   card        #FFFFFF   cardMuted   #F1F2F7   hairline    #E6E8F0
primary     #7C73C0   onPrimary   #FFFFFF   secondary   #94ADD7   onSecondary #1B2340
accent      #ACFADF   accentOn    #0E3A2E   mint        #E8FFCE   mintOn      #2C4A1E
textPrimary #1E2240   textSecondary #5E6480  textTertiary #9AA1BC
success     #2F9E6E   warning     #D99A2B   danger      #D9534F
shadow      #16224D   heroStart   #7C73C0   heroEnd     #94ADD7
features    #7C73C0 #5C8AD8 #2E9A8E #7B61C4 #C98A3D #C25E5E #3F7FBF #9B7AC0
```

**Dark mode**
```
canvas      #111844   card        #1C2557   cardMuted   #242F6A   hairline    #2B3574
primary     #7288AE   onPrimary   #111844   secondary   #94ADD7   onSecondary #111844
accent      #4B5694   accentOn    #EAE0CF   mint        #EAE0CF   mintOn      #1E2440
textPrimary #EAE0CF   textSecondary #AEB7DA  textTertiary #7E88B8
success     #4FD0A0   warning     #F0BD5E   danger      #F27084
shadow      #000000   heroStart   #4B5694   heroEnd     #7288AE
features    #9A8CE8 #7BA4EC #4CC3A6 #A58BE0 #E8B25E #E77A7A #6CA2FF #BF9AE0
```

---

## 11. Suggested CSS variables (drop-in for your website)

```css
:root {
  --canvas: #F3F4F8;
  --card: #FFFFFF;
  --card-muted: #F1F2F7;
  --hairline: #E6E8F0;
  --primary: #7C73C0;
  --on-primary: #FFFFFF;
  --secondary: #94ADD7;
  --on-secondary: #1B2340;
  --accent: #ACFADF;
  --accent-on: #0E3A2E;
  --mint: #E8FFCE;
  --mint-on: #2C4A1E;
  --text-primary: #1E2240;
  --text-secondary: #5E6480;
  --text-tertiary: #9AA1BC;
  --success: #2F9E6E;
  --warning: #D99A2B;
  --danger: #D9534F;
  --shadow: 0 6px 18px rgba(22, 34, 77, 0.04);
  --hero-grad: linear-gradient(135deg, #7C73C0, #94ADD7);
  --radius-sm: 14px;
  --radius-md: 16px;
  --radius-lg: 20px;
  --radius-xl: 24px;
}

[data-theme="dark"] {
  --canvas: #111844;
  --card: #1C2557;
  --card-muted: #242F6A;
  --hairline: #2B3574;
  --primary: #7288AE;
  --on-primary: #111844;
  --secondary: #94ADD7;
  --on-secondary: #111844;
  --accent: #4B5694;
  --accent-on: #EAE0CF;
  --mint: #EAE0CF;
  --mint-on: #1E2440;
  --text-primary: #EAE0CF;
  --text-secondary: #AEB7DA;
  --text-tertiary: #7E88B8;
  --success: #4FD0A0;
  --warning: #F0BD5E;
  --danger: #F27084;
  --shadow: 0 6px 18px rgba(0, 0, 0, 0.04);
  --hero-grad: linear-gradient(135deg, #4B5694, #7288AE);
}

/* reusable treatments */
.icon-tile { color: var(--accent); background: color-mix(in srgb, var(--accent) 14%, transparent); }
.wash-primary { background: color-mix(in srgb, var(--primary) 8%, transparent); border: 1px solid color-mix(in srgb, var(--primary) 18%, transparent); }
.nav-indicator { background: color-mix(in srgb, var(--primary) 16%, transparent); }
```

---

That's the entire theme, captured from source. Build your site's tokens from Section 10/11 and every component style from Sections 4–8, and the web app will feel identical to the Flutter panel — in both light and dark mode.