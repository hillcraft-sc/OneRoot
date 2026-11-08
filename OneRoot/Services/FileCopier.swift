#if os(macOS) // macOS only; the Linux side is LinuxPlatform.swift (#79)
import Foundation

/// Recursive copy via `copyfile(3)`, for what `FileManager.copyItem`
/// doesn't offer: byte-level progress within a file, and stopping
/// mid-file. Same result otherwise — clones on APFS (instant, no extra
/// space), copies symlinks as links, keeps metadata/xattrs/ACLs — except
/// macOS's "everyone deny delete" entry (see
/// `removeEveryoneDenyDelete`). The C callback plumbing stays contained
/// here.
enum FileCopier {
    /// Copies `source` to `destination`, which must not exist yet.
    /// `onProgress` gets the bytes copied of this item so far (called from
    /// the copying thread, often — callers throttle). If the copy fails or
    /// `cancellation` fires, the partial copy is removed and this throws
    /// (`CancellationError` for a cancel).
    /// `includeMetadata` false copies only contents, permissions, owner,
    /// and dates — no extended attributes (Finder tags, quarantine,
    /// "Where from") or access-control lists. For destinations that can't
    /// store those natively, where macOS would otherwise write a hidden
    /// "._name" file beside every item and lock it for each attribute —
    /// on an NFS share, most of the copy's time (see
    /// `storesMetadataNatively`).
    static func copy(
        _ source: URL,
        to destination: URL,
        includeMetadata: Bool = true,
        cancellation: CancellationFlag,
        onProgress: @escaping (Int64) -> Void
    ) throws {
        guard (try? FileManager.default.attributesOfItem(atPath: destination.path)) == nil else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EEXIST))
        }

        let tracker = Tracker(cancellation: cancellation, onProgress: onProgress)
        guard let state = copyfile_state_alloc() else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOMEM))
        }
        defer { copyfile_state_free(state) }
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(tracker).toOpaque())

        // A clone carries every attribute along, so it's only for full copies.
        let contents = includeMetadata ? (COPYFILE_ALL | COPYFILE_CLONE) : (COPYFILE_DATA | COPYFILE_STAT)
        let flags = copyfile_flags_t(contents | COPYFILE_RECURSIVE)
        let result = withExtendedLifetime(tracker) {
            copyfile(source.path, destination.path, state, flags)
        }
        let failureCode = result == 0 ? nil : (tracker.errorCode ?? errno)

        if tracker.wasCancelled || failureCode != nil {
            // Ours to discard: it didn't exist before (checked above).
            try? FileManager.default.removeItem(at: destination)
        }
        if tracker.wasCancelled {
            throw CancellationError()
        }
        if let failureCode {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(failureCode))
        }
        // Each folder inside is handled as it's finished (see `callback`);
        // this covers the item itself.
        removeEveryoneDenyDelete(atPath: destination.path)
    }

    /// Whether the volume `url` is on stores extended attributes itself
    /// (APFS, HFS+, SMB shares). `false` when it says it doesn't, or
    /// doesn't say (NFS) — macOS then fakes them with "._" files.
    static func storesMetadataNatively(_ url: URL) -> Bool {
        struct Reply {
            var length: UInt32 = 0
            var capabilities = vol_capabilities_attr_t()
        }
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe.deleteLastPathComponent()
        }
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_CAPABILITIES)
        var reply = Reply()
        guard getattrlist(probe.path, &request, &reply, MemoryLayout<Reply>.size, 0) == 0 else { return true }
        let interfaces = Int(VOL_CAPABILITIES_INTERFACES)
        let valid = withUnsafeBytes(of: reply.capabilities.valid) { $0.load(fromByteOffset: interfaces * 4, as: UInt32.self) }
        let supported = withUnsafeBytes(of: reply.capabilities.capabilities) { $0.load(fromByteOffset: interfaces * 4, as: UInt32.self) }
        let bit = UInt32(VOL_CAP_INT_EXTENDED_ATTR)
        return valid & bit != 0 && supported & bit != 0
    }

    /// macOS marks Desktop, Documents, Downloads and the other folders in
    /// your home folder "everyone: deny delete" so they can't be thrown
    /// away. Copying that along made the *copy* impossible to trash too,
    /// so it's left off — only that entry; any other access rules are kept.
    static func removeEveryoneDenyDelete(atPath path: String) {
        guard let acl = acl_get_link_np(path, ACL_TYPE_EXTENDED) else { return }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        // The "everyone" group's fixed UUID (gid 12).
        guard var everyone = UUID(uuidString: "ABCDEFAB-CDEF-ABCD-EFAB-CDEF0000000C")?.uuid else { return }

        var changed = false
        var emptied: [acl_entry_t] = []
        var entry: acl_entry_t?
        var entryID = ACL_FIRST_ENTRY.rawValue
        while acl_get_entry(acl, entryID, &entry) == 0, let current = entry {
            entryID = ACL_NEXT_ENTRY.rawValue
            var tag = ACL_UNDEFINED_TAG
            var permset: acl_permset_t?
            guard acl_get_tag_type(current, &tag) == 0, tag == ACL_EXTENDED_DENY,
                  acl_get_permset(current, &permset) == 0, let permset,
                  acl_get_perm_np(permset, ACL_DELETE) == 1,
                  let qualifier = acl_get_qualifier(current) else { continue }
            let isEveryone = withUnsafeBytes(of: &everyone) { memcmp($0.baseAddress, qualifier, 16) == 0 }
            acl_free(qualifier)
            guard isEveryone else { continue }
            acl_delete_perm(permset, ACL_DELETE)
            acl_set_permset(current, permset)
            changed = true
            if !allPermissions.contains(where: { acl_get_perm_np(permset, $0) == 1 }) {
                emptied.append(current)
            }
        }
        guard changed else { return }
        for entry in emptied { acl_delete_entry(acl, entry) }
        acl_set_link_np(path, ACL_TYPE_EXTENDED, acl)
    }

    private static let allPermissions: [acl_perm_t] = [
        ACL_READ_DATA, ACL_WRITE_DATA, ACL_EXECUTE, ACL_DELETE, ACL_APPEND_DATA,
        ACL_DELETE_CHILD, ACL_READ_ATTRIBUTES, ACL_WRITE_ATTRIBUTES,
        ACL_READ_EXTATTRIBUTES, ACL_WRITE_EXTATTRIBUTES, ACL_READ_SECURITY,
        ACL_WRITE_SECURITY, ACL_CHANGE_OWNER, ACL_SYNCHRONIZE,
    ]

    /// Context handed to the C callback. Bytes of files already finished
    /// plus bytes of the current one so far.
    private final class Tracker {
        let cancellation: CancellationFlag
        let onProgress: (Int64) -> Void
        var finishedBytes: Int64 = 0
        var errorCode: Int32?
        var wasCancelled = false

        init(cancellation: CancellationFlag, onProgress: @escaping (Int64) -> Void) {
            self.cancellation = cancellation
            self.onProgress = onProgress
        }

        /// `COPYFILE_QUIT` once cancelled, so the copy stops at the next
        /// callback — between blocks of a big file, not just between files.
        func continueOrQuit() -> Int32 {
            cancellation.waitWhilePaused()
            guard cancellation.isCancelled else { return COPYFILE_CONTINUE }
            wasCancelled = true
            return COPYFILE_QUIT
        }
    }

    private static let callback: copyfile_callback_t = { what, stage, state, sourcePath, destinationPath, context in
        guard let context else { return COPYFILE_CONTINUE }
        let tracker = Unmanaged<Tracker>.fromOpaque(context).takeUnretainedValue()

        switch (what, stage) {
        case (COPYFILE_COPY_DATA, COPYFILE_PROGRESS):
            var copied: off_t = 0
            copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
            tracker.onProgress(tracker.finishedBytes + Int64(copied))
            return tracker.continueOrQuit()

        case (COPYFILE_RECURSE_FILE, COPYFILE_FINISH):
            // Counted from the source's size rather than bytes copied: a
            // clone copies none, but it's still that much done.
            var info = stat()
            if let sourcePath, lstat(sourcePath, &info) == 0 {
                tracker.finishedBytes += Int64(info.st_size)
            }
            tracker.onProgress(tracker.finishedBytes)
            return tracker.continueOrQuit()

        case (COPYFILE_RECURSE_DIR_CLEANUP, COPYFILE_FINISH):
            // A folder's ACL is applied once its contents are done.
            if let destinationPath { removeEveryoneDenyDelete(atPath: String(cString: destinationPath)) }
            return tracker.continueOrQuit()

        case (_, COPYFILE_ERR), (COPYFILE_RECURSE_ERROR, _):
            // Stop at the first failure, like `FileManager.copyItem` —
            // half a folder silently copied would be worse.
            tracker.errorCode = errno
            return COPYFILE_QUIT

        default:
            return tracker.continueOrQuit()
        }
    }
}
#endif
