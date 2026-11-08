import CAdwaita
import Foundation

/// Mounts a network address (smb://, nfs://, sftp://, ftp://, dav://, …)
/// through GIO/GVfs — the same code GNOME Files uses — and returns the local
/// folder gvfs-fuse shows it at, so the file list can browse it like any
/// folder. The Linux side of the Mac's `NetworkShareService`.
///
/// Logins are answered through a `GMountOperation`: GVfs says which of user
/// name, domain and password it needs (`MountAuthPolicy`), and nothing secret
/// goes on a command line or into the environment.
@MainActor
final class NetworkMounter {
    struct Credentials: Equatable {
        var username: String
        var password: String
    }

    enum Failure: Error, Equatable, LocalizedError {
        case needsLogin
        case authentication
        case failed(String)
        case notBrowsable(String)

        var errorDescription: String? {
            switch self {
            case .needsLogin:
                return "This location needs a user name and password."
            case .authentication:
                return "The server didn\u{2019}t accept that user name and password."
            case .failed(let message):
                return message.isEmpty ? "Couldn\u{2019}t connect." : message
            case .notBrowsable(let address):
                return "Connected to \(address), but it isn\u{2019}t available as a folder. OneRoot browses network locations through gvfs-fuse; make sure gvfs-fuse is installed and running."
            }
        }
    }

    /// How long a mount may take before it is given up on.
    static let timeoutMilliseconds = 60_000

