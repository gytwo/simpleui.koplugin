# Tiny Critter

A pixel-art companion for your Home Screen, with a speech bubble that comments on your reading. It is off by default: add it from the layout editor, then choose its side in the module's settings. Which critter it is, its decorations, its bubble style, the topics, where the phrases come from and whether it reacts to events are set once for every screen, in **Settings > Tiny Critter**, so it is the same companion everywhere.

## What it does

- **Passive phrases** — a greeting for the time of day, your streak, books finished this year, goals, milestones and the book you are reading (its progress, or how long it has waited for you). Each bundled critter also has its own greetings, streak and reading-today lines, mixed in with the general ones (most of the time in those topics) and turned on or off with them.
- **Conversation** — tap the critter (or press Enter) to open a chat. The bubble shows a prompt and a panel below it offers 2–3 replies; **Say something else…** draws a new prompt. Some prompts ask for affection (a pat, a head scratch, a tickle) and the critter answers with a matching face. The window closes on a tap outside, Back, suspend or a screen size change. Without a touch screen, Up/Down move the selection and Press chooses.
- **Mood** — the critter has a mood from *grumpy* to *radiant*. It rises with the reading you do each day and with conversation (up to a daily cap), and falls on days you do not read. Mood only shapes the conversation.
- **Event reactions** — without being tapped, it comments on what happened: finishing a book, a reading session, low battery, a special date, a new month, your return after time away, or the device charging. One pending reaction is shown at a time, and it expires after two days. Each bundled critter also reacts in its own voice, mixed in with the general lines (about half of the time); critters of your own use the general ones. Toggle with **React to events**.
- **Daily challenges** — it can offer one challenge a day (read a number of minutes or pages today, read for a minute to keep your streak, or start a session before a deadline hour). A completed challenge gives a mood bonus and a reaction. Challenges expire at midnight, with no penalty.
- **Reading suggestions** — ask "Want something new to read?" and it suggests a book from your library that you have not opened yet; you can open it, ask for another or say not now.
- **Games** — "Want to play something?" offers rock, paper, scissors, heads or tails and *Guess the author* (who said a short quote, from the same collections; quotes without an author are not asked). After each round you can play another or stop; winning or answering right adds a little mood, within the same daily cap as the conversation.
- **Quotes** — "Shall I read you something?" reads a short quote from the Quote of the Day collection and from your own quote files (every file in `simpleui/sui_quotes/`), then comments on it when you are done. The comment follows the critter's mood.
- **Bubble style** — *Pixel* (default, stepped corners and tail) or *Smooth* (anti-aliased).
- **Fonts** — the bubble uses the font of the module's Message style; in the Pixel style that defaults to the bundled Geist Pixel family.
- **Your name** — set **Your name** and some phrases will use it.

## Layout

The bubble has a fixed size, so the critter and the decorations never move. You choose which side of the bubble the critter stands on and align the whole group left, centre or right on wide screens (per module). The decorations, up to two on each side in the order they stand on the screen, are arranged in **Settings > Tiny Critter**; any that do not fit are left out.

## In the Quick Settings panel

The critter can also stand in the Quick Settings panel, in every screen where the panel opens: below the buttons in the classic layout, below the book details in the Book layout. Turn it on in **Bars > Quick Settings Bar > Tiny Critter**, where you also pick its side, alignment and scale. It is the same critter, with the same decorations, mood and conversation. It shows what is already known about today and reads no statistics of its own; opening the suggested book closes the panel.

## Bundled critters

Suey (the default, a cat), Chonk (a cat with heart-shaped sunglasses and a tiara), Tulu (a tiny winged tentacle-faced sea monster), Frankie (a stitched-together patchwork monster), Vlad (a pale, pointy-eared little vampire in a red-lined cape), Sholmes (a deerstalker-wearing detective in a long brown coat), Argos (a loyal floppy-eared dog with a red collar) and Hazel (a messy-haired little witch in a crooked pointed hat and a gingham dress). Each has twelve moods: `neutral`, `happy`, `party`, `sleepy`, `cheer`, `love`, `sad`, `surprised`, `curious`, `grumpy`, `shy`, `playful`.

## Custom critters and decorations

Everything below lives in `<KOReader settings dir>/simpleui/sui_critters/`. The folder is created when you open the *Critter* picker and is never touched by updates.

- **Your own critters** — a critter is a folder named after it holding `neutral.png` (required) and optionally one image per mood above, all with the same canvas size. A single loose `.png` file is used for every mood; `.svg` works too. A PNG whose longest side is 64 px or less is treated as pixel art and enlarged without smoothing. A critter with the same name as a bundled one replaces it.
- **Your own decorations** — `.png` (or `.svg`) files in `sui_critters/decor/`. Loose files stand on the floor of the row; put them in `decor/wall/` to hang them at mid-height or in `decor/ceiling/` to hang them from the top. Pixel-art decorations are enlarged by the same factor as the critter.
- **Your own phrases** — put a `phrases.lua` in the same folder, returning a list of `{ text = "...", sub = "...", mood = "happy", period = "morning", min_streak = 3, min_books = 1 }`. Only `text` is required.
  - `sub` is the smaller second line (up to two lines in the bubble).
  - `mood` is one of the twelve moods listed above (`neutral`, `happy`, `party`, `sleepy`, `cheer`, `love`, `sad`, `surprised`, `curious`, `grumpy`, `shy`, `playful`); any other value shows `neutral`.
  - `period` is one of `morning`, `afternoon`, `evening`, `night`.
  - `text` and `sub` may use `{streak}`, `{books}`, `{pages}`, `{minutes}`, `{goal}`, `{weekday}` and `{name}` (the name you gave the critter). A phrase is skipped while one of its placeholders has no value.
  - Set **Phrases** on the module to *Included and mine* or *Mine only*.

Custom critters are included in [backups](../README.md#backup--restore).

Back to the [README](../README.md).
