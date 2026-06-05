import UIKit
import Flutter
import CallKit

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate, CXCallObserverDelegate {
    private var callObserver: CXCallObserver!
    private var channel: FlutterMethodChannel!
    private var callStartTime: Date?
    private var callConnectedTime: Date?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        // Setup MethodChannel after rootViewController is ready
        if let controller = window?.rootViewController as? FlutterViewController {
            channel = FlutterMethodChannel(name: "com.your.app/call_tracker",
                                           binaryMessenger: controller.binaryMessenger)

            channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
                if call.method == "initCallTracker" {
                    self?.initCallTracker()
                    result(nil)
                } else {
                    result(FlutterMethodNotImplemented)
                }
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func initCallTracker() {
        callObserver = CXCallObserver()
        callObserver.setDelegate(self, queue: nil)
    }

    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        if call.hasConnected && callConnectedTime == nil {
            callConnectedTime = Date()
            channel?.invokeMethod("onCallConnected", arguments: nil)
        }

        if call.hasEnded {
            var duration = 0
            if let connected = callConnectedTime {
                duration = Int(Date().timeIntervalSince(connected))
            }

            let args: [String: Any] = [
                "duration": duration,
                "wasConnected": callConnectedTime != nil
            ]
            channel?.invokeMethod("onCallEnded", arguments: args)

            callStartTime = nil
            callConnectedTime = nil
        }

        if !call.isOutgoing && !call.hasConnected && callStartTime == nil {
            // Incoming call is ringing
            callStartTime = Date()
            channel?.invokeMethod("onCallStarted", arguments: nil)
        }
    }
}
