import AVFoundation
import AppKit
import Foundation

enum Permission {
    case microphone
    case accessibility
}

@MainActor
class PermissionsManager: ObservableObject {
    @Published var isMicrophonePermissionGranted = false
    @Published var isAccessibilityPermissionGranted = false

    private var permissionCheckTimer: Timer?

    init() {
        checkMicrophonePermission()
        checkAccessibilityPermission()

        // Monitor accessibility permission changes using NSWorkspace's notification center
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityPermissionChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        // Start continuous permission checking
        startPermissionChecking()
    }

    deinit {
        // Avoid isolated deinit (Swift 6 experimental). Perform minimal teardown.
        stopPermissionChecking()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func startPermissionChecking() {
        // Timer is scheduled on the main run loop
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkMicrophonePermission()
                self?.checkAccessibilityPermission()
            }
        }
    }

    nonisolated private func stopPermissionChecking() {
        Task { @MainActor [weak self] in
            self?.permissionCheckTimer?.invalidate()
            self?.permissionCheckTimer = nil
        }
    }

    func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            isMicrophonePermissionGranted = true
        default:
            isMicrophonePermissionGranted = false
        }
    }

    func checkAccessibilityPermission() {
        let granted = AXIsProcessTrusted()
        isAccessibilityPermissionGranted = granted
    }

    func requestMicrophonePermissionOrOpenSystemPreferences() {

        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isMicrophonePermissionGranted = granted
                }
            }
        case .authorized:
            self.isMicrophonePermissionGranted = true
        default:
            openSystemPreferences(for: .microphone)
        }
    }

    @objc private func accessibilityPermissionChanged() {
        checkAccessibilityPermission()
    }

    func openSystemPreferences(for permission: Permission) {
        let urlString: String
        switch permission {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            urlString =
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
