import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let fileAccess = FileAccess()
  private let appUpdate = AppUpdate()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    fileAccess.register(with: flutterViewController.engine.binaryMessenger)
    appUpdate.register(with: flutterViewController.engine.binaryMessenger)
    AppleMapPlugin.register(with: flutterViewController.registrar(forPlugin: "AppleMapPlugin"))

    super.awakeFromNib()
  }
}

/// Shows an update the app downloaded (lib/update/app_updater.dart) in
/// Finder. The user chose where to save it, so the sandbox lets the app
/// point at it.
final class AppUpdate {
  static let channelName = "com.flappedear.telemetry/app_update"

  private var channel: FlutterMethodChannel?

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "reveal":
        guard let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String,
          FileManager.default.fileExists(atPath: path)
        else {
          result(false)
          return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }
}

/// Keeps the app allowed to read the recordings and folders the user chose,
/// across launches (Dart side: lib/import/file_access.dart).
///
/// The sandbox lets the app read a file picked in an open panel or dropped on
/// the window only until the app quits. A security-scoped bookmark, made
/// while that access lasts, gives it back on a later launch, so a saved day
/// can read its recordings again where they are.
final class FileAccess {
  static let channelName = "com.flappedear.telemetry/file_access"

  /// Bookmarks kept in the app's own preferences, oldest use first.
  private static let defaultsKey = "recordingBookmarks"

  /// The most bookmarks kept; the least recently chosen are dropped first.
  /// A folder's bookmark covers every recording in it.
  static let maximumBookmarks = 500

  private var channel: FlutterMethodChannel?

  /// The bookmarks being accessed now, by the path they were made for. They
  /// stay open while the app runs.
  private var accessing: [String: URL] = [:]

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "remember":
        result(self.remember(call.arguments as? [String] ?? []))
      case "restore":
        result(self.restore())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  private struct Entry {
    var path: String
    var bookmark: Data
  }

  private func load() -> [Entry] {
    let stored = UserDefaults.standard.array(forKey: Self.defaultsKey) ?? []
    return stored.compactMap { value in
      guard let entry = value as? [String: Any],
        let path = entry["path"] as? String,
        let bookmark = entry["bookmark"] as? Data
      else { return nil }
      return Entry(path: path, bookmark: bookmark)
    }
  }

  private func save(_ entries: [Entry]) {
    let kept = entries.suffix(Self.maximumBookmarks)
    UserDefaults.standard.set(
      kept.map { ["path": $0.path, "bookmark": $0.bookmark] as [String: Any] },
      forKey: Self.defaultsKey)
  }

  private static func bookmark(_ url: URL) -> Data? {
    try? url.bookmarkData(
      options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
      includingResourceValuesForKeys: nil, relativeTo: nil)
  }

  /// Bookmarks each of [paths] the app may read now; returns how many.
  private func remember(_ paths: [String]) -> Int {
    var entries = load()
    var made = 0
    for path in paths {
      guard let bookmark = Self.bookmark(URL(fileURLWithPath: path)) else { continue }
      entries.removeAll { $0.path == path }
      entries.append(Entry(path: path, bookmark: bookmark))
      made += 1
    }
    if made > 0 { save(entries) }
    return made
  }

  /// Starts accessing every remembered file and folder that still exists;
  /// returns how many are accessible. Bookmarks that no longer resolve are
  /// dropped, and stale ones made again.
  private func restore() -> Int {
    var entries = load()
    var changed = false
    var index = 0
    while index < entries.count {
      let entry = entries[index]
      if accessing[entry.path] != nil {
        index += 1
        continue
      }
      var stale = false
      guard
        let url = try? URL(
          resolvingBookmarkData: entry.bookmark, options: [.withSecurityScope],
          relativeTo: nil, bookmarkDataIsStale: &stale)
      else {
        entries.remove(at: index)
        changed = true
        continue
      }
      if url.startAccessingSecurityScopedResource() {
        accessing[entry.path] = url
        if stale, let renewed = Self.bookmark(url) {
          entries[index].bookmark = renewed
          changed = true
        }
      }
      index += 1
    }
    if changed { save(entries) }
    return accessing.count
  }
}
