---
version: "alpha"
name: "Sahara Modern"
description: "A warm, editorial travel-app design system for AI Tour. Rounded, soft-shadowed, built for a real product rather than a generic template."
colors:
  primary: "#FAF6F0"
  secondary: "#D6CBBB"
  tertiary: "#2B241E"
  neutral: "#C1602C"
  surface: "#FFFFFF"
  accent: "#3E6B62"
typography:
  h1:
    fontFamily: Plus Jakarta Sans
    fontSize: 2.5rem
    fontWeight: 700
  body-md:
    fontFamily: Inter
    fontSize: 1rem
    fontWeight: 400
components:
  button-primary:
    backgroundColor: "{colors.neutral}"
    textColor: "#FFF8F1"
    padding: 14px
---

## Overview

AI Tour is a trip-planning app for exploring Algeria — the Casbah, Roman ruins at Djemila and Timgad, the Tassili plateau, the Kabylie coast. The design should feel like a considered, purpose-built travel companion: warm paper tones evoking sun and sand, a single confident terracotta accent, and soft rounded surfaces throughout. It should read as crafted for this specific product, not dropped in from a generic SaaS template.

Corners are consistently rounded (10–28px depending on scale), shadows are soft and warm-tinted rather than hard black, and icon-only controls (back button, swipe actions, send buttons) are full circles. The map uses a clean, minimal light basemap rather than a busy default tile style, so it reads as part of the same palette as the rest of the UI.

- Density: 5/10 — Balanced
- Variance: 3/10 — Restrained, one accent color used with intent
- Motion: 4/10 — Subtle

- **Style:** Warm, rounded, editorial, grounded in place
- **Keywords:** terracotta, paper, rounded, soft shadow, warm neutral, desert, coastal, travel
- **Era:** Contemporary mobile product design
- **Light/Dark:** ✓ Light / ✗ No dark mode yet

## Colors

- **Paper White** (#FAFAFA) — Light surface, card backgrounds
- **Fold Shadow** (#B0B0B0) — Secondary surface or text color
- **Ink Black** (#1A1A1A) — Dark surface, primary background
- **Accent Coral** (#FF6B6B) — Primary accent, CTAs and interactive elements
- **Sky Fold** (#87CEEB) — Extended palette, decorative use
- **Sage Paper** (#A8D5BA) — Extended palette, decorative use
- **Warm Crease** (#F0C987) — Extended palette, decorative use
- **Steel Grey** (#4A4A4A) — Secondary text, borders, muted elements


## Typography

- **Display / Hero:** Poppins — Weight 700, tight tracking, used for headline impact
- **Body:** Poppins — Weight 400, 16px/1.6 line-height, max 72ch per line
- **UI Labels / Captions:** Poppins — 0.875rem, weight 500, slight letter-spacing
- **Monospace:** JetBrains Mono — Used for code, metadata, and technical values

Scale:
- Hero: clamp(2.5rem, 5vw, 4rem)
- H1: 2.25rem
- H2: 1.5rem
- Body: 1rem / 1.6
- Small: 0.875rem


## Layout

- **Grid:** CSS Grid primary. Max-width containment: 1280px centered with 1.5rem side padding.
- **Spacing rhythm:** Balanced. Base unit: 0.5rem (8px).
- **Section vertical gaps:** clamp(4rem, 8vw, 8rem).
- **Hero layout:** Split-screen (text left, visual right).
- **Feature sections:** Zig-zag alternating text+image rows. No 3-equal-columns.
- **Mobile collapse:** All multi-column layouts collapse below 768px. No horizontal overflow.
- **z-index contract:** base (0) / sticky-nav (100) / overlay (200) / modal (300) / toast (500).


## Elevation & Depth

CSS polygon clip-paths, faceted card surfaces, paper fold shadows, tessellation backgrounds, angular section dividers, crease line borders, layered paper depth, geometric hover transforms

- **Physics:** Ease-out curves, 200-300ms duration. Smooth and predictable.
- **Entry animations:** Fade + translate-Y (16px → 0) over 420ms ease-out. Staggered cascades for lists: 80ms between items.
- **Hover states:** Subtle color shift + shadow adjustment over 200ms.
- **Page transitions:** Fade only (200ms).
- **Performance:** Only transform and opacity animated. No layout-triggering properties.


## Shapes

Base corner radius: 0px. See rounded tokens in front matter for the full scale.


## Components

- **Primary Button:** Sharp edges (0px) shape. Accent color fill. Hover: 8% darken + subtle lift shadow. Active: -1px translate tactile press. Font weight 600. No outer glows.
- **Secondary / Ghost Button:** Outline variant. 1.5px border in muted color. Text in primary color. Hover: subtle background fill.
- **Cards:** Sharp edges (0px) corners. Surface background. Subtle shadow (0 2px 12px rgba(0,0,0,0.06)). 1px border stroke.
- **Inputs:** Label above input. 1px border stroke. Focus ring: 2px accent color offset 2px. Error text below in semantic red. No floating labels.
- **Navigation:** Primary surface background. Active item: accent color indicator. Font weight 500 when active.
- **Skeletons:** Shimmer animation matching component dimensions. No circular spinners.
- **Empty States:** Icon-based composition with descriptive text and action button.


## Do's and Don'ts

- No emojis in UI — use icon system only (Lucide, Heroicons)
- No pure black (#000000) — use off-black or charcoal variants
- No oversaturated accent colors (saturation cap: 80%)
- No 3-column equal-width feature layouts — use zig-zag or asymmetric grid
- No `h-screen` — use `min-h-[100dvh]`
- No AI copywriting clichés: "Elevate", "Seamless", "Unleash", "Next-Gen"
- No broken external image links — use picsum.photos or inline SVG
- No generic lorem ipsum in demos

- Do CSS polygon clip-paths
- Do Faceted card surfaces
- Do Paper fold shadows
- Do Tessellation backgrounds
- Do Angular section dividers
- Do Geometric hover transforms


## Use Case

Landing pages, SaaS
