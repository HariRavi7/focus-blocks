import Cocoa
import FlutterMacOS

// Installed by tool/setup_platforms.dart. Edit this copy in platform/macos/.
class MainFlutterWindow: NSWindow {
  private var menuBar: MenuBarController?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 420, height: 640)
    self.title = "Focus Blocks"
    // Closing the window only hides it; the app keeps running in the menu bar.
    self.isReleasedWhenClosed = false

    RegisterGeneratedPlugins(registry: flutterViewController)
    menuBar = MenuBarController(messenger: flutterViewController.engine.binaryMessenger, window: self)

    super.awakeFromNib()
  }
}

/// The menu bar item: an icon with the current block and minutes left, and a
/// menu built by the Dart side (lib/platform/menu_bar.dart).
final class MenuBarController: NSObject {
  private let statusItem: NSStatusItem
  private let channel: FlutterMethodChannel
  private weak var window: NSWindow?
  private var lastItems: NSArray?

  init(messenger: FlutterBinaryMessenger, window: NSWindow) {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    channel = FlutterMethodChannel(name: "focus_blocks/menu_bar", binaryMessenger: messenger)
    self.window = window
    super.init()

    if let button = statusItem.button {
      if #available(macOS 11.0, *) {
        button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Focus Blocks")
        button.imagePosition = .imageLeading
      } else {
        button.title = "Focus"
      }
    }
    statusItem.menu = buildMenu([
      ["id": "open", "label": "Open Focus Blocks"],
      ["separator": true],
      ["id": "quit", "label": "Quit Focus Blocks"],
    ])

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      if call.method == "update", let args = call.arguments as? [String: Any] {
        self.update(args)
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func update(_ args: [String: Any]) {
    let title = args["title"] as? String ?? ""
    if let button = statusItem.button {
      if #available(macOS 11.0, *) {
        button.title = title.isEmpty ? "" : " " + title
        // Fixed-width digits so the countdown doesn't jiggle.
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
      } else {
        button.title = title.isEmpty ? "Focus" : title
      }
    }
    // The title ticks every second during a Pomodoro; only rebuild the menu
    // when its items change, so an open menu isn't swapped out.
    let items = args["items"] as? [[String: Any]] ?? []
    let itemsArray = items as NSArray
    if let last = lastItems, last.isEqual(itemsArray) { return }
    lastItems = itemsArray
    statusItem.menu = buildMenu(items)
  }

  private func buildMenu(_ items: [[String: Any]]) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    for spec in items {
      if spec["separator"] as? Bool == true {
        menu.addItem(NSMenuItem.separator())
        continue
      }
      let id = spec["id"] as? String
      let item = NSMenuItem(
        title: spec["label"] as? String ?? "",
        action: #selector(itemClicked(_:)),
        keyEquivalent: id == "quit" ? "q" : ""
      )
      item.target = self
      item.representedObject = id
      item.isEnabled = id != nil && (spec["enabled"] as? Bool ?? true)
      menu.addItem(item)
    }
    return menu
  }

  @objc private func itemClicked(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    switch id {
    case "quit":
      NSApp.terminate(nil)
    case "open":
      showWindow()
    default:
      if id == "wrap" {
        showWindow()
      }
      channel.invokeMethod("action", arguments: id)
    }
  }

  private func showWindow() {
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
}
