#!/usr/bin/env swift
import Foundation

enum SidebarError: Error, CustomStringConvertible {
    case io(String)
    case structure(String)
    
    var description: String {
        switch self {
        case .io(let s): return s
        case .structure(let s): return s
        }
    }
}

func logerr(_ s: String) {
    if let data = (s + "\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

func sharedFileListDir() throws -> URL {
    let fm = FileManager.default
    guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else { throw SidebarError.io("Unable to locate Application Support directory") }
    return appSupport.appendingPathComponent("com.apple.sharedfilelist", isDirectory: true)
}

func openSFL(_ url: URL) throws -> NSMutableDictionary {
    let data: Data
    do { data = try Data(contentsOf: url) }
    catch {
        throw SidebarError.io("Unable to read SFL file at \(url.path). Full Disk Access may be required.")
    }
    
    let allowed: [AnyClass] = [
        NSDictionary.self, NSMutableDictionary.self,
        NSArray.self, NSMutableArray.self,
        NSString.self, NSMutableString.self,
        NSData.self, NSMutableData.self,
        NSNumber.self, NSUUID.self, NSDate.self
    ]
    
    guard let unarchived = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: allowed, from: data) as? NSDictionary
    else { throw SidebarError.structure("Unable to unarchive SFL data") }
    
    return NSMutableDictionary(dictionary: unarchived)
}

func saveSFL(_ url: URL, dict: NSMutableDictionary) throws {
    let archived = try NSKeyedArchiver.archivedData(withRootObject: dict, requiringSecureCoding: false)
    try archived.write(to: url, options: [])
}

func reload() {
    let killShared = Process()
    killShared.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    killShared.arguments = ["sharedfilelistd"]
    try? killShared.run()
    killShared.waitUntilExit()
    
    // Also restart Finder to pick up changes
    let killFinder = Process()
    killFinder.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    killFinder.arguments = ["Finder"]
    try? killFinder.run()
    killFinder.waitUntilExit()
}

// ============ TopSidebarSection (Recents & Shared) ============

func topSidebarSectionURL() throws -> URL {
    let dir = try sharedFileListDir()
    return dir.appendingPathComponent("com.apple.LSSharedFileList.TopSidebarSection.sfl4", isDirectory: false)
}

func hideRecentsAndShared() throws {
    let url = try topSidebarSectionURL()
    let dict = try openSFL(url)
    
    guard let items = dict["items"] as? NSArray else {
        throw SidebarError.structure("No items array in TopSidebarSection")
    }
    
    let newItems = NSMutableArray()
    
    for item in items {
        guard let itemDict = item as? NSDictionary else { continue }
        
        // Check if this is Recents or Shared by examining the bookmark path
        var shouldHide = false
        if let bookmarkData = itemDict["Bookmark"] as? Data {
            var stale = false
            if let bookmarkURL = try? URL(resolvingBookmarkData: bookmarkData,
                                          options: .withoutUI,
                                          relativeTo: nil,
                                          bookmarkDataIsStale: &stale) {
                let path = bookmarkURL.path
                if path.contains("myDocuments.cannedSearch") || path.contains("SharedDocuments.cannedSearch") {
                    shouldHide = true
                }
            }
        }
        
        let newItem = NSMutableDictionary(dictionary: itemDict)
        
        if shouldHide {
            // Set visibility to 1 (hidden) and ensure ItemIsHidden is set
            newItem["visibility"] = NSNumber(value: 1)
            
            let customProps = NSMutableDictionary(dictionary: (itemDict["CustomItemProperties"] as? NSDictionary) ?? [:])
            customProps["com.apple.LSSharedFileList.ItemIsHidden"] = NSNumber(value: 1)
            newItem["CustomItemProperties"] = customProps
        }
        
        newItems.add(newItem)
    }
    
    dict["items"] = newItems
    try saveSFL(url, dict: dict)
    print("✓ Recents and Shared set to hidden in TopSidebarSection")
}

func showRecentsAndShared() throws {
    let url = try topSidebarSectionURL()
    let dict = try openSFL(url)
    
    guard let items = dict["items"] as? NSArray else {
        throw SidebarError.structure("No items array in TopSidebarSection")
    }
    
    let newItems = NSMutableArray()
    
    for item in items {
        guard let itemDict = item as? NSDictionary else { continue }
        
        let newItem = NSMutableDictionary(dictionary: itemDict)
        newItem["visibility"] = NSNumber(value: 0)
        
        let customProps = NSMutableDictionary(dictionary: (itemDict["CustomItemProperties"] as? NSDictionary) ?? [:])
        customProps["com.apple.LSSharedFileList.ItemIsHidden"] = NSNumber(value: 0)
        newItem["CustomItemProperties"] = customProps
        
        newItems.add(newItem)
    }
    
    dict["items"] = newItems
    try saveSFL(url, dict: dict)
    print("✓ Recents and Shared set to visible in TopSidebarSection")
}

func removeRecentsAndShared() throws {
    let url = try topSidebarSectionURL()
    let dict = try openSFL(url)
    
    // Simply clear all items - this removes Recents and Shared
    dict["items"] = NSMutableArray()
    try saveSFL(url, dict: dict)
    print("✓ Removed all items from TopSidebarSection (Recents & Shared removed)")
}

// ============ NetworkBrowser (Bonjour/Shared computers) ============

func networkBrowserURL() throws -> URL {
    let dir = try sharedFileListDir()
    return dir.appendingPathComponent("com.apple.LSSharedFileList.NetworkBrowser.sfl4", isDirectory: false)
}

func setBonjourEnabled(_ enabled: Bool) throws {
    let url = try networkBrowserURL()
    let dict = try openSFL(url)
    
    let props = NSMutableDictionary(dictionary: (dict["properties"] as? NSDictionary) ?? [:])
    props["com.apple.NetworkBrowser.bonjourEnabled"] = NSNumber(value: enabled ? 1 : 0)
    dict["properties"] = props
    
    try saveSFL(url, dict: dict)
    print("✓ Bonjour computers \(enabled ? "enabled" : "disabled") in NetworkBrowser")
}

func setConnectedServersEnabled(_ enabled: Bool) throws {
    let url = try networkBrowserURL()
    let dict = try openSFL(url)
    
    let props = NSMutableDictionary(dictionary: (dict["properties"] as? NSDictionary) ?? [:])
    props["com.apple.NetworkBrowser.connectedEnabled"] = NSNumber(value: enabled ? 1 : 0)
    dict["properties"] = props
    
    try saveSFL(url, dict: dict)
    print("✓ Connected servers \(enabled ? "enabled" : "disabled") in NetworkBrowser")
}

// ============ Main ============

func usage() {
    print("""
sidebarsections: Control Finder sidebar sections (Recents, Shared, Bonjour)

Usage:
  --hide-recents-shared     Hide Recents and Shared sections (sets visibility=1)
  --show-recents-shared     Show Recents and Shared sections (sets visibility=0)
  --remove-recents-shared   Remove Recents and Shared items entirely
  --disable-bonjour         Disable Bonjour computers in Shared section
  --enable-bonjour          Enable Bonjour computers in Shared section
  --disable-connected       Disable connected servers in Locations
  --enable-connected        Enable connected servers in Locations
  --reload                  Restart sharedfilelistd and Finder to apply changes
  --all-hidden              Hide everything (Recents, Shared, disable Bonjour)
""")
}

let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty {
    usage()
    exit(0)
}

var needsReload = false

do {
    for arg in args {
        switch arg {
        case "--hide-recents-shared":
            try hideRecentsAndShared()
            needsReload = true
        case "--show-recents-shared":
            try showRecentsAndShared()
            needsReload = true
        case "--remove-recents-shared":
            try removeRecentsAndShared()
            needsReload = true
        case "--disable-bonjour":
            try setBonjourEnabled(false)
            needsReload = true
        case "--enable-bonjour":
            try setBonjourEnabled(true)
            needsReload = true
        case "--disable-connected":
            try setConnectedServersEnabled(false)
            needsReload = true
        case "--enable-connected":
            try setConnectedServersEnabled(true)
            needsReload = true
        case "--reload":
            reload()
            print("✓ Reloaded sharedfilelistd and Finder")
        case "--all-hidden":
            try removeRecentsAndShared()
            try setBonjourEnabled(false)
            needsReload = true
        default:
            logerr("Unknown option: \(arg)")
            usage()
            exit(1)
        }
    }
    
    if needsReload && !args.contains("--reload") {
        print("\nRun with --reload to apply changes, or restart Finder manually.")
    }
} catch {
    logerr("Error: \(error)")
    exit(1)
}
