# Home screen redesign — layout and colour notes (2026-11)

Guide for rewriting `lib/features/home/` to match the live website theme
(juntra-payakorn). `home-mockup.webp` next to this file is the picture; this
file is the numbers. Both came from ChatGPT on 2026-11-12 (prompt: the web
palette + fonts, 3 web illustrations and the Mae Mor / Busaba portraits as
reference). The mockup is a direction, not a pixel spec — it does not ship in
the app.

Things in the mockup that are **not** real and must come from the app/server:
- Package names, prices (300 / 900 / 1,200) and credit balance are invented —
  use `tarotPackagesProvider` and the wallet as today.
- The Kunsai portrait was drawn by ChatGPT; use `assets/images/rooms/kunsai.webp`.
- The review quotes/avatars are placeholders; the bottom-nav labels
  (หน้าหลัก · ดูดวง · สิทธิพิเศษ · บทความ · บัญชี) are ChatGPT's guess — keep
  the app's real destinations.

## 1. Layout (390 × 844 dp phone)

`Scaffold` + `CustomScrollView` (slivers), fixed bottom navigation.

| Section | Height (dp) | Notes |
|---|---|---|
| Top app bar | 64 | logo left; wallet chip + avatar right |
| Hero slider | 210 | full width, gradient overlay, see §4 |
| "เลือกห้องดูดวง" heading | 28 | |
| Room selector | 124 | 3 cards in one row |
| Daily check-in | 132 | luck line + 7-day streak |
| Card of the day | 164 | face-down card + CTA |
| Packages heading | 28 | with "ดูทั้งหมด" |
| Package carousel | 190 | horizontal |
| Free one-card banner | 112 | |
| Reviews heading | 28 | with "ดูเพิ่มเติม" |
| Review carousel | 136 | horizontal |
| Decorative footer | 110 | moonlit lotus pond |
| Bottom navigation | 72 + inset | 5 destinations |

- Page padding 16; gap between sections 16; heading → content 10; card padding 12–16.
- Radius: cards 18, hero 20, pills 999. Gold border 0.8 dp, selected 1.5 dp.
- Leave ≥ 24 dp between the last content and the bottom nav.
- Heights are targets — Thai text and font scaling must be allowed to grow them.

## 2. Colour roles

| Role | Value |
|---|---|
| Page background | `#0A0612`, gradient `#0A0612 → #160A26 → #241038` |
| Card fill | `#241038` @ 85 % · elevated card `#301546` @ 95 % |
| Gold | primary `#E7C97A`, highlight `#F6E3A8`, subtle border `#A8854A` @ 65 % |
| Text | primary `#F3E9FF`, secondary `#D8C9E8`, muted `#B6A5C5`, disabled `#756784` |
| Moonlight | `#FFF7E0` |
| Purple | interactive `#7A3DF0`, selected `#B07AFF` |
| Magenta | `#D24AD1` — decoration only |
| Gold CTA | gradient `#F6E3A8` 0 % → `#E7C97A` 55 % → `#C59B48` 100 %, label `#241038` (dark, not white) |

Room accents — card background tinted with the accent @ 12 %, border @ 75 %,
glow @ 15 % with 12 dp blur; the selected room gets a 1.5 dp border and a
small accent chip:

| Room | Accent |
|---|---|
| บุษบา (Busaba) | `#7CC7F6` sky blue |
| แม่หมอ (Mae Mor) | `#A884F4` lavender |
| คุณไสย (Kunsai) | `#E0455F` crimson |

Never put accent-coloured body text straight on a photo — add a solid/gradient scrim first.

## 3. Typography

| Role | Font | Size / weight | Line height |
|---|---|---|---|
| App-bar Thai title | Charm | 23 / 700 | 1.2 |
| Latin display | Cormorant Garamond | 24 / 600 | 1.15 |
| Hero headline | Charm | 25 / 700 | 1.25 |
| Section heading | Bai Jamjuree | 19 / 600 | 1.3 |
| Card title | Bai Jamjuree | 16 / 600 | 1.35 |
| Body | Bai Jamjuree | 14 / 400 | 1.5 |
| Caption | Bai Jamjuree | 12 / 400 | 1.4 |
| Price | Bai Jamjuree | 15 / 700 | 1.3 |
| Button | Bai Jamjuree | 15 / 600 | 1.3 |
| Nav label | Bai Jamjuree | 11 / 500 | 1.3 |

Gold for display headings, white-lavender for body. Charm only for display
sizes — never for small functional labels.

## 4. Components

- **Hero slider** — 358 × 210 (≈ 1.70 : 1), `PageView`, autoplay 5 s, transition
  450 ms, pause while touched; dots 6 dp, active 8 dp gold; CTA ≥ 48 dp tall;
  bottom-left dark gradient @ 85 % under the text.
  ⚠️ The hero photos (`assets/images/hero/*.webp`) are 4 : 5 portraits. A
  1.70 : 1 `BoxFit.cover` crop centred would cut the face — lay it out like the
  mockup (text on the left, portrait on the right ~55 % width) or align the crop
  to the face (`Alignment(0.3, -0.6)` area), and check every slide.
