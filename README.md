# Sloka Words

A macOS flashcard app for learning the Sanskrit words in stotras. Each card shows a word in
Telugu script, Hindi (Devanagari) script and IAST. Its back gives the Telugu meaning, the
English meaning and the verses it appears in.

The deck covers:

| Source | Groups | Words |
| --- | --- | --- |
| Bhagavad Gita | Chapters 1–18 | 3,984 |
| Vishnu Sahasranamam | Pūrva-bhāga, Stotram (the thousand names), Uttara-bhāga | 1,295 |
| Bhaja Govindam | Refrain, Dvādaśa-mañjarikā, Caturdaśa-mañjarikā, concluding verses | 170 |

That is 5,194 unique cards. Each word appears once, however many chapters or verses it
occurs in, and its card lists all of those verses. Spelling variants such as `vedavid` and
`veda-vit` are merged. Phrases that only add a particle (`drupadaḥ ca`) are merged into
the word. A phrase whose words all have cards of their own (`mām eva`) is dropped.

1,128 cards have a Telugu meaning so far, including every Bhaja Govindam word. The rest show the English meaning, and the words
still needing a Telugu meaning are listed in `missing_te.json`.

The words come from the `Words:` lists in the
[bhakti](https://github.com/venkatacrc) stotra pages (`BhagavadGita/*.html`,
`Vishnu/vishnu_sahasranamam.html`, …).

## Build and run

Requires macOS 14 or later and the Xcode Command Line Tools (`xcode-select --install`).

```sh
./scripts/build_app.sh
open build/SlokaWords.app
```

For development you can also run `swift run --package-path app`.

## Using the app

- **Words / Verses** (top left of the toolbar): practice single words, or whole verses. There
  are 913 verse cards: 701 from the Gita, 181 from the Vishnu Sahasranamam and 31 from
  Bhaja Govindam.
  - A verse card shows only the first line. Recite the rest, then press **Space** to check
    against the full verse in Telugu, Hindi (Devanagari) and IAST. The back also shows the
    Telugu meaning (where available), the English meaning and the word-by-word meanings.
  - **E** opens the verse editor. Rewrite the lines the way the verse is chanted, one line
    per row, and press **Save**. The edit is used straight away, and the card is labelled
    *Edited*. **Remove my edit** goes back to the deck text.
- **Learn / Test** (toolbar):
  - *Learn* shows every card in full: the whole verse or word with all its meanings. Step
    through with **← / →**, and mark cards with **K** (known) or **R** (review).
  - *Test* hides the answer. Recall it, press **Space** to reveal, then **G** (got it) or
    **M** (missed it). The header keeps the score. Cards you get are marked known, and missed
    ones are marked for review. At the end you see your score and can retest just the
    missed cards.
- **Print** (⌘P, or the printer button in the toolbar): prints the verses in the chapters and
  sections ticked in the sidebar, or saves them as a PDF. Choose which scripts and meanings to
  include, and optionally only the verses marked for review. Your verse edits are used.
- **Sidebar:** tick the chapters or sections to practice. Each source has **Select all** and
  **Clear**, and the card count updates as you change selections. Your choices are saved.
- **← / →:** previous / next card (in Test, → skips the card).
- **Toolbar:** choose *All cards*, *Not yet known* or *Review only*; turn **Shuffle** on or
  off; **Restart** from the first card.
- **File menu:**
  - **Import Deck…** (⌘O) loads a regenerated `words.json` without rebuilding the app.
  - **Reload Deck** (⇧⌘R) re-reads the deck.
  - **Use Built-in Deck** removes an imported deck.
  - **Export Verse Edits…** (⇧⌘E) writes your verse edits to a JSON file (see below).
  - **Reset Progress…** clears the known and review marks.

Progress is saved per word, so adding new stotras keeps your known and review marks.

## Phone and web app

`web/` holds an installable web app with the same cards. It has Words and Verses, Learn and
Test, chapter selection, verse editing and Print / Save as PDF. It works on Android phones,
iPhones and desktop browsers, and keeps working offline once it's opened. It's served from the
bhakti GitHub Pages site at <https://venkatacrc.github.io/bhakti/flashcards/>.

To publish it, or to update it after changing the deck:

```sh
./scripts/publish_web.sh ~/code/bhakti   # copies web/ and words.json into bhakti/flashcards/
cd ~/code/bhakti && git add flashcards && git commit -m "Update flash cards" && git push
```

To install it on a Pixel, open the link in Chrome, then open the ⋮ menu and choose
**Add to Home screen** (or **Install app**). Swipe the card left or right to move between cards.
Tap it in Test mode to show the answer.

