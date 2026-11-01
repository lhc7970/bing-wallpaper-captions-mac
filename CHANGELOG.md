# Changelog

Notable changes. Format based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed
- The random older images in the rotation folder are picked once per day (a
  hash of the date and the file name), not on every run, so the extra daily
  runs no longer replace them each time.
- A new image waits (up to 24 hours) until its English text is published,
  about 15 hours after the Chinese text, so it is not saved without English.
  The suggested daily times are now 16:00 and 22:00 China time.
- English text that was missing when an image was saved is filled in by a later
  run while Bing still lists the image, matched by the image's `bing:id`.
- `bingkit.swift info` reports an image's `bing:id` and whether it has English
  text; `tag` keeps a file's existing `bing:` namespace.

## [0.1.0] - 2026-11-01

First public version.

### Added
- `bing.sh`: downloads the UHD Bing images of the last 15 days into a
  collection folder, one image per date. Skips iCloud conflict copies and
  placeholders, and never downloads an image again after you delete it
  (`.bing-downloaded`). Downloads are atomic.
- XMP metadata in each new image (title, description, credit, date, link,
  image ID, English title and description), written without re-encoding.
- `rotation.sh`: builds a folder of captioned copies (8 newest + 8 random
  older) for the macOS wallpaper rotation. It keeps unchanged copies and never
  empties the folder.
- Chinese and English captions bottom left, with the date and credit on the
  last line. Margins adapt to the narrowest screen the Mac uses.
- `bingkit.swift`: the ImageIO / AppKit helper behind XMP and captions.
- Settings from an optional config file
  (`~/.config/bing-wallpaper-captions/config`), overridden by environment
  variables and the command argument. The default collection is
  *iCloud Drive* › `Bing_Wallpaper`.
