#!/usr/bin/env swift
import Foundation

enum SidebarError: Error, CustomStringConvertible {
    case io(String)
    case structure(String)
    case invalidPath(String)
    case bookmark(String)

    var description: String {
        switch self {
        case .io(let s): return s
        case .structure(let s): return s
        case .invalidPath(let s): return s
        case .bookmark(let s): return s
        }
    }
}

func logerr(_ s: String) {
    if let data = (s + "\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

func favoritesFileURL() throws -> URL {
    let fm = FileManager.default
    guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else { throw SidebarError.io("Unable to locate Application Support directory") }

    let dir = appSupport.appendingPathComponent("com.apple.sharedfilelist", isDirectory: true)

    let fileName: String
    if #available(macOS 26, *) {
        fileName = "com.apple.LSSharedFileList.FavoriteItems.sfl4"
    } else {
        fileName = "com.apple.LSSharedFileList.FavoriteItems.sfl3"
    }

    return dir.appendingPathComponent(fileName, isDirectory: false)
}

func createEmptySFLIfMissing(_ url: URL) throws {
    let fm = FileManager.default
    if fm.fileExists(atPath: url.path) { return }
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

    let root = NSMutableDictionary()
    root["items"] = NSArray()
    root["properties"] = NSDictionary(object: 1, forKey: "com.apple.LSSharedFileList.ForceTemplateIcons" as NSString)

    try saveSFL(url, dict: root)
}

func openSFL(_ url: URL) throws -> NSMutableDictionary {
    let fm = FileManager.default
    
    // Check if file exists first to provide better error messages
    if !fm.fileExists(atPath: url.path) {
        throw SidebarError.io("SFL file does not exist at \(url.path). It should have been created.")
    }
    
    // Check if file is readable
    if !fm.isReadableFile(atPath: url.path) {
        throw SidebarError.io("Unable to read SFL file at \(url.path). Full Disk Access may be required for your terminal.")
    }
    
    let data: Data
    do { data = try Data(contentsOf: url) }
    catch let error as NSError {
        if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
            throw SidebarError.io("Permission denied reading \(url.path). Full Disk Access may be required.")
        }
        throw SidebarError.io("Unable to read SFL file at \(url.path): \(error.localizedDescription)")
    }

    let allowed: [AnyClass] = [
        NSDictionary.self, NSMutableDictionary.self,
        NSArray.self, NSMutableArray.self,
        NSString.self, NSMutableString.self,
        NSData.self, NSMutableData.self,
        NSNumber.self, NSUUID.self, NSDate.self
    ]

    let obj: NSDictionary
    do {
        guard let unarchived = try NSKeyedUnarchiver.unarchivedObject(ofClasses: allowed, from: data) as? NSDictionary
        else { throw SidebarError.structure("Unarchived object is not a dictionary") }
        obj = unarchived
    } catch {
        throw SidebarError.structure("Unable to unarchive SFL data: \(error)")
    }

    return NSMutableDictionary(dictionary: obj)
}

func saveSFL(_ url: URL, dict: NSMutableDictionary) throws {
    let archived: Data
    do {
        archived = try NSKeyedArchiver.archivedData(withRootObject: dict, requiringSecureCoding: false)
    } catch {
        throw SidebarError.io("Unable to archive updated SFL dictionary: \(error)")
    }

    do { try archived.write(to: url, options: []) }
    catch {
        throw SidebarError.io("Unable to write SFL file at \(url.path): \(error)")
    }
}

func standardizedFileURL(from path: String) throws -> URL {
    let p = (path as NSString).standardizingPath
    if p.isEmpty { throw SidebarError.invalidPath("Invalid path: \(path)") }
    return URL(fileURLWithPath: p).absoluteURL
}

func itemsArrayMutable(from dict: NSMutableDictionary) throws -> NSMutableArray {
    guard let items = dict["items"] as? NSArray
    else { throw SidebarError.structure("Missing 'items' array in SFL structure") }
    return NSMutableArray(array: items)
}

