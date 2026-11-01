// bingkit.swift — image helpers for bing.sh and rotation.sh (macOS only).
// Run with `swift bingkit.swift <command> …`; needs Xcode Command Line Tools
// (`xcode-select --install`), which macOS does not ship.
//
//   tag <in.jpg> <out.jpg> <key=value>…
//       Copy a JPEG and add XMP fields, without re-encoding the image.
//       Keys: dc:title dc:description dc:rights photoshop:DateCreated
//             bing:id bing:link bing:titleEn bing:descriptionEn
//       Fields already in the file are kept. If the file already uses a
//       namespace for `bing:` (an older one), the new fields join it.
//   info <in.jpg>…
//       Print one line per image: bing:id, TAB, 1 if bing:titleEn is set
//       (else 0), TAB, the path. bing:id is empty for images without XMP.
//   caption <out-dir> <in.jpg>…
//       Write a copy of each image with its caption drawn bottom right.
//       Text comes from the XMP written by `tag`; images without it use
//       their file name ("YYYY-MM-DD <description> © <credit>.jpg").
//       BING_CAPTION_POSITION: bottom-left (default) or bottom-right.
//       BING_SCREEN_ASPECT: width/height of the narrowest screen the copies
//       will be shown on (rotation.sh passes it). The wallpaper fills the
//       screen, so a narrower screen cuts more off the sides; margins grow by
//       that much. Default 1.52, the narrowest MacBook screen.
//   screens
//       Print width/height of the narrowest screen connected now (or nothing).
//
// Exit codes: 0 ok · 1 at least one image failed · 2 usage error.

import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// An identifier for this project's XMP fields; it does not need to resolve.
let bingNamespace = "https://github.com/lhc7970/bing-wallpaper-captions-mac/xmp/1.0/" as CFString
let bingPrefix = "bing" as CFString

func warn(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func usage() -> Never {
    warn("usage: swift bingkit.swift tag <in.jpg> <out.jpg> <key=value>...")
    warn("       swift bingkit.swift caption <out-dir> <in.jpg>...")
    warn("       swift bingkit.swift info <in.jpg>...")
    warn("       swift bingkit.swift screens")
    exit(2)
}

func imageSource(_ path: String) -> CGImageSource? {
    CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
}

// MARK: tag

func tag(_ input: String, _ output: String, _ pairs: [String]) -> Bool {
    guard let source = imageSource(input), let type = CGImageSourceGetType(source),
          let destination = CGImageDestinationCreateWithURL(
              URL(fileURLWithPath: output) as CFURL, type, 1, nil)
    else { warn("bingkit: cannot read \(input)"); return false }

    // Reuse the file's own `bing:` namespace, so one file never has two.
    var namespace = bingNamespace
    if let existing = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
       let idTag = CGImageMetadataCopyTagWithPath(existing, nil, "bing:id" as CFString),
       let uri = CGImageMetadataTagCopyNamespace(idTag) {
        namespace = uri
    }
    let metadata = CGImageMetadataCreateMutable()
    guard CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace, bingPrefix, nil)
    else { warn("bingkit: cannot register XMP namespace"); return false }
    for pair in pairs {
        guard let eq = pair.firstIndex(of: "=") else { warn("bingkit: bad field \(pair)"); return false }
        let key = String(pair[..<eq]), value = String(pair[pair.index(after: eq)...])
        if value.isEmpty { continue }
        guard CGImageMetadataSetValueWithPath(metadata, nil, key as CFString, value as CFString)
        else { warn("bingkit: cannot set \(key)"); return false }
    }
    let options = [kCGImageDestinationMetadata: metadata,
                   kCGImageDestinationMergeMetadata: true] as CFDictionary
    var error: Unmanaged<CFError>?
    guard CGImageDestinationCopyImageSource(destination, source, options, &error) else {
        warn("bingkit: cannot write \(output): \(String(describing: error?.takeRetainedValue()))")
        return false
    }
    return true
}

// MARK: caption text

struct Caption {
    var date = "", title = "", titleEn = "", description = "", credit = "", descriptionEn = ""
}

// Reads a text XMP value; language alternatives (dc:title etc.) return x-default.
func xmpString(_ metadata: CGImageMetadata, _ path: String) -> String {
    guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString),
          let value = CGImageMetadataTagCopyValue(tag) else { return "" }
    if let string = value as? String { return string }
    if let items = value as? [CGImageMetadataTag], let first = items.first,
       let string = CGImageMetadataTagCopyValue(first) as? String { return string }
    return ""
}

func caption(for path: String, _ source: CGImageSource) -> Caption {
    var c = Caption()
    // The file name always starts with the date (YYYY-MM-DD).
    let fileName = (path as NSString).lastPathComponent
    if fileName.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2} "#, options: .regularExpression) != nil {
        c.date = String(fileName.prefix(10))
    }
    if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
        c.title = xmpString(metadata, "dc:title")
        c.description = xmpString(metadata, "dc:description")
        c.credit = xmpString(metadata, "dc:rights")
        c.titleEn = xmpString(metadata, "bing:titleEn")
        c.descriptionEn = xmpString(metadata, "bing:descriptionEn")
    }
    if c.description.isEmpty {
        // "YYYY-MM-DD <description> © <credit>.jpg"
        var name = (path as NSString).lastPathComponent
        if name.hasSuffix(".jpg") { name.removeLast(4) }
        if name.count > 11 { name.removeFirst(11) }
        if let r = name.range(of: " © ", options: .backwards) {
            c.description = String(name[..<r.lowerBound])
            c.credit = "© " + String(name[r.upperBound...])
        } else {
            c.description = name
        }
    }
    return c
}

