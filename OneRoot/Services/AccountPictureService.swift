import Foundation
import OpenDirectory

/// Reads the current macOS user account's photo — the same image Finder
/// itself shows for the Home entry in its own sidebar. Returns raw image
/// data rather than `NSImage`: this stays Foundation-only per CLAUDE.md
/// §1, and image construction happens at the view layer, matching how
/// icons are already built elsewhere (`FolderOutlineView`,
/// `FileTableController`).
struct AccountPictureService {
    func currentUserImageData() -> Data? {
        let session = ODSession.default()
        guard
            let node = try? ODNode(session: session, type: ODNodeType(kODNodeTypeAuthentication)),
            let record = try? node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil),
            let values = try? record.values(forAttribute: kODAttributeTypeJPEGPhoto) as? [Data]
        else { return nil }
        return values.first
    }
}
