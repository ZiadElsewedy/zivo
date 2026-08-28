import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Strong reference so the audio-route channel/observer outlives this method.
  private var audioRoute: AudioRoute?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Wire the OS audio-route channel (see AudioRouteChannel on the Dart side).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ZivoAudioRoute") {
      audioRoute = AudioRoute(messenger: registrar.messenger())
    }
  }
}

/// Reports the current OS audio output route (AirPods / headphones / speaker)
/// to Flutter over `zivo/audio_route` (one-shot `current`) and
/// `zivo/audio_route/events` (live changes). Reads `AVAudioSession`'s current
/// route, which reflects the system hardware output regardless of which app is
/// producing audio — good enough while Spotify plays in its own process.
///
/// iOS exposes no public accessory-battery API, so `battery` is always omitted.
final class AudioRoute: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    let method = FlutterMethodChannel(name: "zivo/audio_route", binaryMessenger: messenger)
    method.setMethodCallHandler { [weak self] call, result in
      if call.method == "current" {
        result(self?.currentRoute())
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    let events = FlutterEventChannel(name: "zivo/audio_route/events", binaryMessenger: messenger)
    events.setStreamHandler(self)
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = events
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(routeChanged),
      name: AVAudioSession.routeChangeNotification,
      object: nil
    )
    // Emit the current route immediately so the stream has a value on listen.
    events(currentRoute())
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    NotificationCenter.default.removeObserver(
      self,
      name: AVAudioSession.routeChangeNotification,
      object: nil
    )
    sink = nil
    return nil
  }

  @objc private func routeChanged(_ notification: Notification) {
    sink?(currentRoute())
  }

  private func currentRoute() -> [String: Any]? {
    let session = AVAudioSession.sharedInstance()
    guard let output = session.currentRoute.outputs.first else { return nil }
    return [
      "name": output.portName,
      "kind": kind(for: output.portType),
    ]
  }

  private func kind(for port: AVAudioSession.Port) -> String {
    switch port {
    case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
      return "bluetooth"
    case .headphones, .headsetMic:
      return "headphones"
    case .builtInSpeaker, .builtInReceiver:
      return "phone"
    case .airPlay, .HDMI, .usbAudio, .carAudio, .lineOut:
      return "speaker"
    default:
      return "unknown"
    }
  }
}