    /// Mounts `address` (already mounted counts as success) and returns the
    /// local folder it appears at.
    func mount(_ address: URL, credentials: Credentials?) async throws -> URL {
        let file = g_file_new_for_uri(address.absoluteString)!
        defer { g_object_unref(gpointer(file)) }
        if let path = Self.localPath(of: file) { return URL(fileURLWithPath: path, isDirectory: true) }

        let operation = g_mount_operation_new()!
        defer { g_object_unref(gpointer(operation)) }
        let cancellable = g_cancellable_new()!
        defer { g_object_unref(gpointer(cancellable)) }
        let state = MountState(credentials: credentials)
        let statePointer = Unmanaged.passRetained(state).toOpaque()
        defer { Unmanaged<MountState>.fromOpaque(statePointer).release() }

        let askPassword: @convention(c) (UnsafeMutablePointer<GMountOperation>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, GAskPasswordFlags, gpointer?) -> gboolean = { operation, _, _, _, flags, data in
            guard let operation, let data else { return 0 }
            let state = Unmanaged<MountState>.fromOpaque(data).takeUnretainedValue()
            state.askCount += 1
            trace("mount: ask-password flags=\(flags.rawValue) attempt=\(state.askCount)")
            switch MountAuthPolicy.answer(flags: flags.rawValue, credentials: state.credentials, attempt: state.askCount) {
            case .reply(let username, let domain, let password):
                g_mount_operation_set_username(operation, username)
                g_mount_operation_set_domain(operation, domain)
                g_mount_operation_set_password(operation, password)
                g_mount_operation_reply(operation, G_MOUNT_OPERATION_HANDLED)
            case .anonymous:
                g_mount_operation_set_anonymous(operation, 1)
                g_mount_operation_reply(operation, G_MOUNT_OPERATION_HANDLED)
            case .abort(let failure):
                state.refusal = failure
                g_mount_operation_reply(operation, G_MOUNT_OPERATION_ABORTED)
            }
            return 1
        }
        let signal = g_signal_connect_data(
            gpointer(operation), "ask-password",
            unsafeBitCast(askPassword, to: GCallback.self), statePointer, nil, GConnectFlags(rawValue: 0)
        )
        defer { g_signal_handler_disconnect(gpointer(operation), signal) }

        // A watchdog: GVfs can wait on a dead server for a long time.
        let timeout = g_timeout_add(guint(Self.timeoutMilliseconds), { data in
            if let data { g_cancellable_cancel(data.assumingMemoryBound(to: GCancellable.self)) }
            return 0
        }, gpointer(cancellable))
        defer { if g_main_context_find_source_by_id(nil, timeout) != nil { g_source_remove(timeout) } }

        trace("mount: starting \(address.absoluteString)")
        let outcome: MountOutcome = await withCheckedContinuation { continuation in
            let box = Unmanaged.passRetained(ContinuationBox(continuation))
            g_file_mount_enclosing_volume(file, GMountMountFlags(rawValue: 0), operation, cancellable, { _, result, data in
                guard let data else { return }
                let box = Unmanaged<ContinuationBox>.fromOpaque(data).takeRetainedValue()
                guard let result else { box.continuation.resume(returning: .failed("")); return }
                // The file is the source object; fetch it back from the result.
                let source = g_async_result_get_source_object(result)
                var error: UnsafeMutablePointer<GError>?
                _ = g_file_mount_enclosing_volume_finish(OpaquePointer(source), result, &error)
                if let source { g_object_unref(source) }
                guard let error else { box.continuation.resume(returning: .mounted); return }
                defer { g_error_free(error) }
                let message = String(cString: error.pointee.message)
                if g_error_matches(error, g_io_error_quark(), Int32(G_IO_ERROR_ALREADY_MOUNTED.rawValue)) != 0 {
                    box.continuation.resume(returning: .mounted)
                } else if g_error_matches(error, g_io_error_quark(), Int32(G_IO_ERROR_CANCELLED.rawValue)) != 0 {
                    box.continuation.resume(returning: .cancelled)
                } else if g_error_matches(error, g_io_error_quark(), Int32(G_IO_ERROR_FAILED_HANDLED.rawValue)) != 0 {
                    box.continuation.resume(returning: .refused)
                } else if g_error_matches(error, g_io_error_quark(), Int32(G_IO_ERROR_PERMISSION_DENIED.rawValue)) != 0
                            || g_error_matches(error, g_io_error_quark(), Int32(G_IO_ERROR_NOT_SUPPORTED.rawValue)) == 0 && message.localizedCaseInsensitiveContains("password") {
                    box.continuation.resume(returning: .accessDenied(message))
                } else {
                    box.continuation.resume(returning: .failed(message))
                }
            }, box.toOpaque())
        }

        trace("mount: finished \(outcome)")
        switch outcome {
        case .mounted: break
        case .cancelled: throw Failure.failed("The server didn\u{2019}t answer in \(Self.timeoutMilliseconds / 1000) seconds.")
        case .refused: throw state.refusal ?? Failure.authentication
        case .accessDenied(let message):
            throw credentials == nil ? Failure.needsLogin : (message.isEmpty ? Failure.authentication : Failure.failed(message))
        case .failed(let message): throw Failure.failed(message)
        }
        guard let path = Self.localPath(of: file) else { throw Failure.notBrowsable(address.absoluteString) }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Where gvfs-fuse shows the (mounted) location, or nil.
    private static func localPath(of file: OpaquePointer) -> String? {
        guard let raw = g_file_get_path(file) else { return nil }
        defer { g_free(raw) }
        let path = String(cString: raw)
        return path.isEmpty ? nil : path
    }

    private final class MountState {
        let credentials: Credentials?
        var askCount = 0
        var refusal: Failure?
        init(credentials: Credentials?) { self.credentials = credentials }
    }

    private final class ContinuationBox {
        let continuation: CheckedContinuation<MountOutcome, Never>
        init(_ continuation: CheckedContinuation<MountOutcome, Never>) { self.continuation = continuation }
    }

    private enum MountOutcome {
        case mounted, cancelled, refused
        case accessDenied(String)
        case failed(String)
    }
}

/// What to answer when GVfs asks for a login: pure, so it is tested without a
/// server. `flags` are GAskPasswordFlags' bits.
enum MountAuthPolicy {
    static let needPassword: UInt32 = 1 << 0
    static let needUsername: UInt32 = 1 << 1
    static let needDomain: UInt32 = 1 << 2
    static let anonymousSupported: UInt32 = 1 << 4

    enum Answer: Equatable {
        case reply(username: String, domain: String, password: String)
        case anonymous
        case abort(NetworkMounter.Failure)
    }

    /// `attempt` counts the asks for this mount: a second ask means the first
    /// answer was refused, so ask again with the same login would loop forever.
    static func answer(flags: UInt32, credentials: NetworkMounter.Credentials?, attempt: Int) -> Answer {
        guard let credentials else {
            // No login given: guest access where the protocol has it.
            return flags & anonymousSupported != 0 && attempt == 1 ? .anonymous : .abort(.needsLogin)
        }
        guard attempt == 1 else { return .abort(.authentication) }
        return .reply(username: credentials.username, domain: flags & needDomain != 0 ? "WORKGROUP" : "", password: credentials.password)
    }
}
