import Flutter
import MapKit
import UIKit

/// Apple Maps under the track map on iPhone and iPad (Dart side:
/// lib/day/apple_map.dart).
///
/// Flutter draws the trace, the cursor and every other overlay above this
/// view and owns the camera: the map takes no gesture of its own, and Dart
/// sends the part of the world to show on the
/// "com.flappedear.telemetry/apple_map/<view id>" channel ("setRegion": left,
/// top, width and height as fractions of the Web Mercator world, which MapKit
/// map points share).
final class AppleMapPlugin: NSObject {
  static let viewType = "com.flappedear.telemetry/apple_map"

  /// Opens Apple's legal notice for the map ("openLegal" with its https
  /// URL), which the map's own link cannot: the map takes no touch or click.
  private static var legalChannel: FlutterMethodChannel?

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(AppleMapFactory(messenger: registrar.messenger()), withId: viewType)
    let channel = FlutterMethodChannel(name: viewType, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "openLegal" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let text = call.arguments as? String, let url = URL(string: text),
        url.scheme == "https"
      else {
        result(false)
        return
      }
      UIApplication.shared.open(url)
      result(true)
    }
    legalChannel = channel
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

  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
  ) -> FlutterPlatformView {
    return AppleMapPlatformView(
      frame: frame, viewId: viewId, arguments: args, messenger: messenger)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

final class AppleMapPlatformView: NSObject, FlutterPlatformView {
  private let mapView: RegionMapView
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, arguments: Any?, messenger: FlutterBinaryMessenger) {
    mapView = RegionMapView(frame: frame)
    channel = FlutterMethodChannel(
      name: "\(AppleMapPlugin.viewType)/\(viewId)", binaryMessenger: messenger)
    super.init()
    mapView.show(AppleMapPlugin.mapRect(from: arguments))
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setRegion":
        self?.mapView.show(AppleMapPlugin.mapRect(from: call.arguments))
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView {
    return mapView
  }
}

/// A map that shows exactly the rectangle it is given and nothing the user
/// does moves it.
final class RegionMapView: MKMapView {
  private var shown: MKMapRect?
  private var loggedMismatch = false
  private var laidOutSize = CGSize.zero

  override init(frame: CGRect) {
    super.init(frame: frame)
    mapType = .standard
    isZoomEnabled = false
    isScrollEnabled = false
    isRotateEnabled = false
    isPitchEnabled = false
    showsCompass = false
    showsScale = false
    showsUserLocation = false
    pointOfInterestFilter = .excludingAll
    // Touches go to Flutter, which moves the camera.
    isUserInteractionEnabled = false
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
    // Dart keeps the camera within MapKit's limits (see apple_map.dart); if
    // MapKit still shows another region, the trace drawn over it is off.
    // Logged once, for diagnosis only.
    let shownRect = visibleMapRect
    let tolerance = rect.size.width * 0.01
    if !loggedMismatch
      && (abs(shownRect.size.width - rect.size.width) > tolerance
        || abs(shownRect.midX - rect.midX) > tolerance
        || abs(shownRect.midY - rect.midY) > tolerance)
    {
      loggedMismatch = true
      NSLog(
        "AppleMapView: MapKit shows %@ instead of the requested %@; the overlay may be off.",
        "\(shownRect)", "\(rect)")
    }
  }

  // A region that came before the view had its size is shown once it has.
  override func layoutSubviews() {
    super.layoutSubviews()
    if bounds.size != laidOutSize {
      laidOutSize = bounds.size
      apply()
    }
  }
}
