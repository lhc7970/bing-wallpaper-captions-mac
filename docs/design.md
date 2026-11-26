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

Timing, checked over 15 days: each image appears in Chinese at 16:00 UTC (00:00
China time) and in English exactly **15 hours later** (07:00 UTC, 15:00 China
time). So `bing.sh` holds back a new image whose English text is not out yet:
it is neither downloaded nor recorded, and a later run picks it up. After 24
hours it is saved without English, in case an image never reaches the English
market. Scheduling the daily run after 07:00 UTC means it rarely has to wait;
the rule covers runs at login or wake-up. A second daily run before 16:00 UTC
(22:00 China time) catches a late English text on the same day.

Last, a run fills in English text that was missing when an image was saved,
for every image Bing still lists. `bingkit.swift info` reads each candidate's
`bing:id` and whether it has English; the English text is taken by that ID
only, so a date mix-up or a market showing a different picture cannot pair
the wrong texts. Images without XMP are skipped. `tag` merges into the
existing XMP. Backfill creates the replacement in a private staging directory
under the original's parent, so installation is a single rename even when
the archive and the system temporary directory are on different volumes.

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
- **One random pick per day:** the job runs more than once a day (16:00,
  22:00, at login). Each older image is ranked by a hash of the local date and
  its path in the collection. Macs with the same date, candidate paths and
  counts pick the same images. A new arrival can push a formerly recent image
  into the older pool, where its rank can displace an earlier pick.
  Changing the folder on every run left System Settings, open for a day,
  showing many missing thumbnails; it appears to
  keep an older list of the folder.
- **Safe update:** new copies are drawn first and moved in. Then copies that
  are no longer wanted are removed. The folder is never emptied, because the
  wallpaper is using it.
- Rotation uses the physical collection root for both inventory and rendering.
  Before creating the output, it compares directory device and inode numbers
  along the existing paths. A new child of a case or symlink alias of the
  collection would otherwise put generated copies among the originals.
- **Redraw:** when an original is newer than its copy (for example, XMP was
  added), when the caption look or its configured side changes, or when a
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

## Floating captions over original wallpapers (issue #9)

Could a Mac use the original JPEG as its wallpaper and display the same caption
without generating a rotation folder? The first question is whether the Mac can
identify the photo actually visible on each desktop. Test native shuffle first.
If it exposes the original reliably, the user can keep the interval and random
order in Wallpaper settings. An app that sets each photo itself can associate a
caption with its own selection, at the cost of owning the rotation schedule.
Neither route has been verified on the target Mac.

| Question | Keep macOS folder shuffle | Let an app rotate originals |
|---|---|---|
| Which image is showing? | `NSWorkspace.desktopImageURL(for:)` accepts an `NSScreen` and can return nil. Its contract does not specify whether a shuffled folder yields the currently visible member. Compare each result with the visible photo. A folder, cache URL of unknown provenance, or stale path cannot identify an original. | Choose a readable original and call `setDesktopImageURL(_:for:options:)` for one screen. The caller knows the requested URL and gets success or an error. Check readback and visible pixels after success, including after another wallpaper choice in Settings. |
| When does the caption change? | The SDK declares Space-change, wake and screen-configuration notifications. None promises a callback for each shuffle. Sample the getter periodically as well as on those events. Measure delay from visible change to correct URL. Hide the caption while the source is unknown. | Read the caption from the chosen URL, then publish it for that screen after a successful set and matching readback. Check transition lag. On failure, wake, restart or an external change, reconcile with the current desktop before displaying any saved caption. |
| Multiple displays | Query every connected `NSScreen`. Verify two extended displays can report different originals simultaneously and refresh independently when one changes. | Make a separate set call per intended display. Test that changing one leaves the other correct, including when a display disconnects and reconnects. Re-enumerate screens after a layout change. |
| Spaces | The getter takes a screen and has no Space argument. On an active-Space change, re-query each screen. Test by switching between desktops with different images on the same display. | The setter also takes no Space argument. Test which desktop changes and what the first desktop shows on return. A record of the last URL set for a display cannot establish the wallpaper of its other Spaces. |
| Full-screen apps | The getter can be sampled on entry and exit. Check that the caption stays behind the app and resolves to the visible original on return, even if shuffle advanced. | A scheduled set can coincide with a full-screen Space. Test its effect on returning to the desktop before deciding whether to defer rotation there. Check the other display separately. |

