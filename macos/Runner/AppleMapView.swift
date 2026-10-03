import Cocoa
import FlutterMacOS
import MapKit

/// Apple Maps under the track map on the Mac (Dart side:
/// lib/day/apple_map.dart).
///
/// Flutter draws the trace, the cursor and every other overlay above this
/// view and owns the camera: the map takes no mouse or trackpad event of its
/// own, and Dart sends the part of the world to show on the
/// "com.flappedear.telemetry/apple_map/<view id>" channel ("setRegion": left,
/// top, width and height as fractions of the Web Mercator world, which MapKit
/// map points share).
final class AppleMapPlugin: NSObject {
  static let viewType = "com.flappedear.telemetry/apple_map"

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(AppleMapFactory(messenger: registrar.messenger), withId: viewType)
  }

  /// The map rectangle for a region sent from Dart, or nil when it is not one.
  static func mapRect(from arguments: Any?) -> MKMapRect? {
    guard let numbers = arguments as? [NSNumber], numbers.count == 4 else { return nil }
    let values = numbers.map { $0.doubleValue }
    guard values.allSatisfy({ $0.isFinite }), values[2] > 0, values[3] > 0 else { return nil }
    let world = MKMapRect.world.size.width
    return MKMapRect(
      x: values[0] * world, y: values[1] * world,
      width: values[2] * world, height: values[3] * world)
  }
}

final class AppleMapFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    let mapView = RegionMapView(frame: .zero)
    mapView.controller = AppleMapController(
      mapView: mapView,
      channel: FlutterMethodChannel(
        name: "\(AppleMapPlugin.viewType)/\(viewId)", binaryMessenger: messenger))
    mapView.show(AppleMapPlugin.mapRect(from: args))
    return mapView
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

/// Shows on [mapView] the regions Dart sends. The map view keeps it; it stops
/// listening when the map view goes away.
final class AppleMapController: NSObject {
  private let channel: FlutterMethodChannel

  init(mapView: RegionMapView, channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    channel.setMethodCallHandler { [weak mapView] call, result in
      switch call.method {
      case "setRegion":
        mapView?.show(AppleMapPlugin.mapRect(from: call.arguments))
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }
}

/// A map that shows exactly the rectangle it is given and nothing the user
/// does moves it.
final class RegionMapView: MKMapView {
  private var shown: MKMapRect?
  var controller: AppleMapController?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    mapType = .standard
    isZoomEnabled = false
    isScrollEnabled = false
    isRotateEnabled = false
    isPitchEnabled = false
    showsCompass = false
    showsScale = false
    showsZoomControls = false
    showsPitchControl = false
    showsUserLocation = false
    pointOfInterestFilter = .excludingAll
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  func show(_ rect: MKMapRect?) {
    guard let rect else { return }
    shown = rect
    apply()
  }

  private func apply() {
    guard let rect = shown, bounds.width > 0, bounds.height > 0 else { return }
    setVisibleMapRect(rect, animated: false)
  }

  // Mouse and trackpad events pass through to the Flutter view behind, which
  // pans and zooms the camera.
  override func hitTest(_ point: NSPoint) -> NSView? {
    return nil
  }

  // A region that came before the view had its size is shown once it has,
  // and a new size shows the same region.
  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    apply()
  }
}
