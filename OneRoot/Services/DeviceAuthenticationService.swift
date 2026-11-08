import Foundation
import LocalAuthentication

/// Gates a sensitive action behind Touch ID (falling back to the Mac
/// account password) via `LocalAuthentication` — used before "Copy via
/// SSH" runs, since a saved destination may carry a Keychain-stored
/// password or key passphrase. Whether this runs at all is controlled by
/// `SSHDeviceAuthenticationPreferenceService`.
struct DeviceAuthenticationService {
    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        // A Mac with neither biometrics nor a device password to fall
        // back to can't evaluate this policy at all (essentially never in
        // practice) — treat that as "nothing to gate behind" rather than
        // blocking the feature outright.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return true
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