These API bounds come from the macOS 27.0 SDK, particularly the
`NSDesktopImages` declarations in AppKit's `NSWorkspace.h`. A matching
URL is evidence of identity only after comparison with the desktop. Pointing
native shuffle at the collection also gives macOS control of folder membership.
Check whether archived photos participate. Today [rotation.sh](../rotation.sh)
includes eligible archived originals and selects eight recent and eight older
images by default. An app-owned scheduler could reuse that selection before
setting an original URL.

### Displaying and reading the caption

A resident AppKit helper could place one transparent, borderless window per
display, aligned to its visible frame. Try a window level between the Core
Graphics desktop and desktop-icon levels, with `ignoresMouseEvents` enabled
and a window that cannot become key. AppKit's `canJoinAllSpaces` controls
where a window may appear. It supplies no wallpaper identity. Test stacking,
focus and Space transitions on the device. The proposed target is a caption
visible on the desktop, behind ordinary windows and full-screen apps.

A desktop WidgetKit widget suits a user-placed caption card. The host controls
placement and timeline delivery. A helper can request `reloadTimelines(ofKind:)`,
but that request carries neither a deadline nor a screen ID. A widget would
still need a source for the image and a way to associate the card with that
display. Use the window for the synchronized corner caption experiment. A
widget is worth testing if a movable card with delayed updates is acceptable.

Both routes can reuse `caption(for:_:)` and `xmpString(_:_:)` in
[bingkit.swift](../bingkit.swift). They read the original with ImageIO, take the
date from its filename, and extract Chinese title, description and credit plus
the two English fields. When the description is missing, the reader falls back
to the filename, splitting off a trailing credit when present. The drawing code
already omits empty lines. Only the text reader and line formatting are needed
by a window. For a device check, `swift bingkit.swift fields "/path/to/original.jpg"`
prints raw XMP as JSON, including `bing:id`. It does not apply the display
fallback. Always resolve the original before reading its caption.

### Target Mac check

1. In a test login, record `sw_vers`, display layout, “Displays have separate
   Spaces”, and the starting Wallpaper settings for each desktop. Use two
   extended displays if available and create a second desktop on the first.
   Put copies of three visually distinct original JPEGs in a test folder. Label
   them A, B and C in your notes and keep their dated filenames. From the repo
   root, run `swift bingkit.swift caption "$refs" "$a" "$b" "$c"`, where the
   lowercase variables are the three paths and `$refs` is an existing empty
   directory outside the wallpaper folder. Read the expected caption from each
   rendered copy and record it with the original filename and visible subject.
   Include a JPEG with XMP but no `dc:description` and one without XMP in the
   caption check. Verify the rendered lines against their filename fallback.
   Run `fields` separately on each original and keep its raw JSON or error and
   exit status alongside the reference.
2. From Terminal in that login, save this probe as `probe.swift` in a scratch
   directory and run `swiftc probe.swift -o probe` there. Running `./probe`
   is read-only. The two-argument form sets the specified display's wallpaper.

   ```swift
   import AppKit

   func fail(_ message: String, status: Int32) -> Never {
       FileHandle.standardError.write(Data(("probe: " + message + "\n").utf8))
       exit(status)
   }

   let args = Array(CommandLine.arguments.dropFirst())
   guard args.isEmpty || args.count == 2 else {
       fail("usage: ./probe [DISPLAY_ID IMAGE_PATH]", status: 2)
   }
   let workspace = NSWorkspace.shared
   let displays = NSScreen.screens.compactMap { screen -> (id: String, screen: NSScreen)? in
       let key = NSDeviceDescriptionKey("NSScreenNumber")
       guard let id = screen.deviceDescription[key] as? NSNumber else { return nil }
       return (id.stringValue, screen)
   }
   if args.count == 2 {
       guard let target = displays.first(where: { $0.id == args[0] }) else {
           fail("no connected display with ID \(args[0])", status: 2)
       }
       do {
           let url = URL(fileURLWithPath: args[1])
           try workspace.setDesktopImageURL(url, for: target.screen,
               options: workspace.desktopImageOptions(for: target.screen) ?? [:])
       } catch {
           fail("setting \(args[1]) on display \(target.id): \(error.localizedDescription)", status: 1)
       }
   }
   for (id, screen) in displays {
       print(Date(), id, screen.localizedName,
             workspace.desktopImageURL(for: screen)?.absoluteString ?? "nil")
   }
   ```