// MARK: caption drawing

func drawCaption(_ input: String, into directory: String) -> Bool {
    guard let source = imageSource(input),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let srgb = CGColorSpace(name: CGColorSpace.sRGB)
    else { warn("bingkit: cannot read \(input)"); return false }
    let width = image.width, height = image.height
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: srgb,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { warn("bingkit: cannot draw \(input)"); return false }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    let c = caption(for: input, source)
    let h = CGFloat(height), w = CGFloat(width)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.8)
    shadow.shadowOffset = NSSize(width: 0, height: -h / 1100)
    shadow.shadowBlurRadius = h / 180
    let onLeft = ProcessInfo.processInfo.environment["BING_CAPTION_POSITION"] != "bottom-right"
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = onLeft ? .left : .right
    func style(_ size: CGFloat, _ weight: NSFont.Weight, _ alpha: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: size, weight: weight),
         .foregroundColor: NSColor(white: 1, alpha: alpha),
         .shadow: shadow, .paragraphStyle: paragraph]
    }
    let big = style(h / 48, .semibold, 0.96), small = style(h / 66, .medium, 0.9)
    let tiny = style(h / 84, .regular, 0.72)

    // Bottom line first; blocks stack upwards:
    //   title · English title / description / English description / date · credit
    var blocks: [NSAttributedString] = []
    // "2026-10-30 · © Author/Agency": date first, same separator as the titles.
    let dateCredit = [c.date, c.credit].filter { !$0.isEmpty }.joined(separator: " · ")
    if !dateCredit.isEmpty { blocks.append(NSAttributedString(string: dateCredit, attributes: tiny)) }
    if !c.descriptionEn.isEmpty { blocks.append(NSAttributedString(string: c.descriptionEn, attributes: small)) }
    if !c.description.isEmpty { blocks.append(NSAttributedString(string: c.description, attributes: small)) }
    let titles = [c.title, c.titleEn].filter { !$0.isEmpty }.joined(separator: " · ")
    if !titles.isEmpty { blocks.append(NSAttributedString(string: titles, attributes: big)) }

    // Margins are measured on the part of the image the screen shows. A
    // screen narrower than the image (MacBook: ~1.52 vs 16:9 = 1.78) cuts
    // `crop` off each side. Left: 3% of the visible width. Right: 12%, which
    // clears two columns of desktop icons. The bottom margin clears the Dock.
    let screenAspect = Double(ProcessInfo.processInfo.environment["BING_SCREEN_ASPECT"] ?? "") ?? 1.52
    let visible: CGFloat = min(1, CGFloat(screenAspect) / (w / h))
    let crop: CGFloat = w * (1 - visible) / 2
    let visibleWidth: CGFloat = w * visible
    let maxWidth: CGFloat = visibleWidth * 0.6
    let x: CGFloat = onLeft ? crop + visibleWidth * 0.03 : w - crop - visibleWidth * 0.12 - maxWidth
    var y = h * 0.085
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    for block in blocks {
        let size = block.boundingRect(with: NSSize(width: maxWidth, height: h),
                                      options: [.usesLineFragmentOrigin]).size
        block.draw(with: NSRect(x: x, y: y, width: maxWidth, height: ceil(size.height)),
                   options: [.usesLineFragmentOrigin])
        y += ceil(size.height) + h * 0.004
    }
    NSGraphicsContext.restoreGraphicsState()

    guard let result = context.makeImage() else { return false }
    let output = (directory as NSString).appendingPathComponent((input as NSString).lastPathComponent)
    guard let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: output) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
    else { warn("bingkit: cannot write \(output)"); return false }
    let properties = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
    CGImageDestinationAddImageAndMetadata(
        destination, result, CGImageSourceCopyMetadataAtIndex(source, 0, nil), properties)
    guard CGImageDestinationFinalize(destination) else { warn("bingkit: cannot write \(output)"); return false }
    return true
}

// MARK: main

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }
switch command {
case "tag":
    guard args.count >= 3 else { usage() }
    exit(tag(args[1], args[2], Array(args.dropFirst(3))) ? 0 : 1)
case "info":
    guard args.count >= 2 else { usage() }
    var ok = true
    for input in args.dropFirst() {
        guard let source = imageSource(input) else { warn("bingkit: cannot read \(input)"); ok = false; continue }
        var id = "", english = "0"
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            id = xmpString(metadata, "bing:id")
            english = xmpString(metadata, "bing:titleEn").isEmpty ? "0" : "1"
        }
        print("\(id)\t\(english)\t\(input)")
    }
    exit(ok ? 0 : 1)
case "screens":
    // Screens narrower than 4:3 (portrait) would push the caption to the
    // middle; they are left out.
    let aspects = NSScreen.screens.map { $0.frame.width / $0.frame.height }.filter { $0 >= 4.0 / 3.0 }
    if let narrowest = aspects.min() { print(String(format: "%.3f", narrowest)) }
    exit(0)
case "caption":
    guard args.count >= 3 else { usage() }
    var ok = true
    for input in args.dropFirst(2) where !drawCaption(input, into: args[1]) { ok = false }
    exit(ok ? 0 : 1)
default:
    usage()
}