func addItem(path: String, to dict: NSMutableDictionary) throws {
    let url = try standardizedFileURL(from: path)
    let absolute = url.absoluteString

    let itemsM = try itemsArrayMutable(from: dict)

    // Prevent duplicates by comparing resolved bookmark URLs
    for case let item as NSDictionary in itemsM {
        guard let bookmarkData = item["Bookmark"] as? Data else { continue }
        var stale = false
        if let bookmarkURL = try? URL(resolvingBookmarkData: bookmarkData,
                                      options: .withoutUI,
                                      relativeTo: nil,
                                      bookmarkDataIsStale: &stale),
           bookmarkURL.absoluteString == absolute {
            throw SidebarError.invalidPath("Item already exists: \(absolute)")
        }
    }

    let newItem = NSMutableDictionary()

    // Desktop special-case: avoid CustomItemProperties
    if !url.lastPathComponent.contains("Desktop") {
        let custom = NSMutableDictionary()
        custom["com.apple.LSSharedFileList.ItemIsHidden"] = NSNumber(value: 1)
        custom["com.apple.finder.dontshowonreappearance"] = NSNumber(value: 0)
        newItem["CustomItemProperties"] = custom
    }

    newItem["uuid"] = UUID().uuidString
    newItem["visibility"] = NSNumber(value: 0)

    guard let bookmark = try? url.bookmarkData(options: .suitableForBookmarkFile,
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil)
    else { throw SidebarError.bookmark("Unable to create bookmark for \(absolute)") }

    newItem["Bookmark"] = bookmark

    itemsM.add(newItem)
    dict["items"] = itemsM
}

func removeAll(from dict: NSMutableDictionary) {
    dict["items"] = NSMutableArray()
}

func listItems(from dict: NSMutableDictionary) throws {
    guard let items = dict["items"] as? NSArray
    else { throw SidebarError.structure("Missing 'items' array") }

    for case let item as NSDictionary in items {
        guard let bookmarkData = item["Bookmark"] as? Data else { continue }
        var stale = false
        if let bookmarkURL = try? URL(resolvingBookmarkData: bookmarkData,
                                      options: .withoutUI,
                                      relativeTo: nil,
                                      bookmarkDataIsStale: &stale) {
            print(bookmarkURL.absoluteString)
        }
    }
}

func reload(force: Bool) {
    let killShared = Process()
    killShared.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    killShared.arguments = ["sharedfilelistd"]

    var forceFinder = force
    do {
        try killShared.run()
        killShared.waitUntilExit()
    } catch {
        forceFinder = true
    }

    if forceFinder {
        let killFinder = Process()
        killFinder.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killFinder.arguments = ["Finder"]
        try? killFinder.run()
    }
}

func usage() {
    print("""
sidebarctl: manage Finder Favorites by editing FavoriteItems.sfl3/sfl4

  --list
  --add <path>...
  --removeAll
  --set <path>...        (replace Favorites with given list)
  --reload [--force]
  --path
""")
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let cmd = args.first else { usage(); exit(1) }

    let url = try favoritesFileURL()

    if cmd == "--path" {
        print(url.path)
        exit(0)
    }

    if cmd != "--reload" {
        try createEmptySFLIfMissing(url)
    }

    switch cmd {
    case "--list":
        let dict = try openSFL(url)
        try listItems(from: dict)

    case "--add":
        let paths = Array(args.dropFirst())
        if paths.isEmpty { usage(); exit(1) }
        let dict = try openSFL(url)
        var ok = false
        for p in paths {
            do { try addItem(path: p, to: dict); ok = true }
            catch { logerr("Add failed for \(p): \(error)") }
        }
        if !ok { exit(1) }
        try saveSFL(url, dict: dict)

    case "--removeAll":
        let dict = try openSFL(url)
        removeAll(from: dict)
        try saveSFL(url, dict: dict)

    case "--set":
        let paths = Array(args.dropFirst())
        if paths.isEmpty { usage(); exit(1) }
        let dict = try openSFL(url)
        removeAll(from: dict)
        for p in paths {
            try addItem(path: p, to: dict)
        }
        try saveSFL(url, dict: dict)

    case "--reload":
        let force = args.contains("--force")
        reload(force: force)

    default:
        usage()
        exit(1)
    }

} catch {
    logerr("Error: \(error)")
    exit(1)
}

