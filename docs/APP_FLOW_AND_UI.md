# App Flow & UI Specifications

Based directly on the aesthetic and layout patterns of **mymind**, tailored for the **KeepIt** experience:

---

## 1. Design Principles & Aesthetics
- **Warm Minimalist Canvas:** Subtle off-white/warm grey background (`#F9F9FB`), avoiding sterile pure white.
- **Vibrant Accent Pop:** Warm saffron orange (`#FF6B4A`) for key CTAs and top badges.
- **Masonry Layout:** Staggered 2-column dynamic aspect ratio grid celebrating content diversity (Reel thumbnails, tall images, snippet quotes, link cards).
- **Smooth Micro-interactions:** Fluid bottom sheets, bouncy scale gestures, and blur backdrops (`BackdropFilter`).

---

## 2. Core Screens

### Screen 1: The Feed ("Everything")
- **Top Search Bar:** Floating pill with subtle elevation:
  - Search icon & placeholder: *"Search my mind..."*
  - Instant tag suggestions upon tapping.
  - Quick `+` action button with radiant orange background.
- **Masonry Feed Grid:**
  - Auto-detected media cards.
  - Video cards with centered frosted play icon and source pill (e.g. Instagram camera glyph, YouTube red icon).
  - Subtle metric indicator (e.g., view count, reactions, or date saved).
  - Rounded corners (`16.dp` radius) with smooth borders.
- **Bottom Navigation Bar:**
  - **Everything** (active orange icon)
  - **Spaces** (curated folders/categories)
  - **Serendipity** (nostalgia & forgotten discovery engine)

---

### Screen 2: Card Detail View
- Clean full-screen sheet with gentle hero transition.
- **Action Header:** Dismiss chevron (`v`), editable title (`Untitled` or extracted title), three-dot options (`...`).
- **Main Media / Content Showcase:**
  - High resolution thumbnail or embedded web player.
  - Author attribution: Profile avatar + author name.
  - Source watermark badge.
- **Interactive Action Button:**
  - Elevated frosted glass pill: *"🚀 I've watched this reel"* / *"📖 I've read this article"*.
  - Tapping marks card as processed, triggering gentle haptic feedback.
- **Tags & Metadata Section:**
  - Pill tags: `#ai`, `#contacts`, `#tips`.
  - Date saved, source domain, reading time.

---

### Screen 3: Card Options Bottom Sheet
- Glassmorphic modal drawer with rounded top corners.
- Action items:
  1. 🔗 **View original source** (opens in external browser/app).
  2. 🏷️ **Add tags** (quick interactive chip selector).
  3. 📁 **Add to space** (categorize into collections).
  4. 🧠 **Top of Mind** (pin to top priority carousel).
  5. 🗑️ **Delete card** (soft delete with red warning accent).

---

### Screen 4: Spaces (Curated Collections)
- Visual folder cards (e.g., `AI Tools`, `Workout Routines`, `Recipes`, `Code Snippets`).
- Smart spaces auto-populated by tag rules.

---

### Screen 5: Serendipity (Rediscovery Engine)
- Daily memory cards: *"On this day 2 weeks ago you saved..."*
- Interactive flash-review: Keep, Archive, or Share.