- **Room selector** — 3 cards ≈ 114 × 124, gap 8; portrait in the top 85 dp with
  a dark gradient under the name; whole card tappable.
- **Daily check-in** — top row: calendar icon, luck message, streak counter;
  bottom row: 7 medals 28 dp evenly spaced; done = gold glow, future = muted,
  today = thin animated halo. Guard against double check-in (double tap).
- **Card of the day** — face-down card 76 × 124 on the right, text + CTA left;
  the flip opens the reading.
- **Package carousel** — card 140 × 190, gap 10, ~2.4 cards visible (next one
  peeks); illustration 112 dp tall, then title and a credit-price chip.
- **Free one-card banner** — 112 dp, gold-bordered purple gradient, tarot art right, CTA left.
- **Review cards** — 154 × 136, gap 8, avatar 30, five gold stars, quote max 3 lines + ellipsis.
- **Bottom navigation** — 72 dp + system inset, icons 24 dp, active item on a
  rounded purple pill, inactive icons muted gold.

## 5. Motion (restrained)

| Interaction | Duration | Curve |
|---|---|---|
| Button press (scale 0.97) | 120 ms | `easeOut` |
| Card selection | 220 ms | `easeInOutCubic` |
| Page transition | 300 ms | `easeInOut` |
| Tarot flip (Y-axis perspective) | 500 ms | — |
| Streak confirmed (one gold pulse) | 350 ms | — |
| Carousel snap | 280 ms | `easeOutCubic` |
| Decorative glow | 3 s cycle, ≤ 2 % opacity change | — |

Respect the system reduced-motion setting (turn the decorative loops off).
The cinematic shuffle timings in `shuffle_screen.dart` are separate and stay as they are.

## 6. Accessibility

- WCAG AA: 4.5 : 1 for normal text, 3 : 1 for large text and essential controls.
- Tap targets ≥ 48 × 48 dp with ≥ 8 dp between neighbours.
- Semantic labels on tarot cards and nav items; announce the check-in result.
- Gold text = `#F6E3A8` on a dark solid fill. Avoid small text over bright art,
  low-opacity gold labels, glow-heavy type, and colour-only selection states.
- Must survive font scale up to 200 % (flexible heights, wrapping, no clipping).

## 7. Assets prepared for this redesign (`assets/images/`)

All WebP, long side ≤ 1080 px. Masters (full ChatGPT resolution) live outside
the repo in `D:\Code\App\juntraapp\art-src\2026-11\chatgpt\`; web copies come
from `juntraweb/public/images/`.

| Use | Files | Notes |
|---|---|---|
| Home background | `home/home-bg.webp` 608×1080 | middle 60 % kept dark and calm for cards |
| Splash background | `home/splash-bg.webp` 608×1080 | the empty gold ring for the logo is centred at x 50 %, **y ≈ 41 %** (not 50 %) |
| Hero slider | `hero/maemor-1..5.webp`, `hero/busaba-1..3.webp` 864×1080 | see §4 crop warning |
| Room cards | `rooms/{busaba,maemor,kunsai}.webp` ≈603×1080 | 9:16 portraits; align the crop toward the face |
| Room headers | `rooms/plate-*.webp` 1080×608, `rooms/*-bg.webp` 1080×720 | from the web theater |
| Streak medals | `badges/streak-{3,7,14,30}.webp` 512×512, transparent | milestones: ดาวเริ่มส่องทาง / ครบหนึ่งรอบสัปดาห์ / ดวงจันทร์ครึ่งดวง / ครบหนึ่งรอบจันทร์; the 30-day medal has rays that reach closer to the edge |
| Packages (offline art) | `spreads/*.webp` 800×450 | same art as the web packages |
| Section art | `art/daily-luck`, `collection`, `review`, `whats-new`, `tarot-free` … 1080×463 | web banners, 2.33 : 1 — fits `ArtBanner` (height 132–150, cover) |
| Dividers / frames | `ornament/divider.webp` 1080×202, `ornament/corner-{tl,tr,bl,br}.webp` 360×358, `ornament/frame-thai.webp` 1024×1024 | transparent; the four corners are one master mirrored, so they match exactly; `frame-thai` has small ornaments mid-rail, so a nine-slice must stretch only the plain rail segments |
| Quiet texture | `ornament/nebula.webp` 1080×608 | very dark, safe behind text |
| Empty states | `state/{no-reading,locked,no-chat,offline,collection-empty}.webp` 1080×810 (4 : 3) | were 1 : 1 before — `history_screen.dart` still shows `stateNoReading` in a 150×150 `ClipOval`, which will crop the 4 : 3 art |
| Logos | `logo-juntra.webp` 512×512 (web logo, opaque), `dbd-registered.webp` 208×86 | |

Changed shape vs. the previous app files: `art/auth.webp` is now the web's
portrait 810×1080 (was 1200×670 landscape); the other `art/*` banners are
1080×463 (were 1200×670 or 1200×514).
