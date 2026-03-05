# Fix Wikipedia Content Extraction

## Context

Wikipedia (and likely many other sites) don't return full article content when extracted by the app. Two root causes were identified in `ContentExtractor.swift`:

1. **Content selector regexes never match multi-line HTML** - The patterns use `(.*?)` which doesn't cross newlines, and `.dotMatchesLineSeparators` is missing. Since all real articles span multiple lines, these selectors always fail silently, and the app falls through to using the entire page HTML (including nav, sidebars, etc.).

2. **No browser User-Agent header** - Wikipedia and other sites may serve reduced/different content to the default iOS URLSession User-Agent.

3. **Section extraction uses wrong source** - Heading extraction at line ~388 runs against `workingHTML` (entire page) instead of `contentHTML`, so headings from nav/sidebar can leak into the section list.

## Plan

All changes in: `SpeakTheWeb/Services/ContentExtractor.swift`

### Step 1: Add browser User-Agent to content requests

At line 129, change `let request = URLRequest(url: url)` to a `var` and add a Safari User-Agent header. This ensures sites serve full browser-targeted content.

### Step 2: Fix content selector regexes to match multi-line content

Replace the current content selector loop (lines 328-351) with a multi-phase approach:

**Phase 1 - Simple selectors (`<article>`, `<main>`):**
- Change `(.*?)` to `([\s\S]*?)` (non-greedy, crosses newlines without over-capturing)
- Use `match.range(at: 1)` for capture group (currently uses full match)

**Phase 2 - Div selectors with depth counting:**
- Add new `extractDivContent(from:openingPattern:)` helper method
- Finds the opening `<div>` by regex, then counts `<div>`/`</div>` depth (case-insensitive) to find the matching close tag
- Scans to end of string (input is already downloaded and finite); returns nil if depth never balances, falling through to next selector
- Selectors (in priority order):
  1. `<div id="mw-content-text">` (Wikipedia-specific)
  2. `<div id="mw-body-content">` (Wikipedia-specific)
  3. `<div class="...content|article|post|entry...">` (generic, word-boundary matching within class lists)
  4. `<div id="...content|article|post|entry...">` (generic, word-boundary matching within id values)

**Phase 3 - ARIA role selectors (fallback):**
- `role="main"` and `role="article"` with `[\s\S]*?` non-greedy pattern
- Use `match.range(at: 1)` for capture group

### Step 3: Add Wikipedia-specific unwanted element removal

After the existing unwanted tag removal loop, add patterns to strip Wikipedia noise. Use `\b` word-boundary class matching (e.g. `class="[^"]*\breference\b[^"]*"`) to handle multi-class elements:
- Reference superscripts (`<sup class="...reference...">`)
- Edit section links (`<span class="...mw-editsection...">`)
- Reference lists (`<div class="...reflist...">`, `<ol class="...references...">`)
- Navigation boxes/infoboxes (`<table class="...navbox|sidebar|infobox|metadata...">`)
- Table of contents (`<div id="toc">`)
- Category links / print footer (`<div class="...catlinks...">`, `<div class="...printfooter...">`)

### Step 4: Fix section extraction scope

Change heading regex at line ~388 to run against `contentHTML` instead of `workingHTML`. Update `Range` conversions on lines ~391-393 to use `contentHTML` as well.

### Step 5: Reorder operations for performance

Apply Wikipedia-specific cleanup on `contentHTML` (after content selection), not on full `workingHTML`:
1. Select main content region (Step 2) → `contentHTML`
2. Apply Wikipedia-specific noise removal (Step 3) on `contentHTML` only
3. Extract headings from `contentHTML` (Step 4)
4. Strip tags and clean up

## Tasks

- [ ] Add browser User-Agent header
  - branch: `impl/add-user-agent-header`
  - status: `claimed`
- [ ] Fix content selector regexes
- [ ] Wikipedia cleanup, section fix, reorder

## Verification

Manual testing (no unit tests exist for ContentExtractor):
1. **Wikipedia:** `https://en.wikipedia.org/wiki/Text-to-speech` - verify full article text, no nav/sidebar, no `[1]` refs
2. **Blog:** Test a Medium or similar article (div-based content)
3. **News:** Test BBC News or similar (article-tag based)
4. **Fallback:** Test a page with no semantic HTML to verify graceful degradation
5. **Section headings:** Verify section list only contains headings from article content, not from page chrome
