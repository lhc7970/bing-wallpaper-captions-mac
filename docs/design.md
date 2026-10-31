# Design

Why the scripts work the way they do. For usage, see the [README](../README.md).

## Goal

1. **Collect:** keep each Bing image of the day once, with all the information
   Bing gives about it.
2. **Show:** the Mac desktop rotates through a mix of new and older images, and
   each one shows its description on screen.

## What Bing provides

`https://cn.bing.com/HPImageArchive.aspx?format=js&idx=<n>&n=8` returns at most
8 images per request. `idx=7` reaches 7 days further back, so the last **15
days** are available; larger `idx` values return the same 15. The endpoint is
not documented and may change.

Each image has, among others:

| Field | Example |
|-------|---------|
| `startdate` | `20261030` |
| `title` | 往昔帝国的幽影 |
| `copyright` | `圣巴尔多禄茂教堂，法兰克福，德国 (© AlxeyPnferov/Getty Images)` |
| `copyrightlink` | a Bing search link |
| `urlbase` | `/th?id=OHR.FrankfurtHalloween_ZH-CN5998782698` |

The part after `OHR.` (`FrankfurtHalloween`) is the same in every market, so
it identifies the image. `ensearch=1` on the same host returns the English
text. The English market's date can be a day later, so English text is
matched by image ID, not by date.

## Identity: one image per date

An image is skipped if the folder already has **any** image of its date: a file
named `YYYY-MM-DD ….jpg` or `.YYYY-MM-DD ….jpg.icloud`.

Matching the whole file name looked natural, but in a long-running collection
of about 1,000 images, every duplicate came from it:

- Bing sometimes edits a caption after publishing it (熊蒜 → 野蒜); the new name
  looked like a new image.
- iCloud makes a conflict copy (`<name> 2.jpg`) when two Macs download the
  same day.
- Some file names were stored decomposed (NFD), which a byte-wise match
  misses.

All of these start with the same ASCII date. The trade-off: if Bing replaced a
day's image after it was downloaded, the first one is kept.

**Deleted images stay deleted.** `.bing-downloaded` lists the dates already
downloaded. A listed date is skipped even when its image is gone. Only Bing's
window matters, so lines older than 16 days are dropped (15 days, plus 1 spare
for time zones).

## Where the information lives

| Layer | What | Why |
|-------|------|-----|
| File name | `YYYY-MM-DD <description> © <credit>.jpg` | Readable everywhere and survives any sync. |
| XMP inside the JPEG | title, description, credit, date, link, image ID, English title and description | Travels with the file. Shows in Finder *Get Info* and Spotlight. |

The file name is made from `copyright`: `(` and `)` are dropped, `/` becomes
`, `, `:` becomes ` - `, and characters invalid in file names are removed. The
XMP fields use the text as Bing sends it. Description and credit are split at
the last ` (©`.

XMP is written by `bingkit.swift tag` through ImageIO **without re-encoding**:
decoded pixels stay identical and the file grows by a few KB. `osascript`
cannot reach ImageIO, so this needs `swift` (Xcode Command Line Tools). Without
it, only the file name is written.

| XMP field | Content |
|-----------|---------|
| `dc:title`, `dc:description`, `dc:rights` | Chinese title, description, credit |
| `photoshop:DateCreated` | `YYYY-MM-DD` |
| `bing:id`, `bing:link` | image ID, `copyrightlink` |
| `bing:titleEn`, `bing:descriptionEn` | English title and description |

The `bing:` namespace is `https://github.com/lhc7970/bing-wallpaper-captions-mac/xmp/1.0/`.
It is only an identifier. Readers find fields by the `bing:` prefix the file
declares.

## Rotation folder

`rotation.sh` builds `~/Pictures/Bing_Wallpaper`, and macOS rotates through it
(*System Settings → Wallpaper*, a folder, random order, an interval).

- **Contents:** the 8 newest images plus 8 random older ones, each a copy with
  its caption drawn on it. On a normal day 7 of the newest stay as they are,
  one new image is drawn, and the 8 older ones are picked again.