3. **Native shuffle.** First select a single known JPEG and check the probe
   against it. Then select the test folder, random order and the shortest
   available interval. Choose the longest acceptable delay and a fixed
   observation period (for example, five shuffle intervals). Run
   `while true; do ./probe; sleep 1; done` in Terminal.
   For every visible change during that period, record the time, display, desktop, subject and
   time of the first matching URL. Mark a miss if no match arrives within the
   accepted delay, even if a later sample matches. Keep nil, directory, cached,
   stale and cross-display results verbatim. At the end of the period, allow
   one delay window for pending matches, then stop with Control-C. Fewer than
   three visible changes leaves coverage incomplete.
4. **App-owned rotation.** Switch off shuffle for the test. From the same
   directory run `./probe DISPLAY_ID "/absolute/path/to/A.jpg"`, replacing
   the ID with one printed by the probe. Set B on the other display. With a
   fresh `./probe`, verify both URLs and visible subjects are A/B before
   proceeding. Set C on the first display only. Verify both again and require
   C/B. Seeing C/C exposes a change to the untargeted display.

   Run `./probe absent-id "$a"` and immediately check `echo $?` (expect 2
   and a diagnostic naming the unknown ID). Repeat with a connected ID and
   a nonexistent file. Record the setter's exit status (1 on API error), run
   a separate read-only `./probe`, and record both visible subjects and URLs.
   After a rejected set, expect C/B. Then change one image in Settings to test
   drift.
5. **Repeat for both routes.** Give the two desktops on one display different
   known images or shuffle sources. Switch away and back, enter full screen
   on one display for a rotation interval, then exit. For the setter route,
   queue a change from Terminal before entering full screen, for example
   `sleep 15 && ./probe DISPLAY_ID "/absolute/path/to/B.jpg"`.
   Disconnect/reconnect the external screen and sleep/wake the Mac. Sample
   each time and record which desktop actually changed. Mark unavailable
   layouts or settings as untested.
6. **Presentation needs a prototype.** Repeat those transitions with the
   candidate window showing each source's caption. Verify the text against
   the visible image, click and drag a Finder icon through the caption area,
   cover it with a normal window, then enter and exit full screen. Record
   stale text duration, focus changes and any caption drawn over an app. For
   a widget trial, place a card on each display and record placement and actual
   update time after a change. The URL probe alone cannot verify either UI.
   Restore the starting wallpaper settings before removing the test files.

Record the macOS build, route, display ID, active desktop, visible subject,
returned URL, expected/observed text and delay together for each transition.
Prefer native shuffle only if the visible original can be resolved on every
tested desktop within the owner's acceptable delay. If that fails, the setter
results and the owner's willingness to hand over rotation determine whether to
pursue the helper. The rendered-copy workflow remains the available fallback.

## Ideas not implemented

- **Favorites:** a Finder tag on an original adds it to every rotation.
- **Other markets:** everything assumes `cn.bing.com` (Chinese text, with
  English through `ensearch=1`).


## Filename policy update (Issue #5)

The filename layer is now `YYYY-MM-DD <selected description>[ <credit>].jpg`,
defaulting to English without credit. The XMP table and namespace above do not
change. Read README's “Filename settings and archives” for the current failure,
archive, lock and migration contracts; it supersedes the old filename/fallback
examples above. Rotation inventories immediate named archive folders, rejects
ambiguous dates and never prunes old copies after generation or installation
failure. `info` retains its three-column contract, but hasEn now means both English
fields are present. `fields` exports JSON; `fill` updates missing English only.
