// bingkit.swift — image helpers for bing.sh and rotation.sh (macOS only).
// Run with `swift bingkit.swift <command> …`; needs Xcode Command Line Tools
// (`xcode-select --install`), which macOS does not ship.
//
//   tag <in.jpg> <out.jpg> <key=value>…
//       Copy a JPEG and add XMP fields, without re-encoding the image.
//       Keys: dc:title dc:description dc:rights photoshop:DateCreated
//             bing:id bing:link bing:titleEn bing:descriptionEn
//       Fields already in the file are kept.
//   info <in.jpg>…
//       Print one line per image: bing:id, TAB, 1 when both bing:titleEn
//       and bing:descriptionEn are non-empty after trimming (else 0), TAB,
//       the path. bing:id is empty for images without XMP.
//   caption <out-dir> <in.jpg>…
//       Write a copy of each image with its caption drawn bottom left.
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
import Darwin

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

    let metadata = CGImageMetadataCreateMutable()
    guard CGImageMetadataRegisterNamespaceForPrefix(metadata, bingNamespace, bingPrefix, nil)
    else { warn("bingkit: cannot register XMP namespace"); return false }
    for pair in pairs {
        // Split on Unicode scalars: as Characters, "=" followed by a joiner
        // such as U+200C forms one cluster and would not be found.
        let scalars = pair.unicodeScalars
        guard let eq = scalars.firstIndex(of: "=") else { warn("bingkit: bad field \(pair)"); return false }
        let key = String(scalars[..<eq]), value = String(scalars[scalars.index(after: eq)...])
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
    guard let checkSource = imageSource(output), let check = CGImageSourceCopyMetadataAtIndex(checkSource,0,nil) else { return false }
    for pair in pairs {
        let scalars = pair.unicodeScalars
        guard let eq = scalars.firstIndex(of:"=") else { return false }
        let key = String(scalars[..<eq]), value = String(scalars[scalars.index(after:eq)...])
        if !value.isEmpty && xmpString(check,key) != value { warn("XMP readback failed: \(key)"); return false }
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

// Collection paths are deliberately limited to the root and named archives.
func collectionFiles(_ root: String, lineSafe: Bool = true) throws -> [String] {
    let fm = FileManager.default
    var dirs = [root]
    for name in try fm.contentsOfDirectory(atPath: root) where ["archive", "archived"].contains(name.lowercased()) {
        let path = (root as NSString).appendingPathComponent(name)
        let a = try fm.attributesOfItem(atPath: path)
        guard a[.type] as? FileAttributeType == .typeDirectory else { throw NSError(domain:"unsafe archive", code:1) }
        dirs.append(path)
    }
    var files = [String]()
    for dir in dirs {
        for name in try fm.contentsOfDirectory(atPath: dir) {
            if name.hasSuffix(".icloud") { warn("skip placeholder: \(name)"); continue }
            guard name.hasSuffix(".jpg"), name.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2} "#, options:.regularExpression) != nil else { continue }
            guard !lineSafe || !name.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\t" }) else { warn("skip control characters in path"); continue }
            let path = (dir as NSString).appendingPathComponent(name)
            let a = try fm.attributesOfItem(atPath:path)
            guard a[.type] as? FileAttributeType == .typeRegular else { warn("skip nonregular: \(name)"); continue }
            // Offline dataless files must not be materialized by an inventory.
            var st = stat()
            guard lstat(path, &st) == 0, st.st_flags & 0x40000000 == 0 else { warn("skip offline: \(name)"); continue }
            files.append(path)
        }
    }
    let groups = Dictionary(grouping:files) { String(($0 as NSString).lastPathComponent.prefix(10)) }
    return groups.keys.sorted().flatMap { day -> [String] in
        let group = groups[day]!
        guard group.count == 1 else { warn("skip ambiguous date: \(day) (\(group.count) files)"); return [] }
        return group
    }
}
func filename(_ date:String, _ fields:[String:String]) throws -> String {
    let lang = ProcessInfo.processInfo.environment["BING_FILENAME_LANGUAGE"] ?? "en"
    let credit = ProcessInfo.processInfo.environment["BING_FILENAME_CREDIT"] ?? "0"
    guard ["en","zh"].contains(lang), ["0","1"].contains(credit),
          date.range(of:#"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#,options:.regularExpression) != nil else { throw NSError(domain:"invalid filename settings/date",code:2) }
    func clean(_ v:String) -> String {
        let v = v.precomposedStringWithCanonicalMapping.replacingOccurrences(of:"/",with:", ").replacingOccurrences(of:":",with:" - ")
        let scalars = v.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && !"()\\*?\"<>|".unicodeScalars.contains($0) }
        return String(String.UnicodeScalarView(scalars)).split(whereSeparator:{$0.isWhitespace}).joined(separator:" ").trimmingCharacters(in:CharacterSet(charactersIn:" ."))
    }
    let first = lang == "en" ? "bing:descriptionEn" : "dc:description"
    let second = lang == "en" ? "dc:description" : "bing:descriptionEn"
    var desc = ""
    for key in [first,second,"bing:id"] {
        let candidate = clean(fields[key] ?? "")
        if !candidate.isEmpty { desc = candidate; if key != first { warn("note: \(date) filename falls back to \(key)") }; break }
    }
    guard !desc.isEmpty else { throw NSError(domain:"no reliable filename",code:1) }
    let rights = clean(fields["dc:rights"] ?? "")
    if credit == "1" && rights.isEmpty { warn("note: \(date) has no copyright record") }
    let suffix = credit == "1" && !rights.isEmpty ? " " + rights : ""
    let budget = 236 - suffix.utf8.count
    guard budget > 0 else { throw NSError(domain:"copyright exceeds filename budget",code:1) }
    var limited = ""
    for c in desc { if (limited + String(c)).utf8.count > budget { break }; limited.append(c) }
    guard !limited.isEmpty else { throw NSError(domain:"description exceeds filename budget",code:1) }
    return date + " " + limited.trimmingCharacters(in:CharacterSet(charactersIn:" .")) + suffix + ".jpg"
}
let fieldKeys = ["dc:title","dc:description","dc:rights","photoshop:DateCreated","bing:id","bing:link","bing:titleEn","bing:descriptionEn"]
func fields(_ path:String) throws -> [String:String] {
    guard let source = imageSource(path), let m = CGImageSourceCopyMetadataAtIndex(source,0,nil) else { throw NSError(domain:"missing metadata",code:1) }
    return Dictionary(uniqueKeysWithValues:fieldKeys.map { ($0,xmpString(m,$0)) })
}
func exclusiveMove(_ from:String,_ to:String) throws {
    guard renamex_np(from,to,UInt32(RENAME_EXCL)) == 0 else { throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno)) }
}