Progress and verse edits are saved on each device separately. To bring verse edits made on
the phone back to the repo, use **Export verse edits** in the ☰ menu. Copy the file to the Mac
and run `python3 tools/push_edits.py --repo ~/code/bhakti --edits ~/Downloads/verse_edits.json`.

## Keeping verse edits

The app stores verse edits in
`~/Library/Application Support/SlokaWords/verse_edits.json`.

### Pushing edits to the repos

**File → Push Verse Edits to Repos…** (⇧⌘P) sends your edits back to both repos:

- **bhakti:** the edited lines replace the Telugu, Devanagari and IAST lines of each verse in
  its HTML page. Each page keeps its own line-break style. On pages romanised in ITRANS
  (Bhaja Govindam), the IAST you typed is converted back to ITRANS.
- **sloka_words:** the edits are merged into `verse_edits.json`, and the deck is rebuilt.

First you get a confirmation sheet. It shows each changed line (before and after), the branch
and remote each repo pushes to, and an editable commit message. It also warns you if a page
it will commit already has other uncommitted changes. Only the files the push writes are
committed. After the push, the app loads the rebuilt deck.

The first time, the app looks for the repos in `~/code/sloka_words` and `~/code/bhakti`. If
they are not there, it asks you for the folders. **File → Choose Repo Folders…** changes them
later. Pushing uses your normal git credentials; if git would need to ask for a password, the
push stops with git's error instead of waiting.

The same thing from the command line:

```sh
python3 tools/push_edits.py --repo ~/code/bhakti \
  --edits ~/Library/Application\ Support/SlokaWords/verse_edits.json --dry-run
```

Drop `--dry-run` to commit and push. Add `--no-push` to commit without pushing.

### Keeping edits without pushing

1. In the app, choose **File → Export Verse Edits…** and save the file as `verse_edits.json`
   in the root of this repo. If a file is already there, the export merges into it.
2. Run `python3 tools/build_deck.py --repo ~/code/bhakti`. It reports how many edits were
   applied, and warns about any verse ids it doesn't recognise.
3. Rebuild the app, or use **Import Deck…**.

Each entry is keyed by verse id (`gita:12:1`, `vs:stotram:5`, …) and holds the edited lines
separated by `\n`:

```json
{"gita:12:1": {"te": "…line 1…\n…line 2…", "deva": "…", "iast": "…"}}
```

## Adding a new stotra

1. In `sources.json`, add an entry or set `"enabled": true` on one that is already listed.
   All the bhakti stotra pages with word lists are listed there. To add more Gita chapters,
   extend `include_groups` (for example `["2", "12"]`), or delete that key to include all 18.
2. Regenerate the deck:

   ```sh
   python3 tools/build_deck.py --repo ~/code/bhakti
   ```

3. Add Telugu meanings for the words listed in `missing_te.json` to a new file in
   `te_meanings/` (for example `te_meanings/bhaja_govindam.json`), in the form
   `{"iast word": "తెలుగు అర్థం"}`.
4. Rerun with `--strict`, which fails if any word still lacks a Telugu meaning.
5. In the app, choose **File → Import Deck…** and pick
   `app/Sources/SlokaWords/Resources/words.json`, or rebuild with
   `./scripts/build_app.sh`.

### `sources.json` fields

| Field | Meaning |
| --- | --- |
| `id`, `title`, `short` | Identifier, display name, and the short name used in references such as "Gita 12.5" |
| `lang` | `sanskrit` or `awadhi`; the app can filter by language |
| `enabled` | Whether the source is included in the deck |
| `files` | Glob relative to the bhakti repo |
| `group_by` | `file` (one group per file, e.g. Gita chapters), `heading` (map `<h2 id>` sections to `groups`), or `none` |
| `include_groups` | Optional list that limits which groups are included |
| `iast_style` | Optional. `ch-for-c` for pages that write च as `ch` (the Gita); `itrans` for pages whose romanisation is ITRANS (`aa`, `R^i`, `~N`, `Sh`), such as Bhaja Govindam |

## Layout

```
app/                 Swift package (SwiftUI app)
  Sources/SlokaWords/Resources/words.json   generated deck bundled into the app
tools/build_deck.py  deck builder
tools/push_edits.py  writes verse edits into the bhakti pages and verse_edits.json, commits and pushes
sources.json         source registry
te_meanings/         Telugu meanings, one JSON file per batch or stotra
missing_te.json      words still needing a Telugu meaning (generated)
verse_edits.json     chanting-style verse edits exported from the app (optional)
scripts/build_app.sh builds build/SlokaWords.app
web/                 phone and web app (plain HTML, CSS and JavaScript)
scripts/publish_web.sh copies web/ and the deck into bhakti/flashcards/ for GitHub Pages
```