- **Safe update:** new copies are drawn first and moved in. Then copies that
  are no longer wanted are removed. The folder is never emptied, because the
  wallpaper is using it.
- **Redraw:** when an original is newer than its copy (for example, XMP was
  added), when the caption look changes (`CAPTION_VERSION`), or when a
  narrower screen is seen.
- **Location:** local, not synced by iCloud. It is easy to pick in Settings,
  and it can be deleted and rebuilt at any time.

## Collection and settings

- **Default collection:** *iCloud Drive* › `Bing_Wallpaper`
  (`~/Library/Mobile Documents/com~apple~CloudDocs/Bing_Wallpaper`). It is
  shared by every Mac on the same iCloud account with no setup, and it does
  not depend on *Desktop & Documents Folders* being synced. It has the same
  name as the rotation folder but a different role. Without iCloud Drive the
  scripts stop and ask for `BING_WALLPAPER_DIR`, instead of creating a folder
  that looks like iCloud but is not.
- **Settings:** argument > environment variable > config file
  (`~/.config/bing-wallpaper-captions/config`) > default. The file keeps
  long-lived settings out of the launchd plist. Environment variables suit
  one-off runs. `config.sh` parses the file line by line and accepts only the
  known keys; it never runs the file as a script.

## Caption

```
往昔帝国的幽影 · Ghosts of empires past
圣巴尔多禄茂教堂，法兰克福，德国
St. Bartholomew's Cathedral in Frankfurt, Germany
2026-10-30 · © AlxeyPnferov/Getty Images        ← smaller, dimmer
```

- **The credit has its own line**, so the Chinese and English lines match.
- **The date** leads the credit line:
  - It comes first because credits vary in length, so a trailing date would
    move around.
  - `·` is the same separator as in the title line.
  - The ISO date reads the same in Chinese and English and matches the file
    names.
  - It comes from the file name, so images without XMP show it too.
- **Bottom left:** desktop icons sit on the right, and the Dock sits in the
  middle. On the right, the caption ran into two columns of icons on MacBook
  screens. `BING_CAPTION_POSITION=bottom-right` is available for desktops
  without icons.

### Margins adapt to the screen

The wallpaper fills the screen. A screen narrower than the 16:9 image cuts off
its sides. MacBook screens are narrower than 16:10, because the wallpaper also
fills the strip around the camera:

| Screen | Native | Width/height | Cut off per side | Caption from left: fixed 8% | adaptive |
|--------|--------|--------------|------------------|----------------------------|----------|
| 4K display | 3840×2160 | 1.778 | 0 | 205 pt | 77 pt |
| 14" touch MacBook Pro (2026) | 3024×1986 | 1.523 | 7.2% | 15 pt | 45 pt |
| 16" touch MacBook Pro (2026) | 3472×2266 | 1.532 | 6.9% | 22 pt | 52 pt |

Points assume the default scaling (half the native pixels). The touch-model
resolutions come from launch coverage of Apple's specs.

So:

1. `bingkit.swift screens` reports the narrowest connected screen. Portrait
   screens are ignored.
2. `rotation.sh` keeps the narrowest screen it has ever seen in
   `.screen-aspect`, so a MacBook that runs with the lid closed still fits its
   own screen. It passes that value as `BING_SCREEN_ASPECT`.
3. The left margin is 3% of the visible width, and the caption is at most 60%
   of it. With no screen information, 1.52 is used.

## One Mac downloads, every Mac shows

`bing.sh` (collect) and `rotation.sh` (show) are separate commands. Both
read their settings through `config.sh`. One Mac
that is usually on runs both. Every other Mac runs only `rotation.sh` on the
same iCloud folder, 30 minutes later. Two downloaders would create iCloud
conflict copies.

## Ideas not implemented

- **Favorites:** a Finder tag on an original adds it to every rotation.
- **Caption floating over the wallpaper** instead of drawn into it. This needs
  the current image: either the script rotates the wallpaper itself (for
  example with `NSWorkspace`) and shows an overlay, or macOS's wallpaper state
  turns out to reveal the image shown in shuffle mode.
- **Other markets:** everything assumes `cn.bing.com` (Chinese text, with
  English through `ensearch=1`).