func physicalDirectory(_ path: String) throws -> URL {
    guard let resolved = realpath(path + "/.", nil) else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    defer { free(resolved) }
    return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
}

// Return the existing directory and any components mkdir still needs to create.
// Resolve links before "..", including when a missing component is backed out.
func directoryPrefix(_ path: String) throws -> (existing: URL, missing: [String]) {
    let scalars = path.unicodeScalars
    var dir = URL(fileURLWithPath: scalars.first == "/" ? "/" : FileManager.default.currentDirectoryPath,
                  isDirectory: true)
    var missing = [String]()
    for component in scalars.split(separator: "/").map(String.init) {
        if component == "." { continue }
        if component == ".." {
            if !missing.isEmpty { missing.removeLast() }
            else if dir.path != "/" { dir.deleteLastPathComponent() }
            continue
        }
        if missing.isEmpty {
            let next = dir.appendingPathComponent(component, isDirectory: true)
            var entry = stat()
            if lstat(next.path, &entry) == 0 {
                dir = try physicalDirectory(next.path)
                continue
            }
            guard errno == ENOENT else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        }
        missing.append(component)
    }
    return (dir, missing)
}

func isAncestorOrSame(_ ancestor: URL, of directory: URL) throws -> Bool {
    var target = stat()
    guard stat(ancestor.path, &target) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    var dir = directory
    while true {
        var entry = stat()
        guard stat(dir.path, &entry) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        if entry.st_dev == target.st_dev && entry.st_ino == target.st_ino { return true }
        if dir.path == "/" { return false }
        dir.deleteLastPathComponent()
    }
}

