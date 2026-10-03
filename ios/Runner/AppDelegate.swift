import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IncomingRecordingsPlugin") {
      IncomingRecordingsPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppleMapPlugin") {
      AppleMapPlugin.register(with: registrar)
    }
  }
}

/// Receives VBO and RCZ recordings that another app, such as RaceChrono, sends
/// to this one from the share sheet. Info.plist declares the two file types,
/// and iOS copies each shared file into Documents/Inbox before handing over its
/// URL (LSSupportsOpeningDocumentsInPlace is false).
///
/// Paths go to Dart on the "com.flappedear.telemetry/incoming_recordings"
/// channel. Until Dart calls "ready", for example when the share started the
/// app, they are held here.
final class IncomingRecordingsPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private static let channelName = "com.flappedear.telemetry/incoming_recordings"
  private static let extensions: Set<String> = ["vbo", "rcz"]

  private let channel: FlutterMethodChannel
  private var pending: [String] = []
  private var ready = false

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = IncomingRecordingsPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addSceneDelegate(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ready":
      ready = true
      result(pending)
      pending = []
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // The share started the app.
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let contexts = connectionOptions?.urlContexts else { return false }
    return receive(contexts)
  }

  // The share reached the running app.
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    return receive(URLContexts)
  }

  private func receive(_ contexts: Set<UIOpenURLContext>) -> Bool {
    let paths = contexts.map(\.url)
      .filter { $0.isFileURL && Self.extensions.contains($0.pathExtension.lowercased()) }
      .map(\.path)
      .sorted()
    guard !paths.isEmpty else { return false }
    if ready {
      channel.invokeMethod("received", arguments: paths)
    } else {
      pending.append(contentsOf: paths)
    }
    return true
  }
}