func jsonLine(_ value:Any) -> String {
    String(data:try! JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]),encoding:.utf8)!
}

// MARK: main

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }
switch command {
case "check-output":
    guard args.count == 3 else { usage() }
    do {
        let src = try physicalDirectory(args[1])
        let (parent, missing) = try directoryPrefix(args[2])
        if try isAncestorOrSame(src, of: parent) || (missing.isEmpty && isAncestorOrSame(parent, of: src)) {
            warn("rotation output must not overlap collection")
            exit(1)
        }
        let output = missing.reduce(parent) { $0.appendingPathComponent($1, isDirectory: true) }
        // A final slash preserves any trailing newline in the name through shell command substitution.
        print(output.path + "/")
    } catch { warn("check-output: \(error)"); exit(1) }
case "fields":
    guard args.count >= 2 else { usage() }
    for path in args.dropFirst() {
        do { print(jsonLine(["path":path,"fields":try fields(path)])) }
        catch { warn("fields: \(path): \(error)"); exit(1) }
    }
case "restore":
    guard args.count == 3 else { usage() }
    do {
        let root = URL(fileURLWithPath:args[1]).resolvingSymlinksInPath().path
        let data = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        var failed = false
        for line in data.split(separator: 0x0A).reversed() {
            let record: Any
            do {
                record = try JSONSerialization.jsonObject(with: line)
            } catch where line.endIndex == data.endIndex {
                warn("restore: skipped incomplete trailing recovery record")
                failed = true
                continue
            }
            guard let r = record as? [String:Any],
                  let from = r["source"] as? String, let to = r["target"] as? String else { continue }
            do {
                let parent = URL(fileURLWithPath:from).deletingLastPathComponent().resolvingSymlinksInPath().path
                let targetParent = URL(fileURLWithPath:to).deletingLastPathComponent().resolvingSymlinksInPath().path
                guard parent == targetParent, parent == root || (URL(fileURLWithPath:parent).deletingLastPathComponent().path == root && ["archive","archived"].contains((parent as NSString).lastPathComponent.lowercased())) else { throw NSError(domain:"log outside collection",code:1) }
                let a = try FileManager.default.attributesOfItem(atPath:to)
                guard a[.type] as? FileAttributeType == .typeRegular,
                      a[.systemFileNumber] as? NSNumber == r["inode"] as? NSNumber,
                      a[.size] as? NSNumber == r["size"] as? NSNumber,
                      (a[.modificationDate] as! Date).timeIntervalSince1970 == r["mtime"] as? Double else { throw NSError(domain:"target changed; do not restore",code:1) }
                try exclusiveMove(to,from)
                print(jsonLine(["restored":from]))
            } catch { warn("restore skipped \(to): \(error)"); failed = true }
        }
        if failed { exit(1) }
    } catch { warn("restore: \(error)"); exit(1) }
case "list":
    guard args.count == 2 else { usage() }
    do { for path in try collectionFiles(args[1]) { print(path) } } catch { warn("inventory: \(error)"); exit(1) }
case "name":
    guard args.count == 3 else { usage() }
    do { print(try filename(args[2], fields(args[1]))) } catch { warn("filename: \(error)"); exit(1) }
case "move":
    guard args.count == 3 else { usage() }
    do { try exclusiveMove(args[1],args[2]) } catch { warn("move: \(error)"); exit(1) }
case "rename":
    guard args.count == 2 || args.count == 4 && args[2] == "--apply" else { usage() }
    do {
        let apply = args.count == 4
        let root = try physicalDirectory(args[1])
        let files = try collectionFiles(apply ? root.path : args[1], lineSafe:false)
        var log: FileHandle?
        if apply {
            let logPath = args[3] as NSString
            let parent = logPath.deletingLastPathComponent
            let logDir = try physicalDirectory(parent.isEmpty ? "." : parent)
            guard try !isAncestorOrSame(root, of: logDir) else {
                warn("recovery log must be outside the collection")
                exit(1)
            }
            guard logPath.length > 0, !logPath.hasSuffix("/") else { usage() }
            let newLog = logDir.appendingPathComponent(logPath.lastPathComponent)
            let fd = open(newLog.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            guard fd >= 0 else { warn("recovery log must be a new writable file"); exit(1) }
            log = FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        }
        var failed = false
        for path in files {
            do {
                let before = try FileManager.default.attributesOfItem(atPath:path)
                let f = try fields(path)
                guard !(f["dc:description"] ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
                      !(f["dc:rights"] ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
                      !(f["bing:id"] ?? "").isEmpty else { throw NSError(domain:"incomplete XMP: keep original name",code:1) }
                let name = try filename(String((path as NSString).lastPathComponent.prefix(10)),f)
                let to = ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(name)
                if path == to { continue }
                guard !FileManager.default.fileExists(atPath:to) else { throw NSError(domain:"target exists: keep original",code:1) }
                let record: [String:Any] = ["source":path,"target":to,"size":before[.size]!,"inode":before[.systemFileNumber]!,"mtime":(before[.modificationDate] as! Date).timeIntervalSince1970]
                if apply {
                    log!.write((jsonLine(record)+"\n").data(using:.utf8)!); log!.synchronizeFile()
                    let now = try FileManager.default.attributesOfItem(atPath:path)
                    for k:FileAttributeKey in [.systemFileNumber,.size,.modificationDate] {
                        guard String(describing:before[k]) == String(describing:now[k]) else { throw NSError(domain:"source changed",code:1) }
                    }
                    try exclusiveMove(path,to)
                    log!.write((jsonLine(["completed":to])+"\n").data(using:.utf8)!);log!.synchronizeFile()
                }
                print(jsonLine(record))
            } catch { warn("skip \(path): \(error)"); failed = true }
        }
        if failed { exit(1) }
    } catch { warn("rename: \(error)"); exit(1) }

case "fill":
    guard args.count >= 3 else { usage() }
    do {
        let existing = try fields(args[1])
        let pairs = args.dropFirst(3).filter { pair in
            let scalars = pair.unicodeScalars
        guard let eq = scalars.firstIndex(of:"=") else { return false }
            let key = String(scalars[..<eq])
            return ["bing:titleEn","bing:descriptionEn"].contains(key) && (existing[key] ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
        }
        exit(tag(args[1],args[2],Array(pairs)) ? 0 : 1)
    } catch { warn("fill: \(error)"); exit(1) }
case "tag":
    guard args.count >= 3 else { usage() }
    exit(tag(args[1], args[2], Array(args.dropFirst(3))) ? 0 : 1)
case "info":
    guard args.count >= 2 else { usage() }
    var ok = true
    for input in args.dropFirst() {
        guard let source = imageSource(input), CGImageSourceGetCount(source) > 0 else {
            warn("bingkit: cannot read \(input)"); ok = false; continue
        }
        var id = "", english = "0"
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            id = xmpString(metadata, "bing:id")
            english = (!xmpString(metadata, "bing:titleEn").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && !xmpString(metadata, "bing:descriptionEn").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) ? "1" : "0"
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
