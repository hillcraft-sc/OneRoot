import XCTest
@testable import OneRoot
@testable import OneRootLinux

final class NetworkMounterTests: XCTestCase {
    private let ann = NetworkMounter.Credentials(username: "ann", password: "s3cret")

    func testAnswersWithTheLogin() {
        let flags = MountAuthPolicy.needUsername | MountAuthPolicy.needPassword | MountAuthPolicy.needDomain
        XCTAssertEqual(MountAuthPolicy.answer(flags: flags, credentials: ann, attempt: 1),
                       .reply(username: "ann", domain: "WORKGROUP", password: "s3cret"))
        XCTAssertEqual(MountAuthPolicy.answer(flags: MountAuthPolicy.needPassword, credentials: ann, attempt: 1),
                       .reply(username: "ann", domain: "", password: "s3cret"))
    }

    func testSecondAskMeansTheLoginWasRefused() {
        XCTAssertEqual(MountAuthPolicy.answer(flags: MountAuthPolicy.needPassword, credentials: ann, attempt: 2),
                       .abort(.authentication))
    }

    func testNoLoginTriesGuestOnceThenAsksForOne() {
        let flags = MountAuthPolicy.needPassword | MountAuthPolicy.anonymousSupported
        XCTAssertEqual(MountAuthPolicy.answer(flags: flags, credentials: nil, attempt: 1), .anonymous)
        XCTAssertEqual(MountAuthPolicy.answer(flags: flags, credentials: nil, attempt: 2), .abort(.needsLogin))
        XCTAssertEqual(MountAuthPolicy.answer(flags: MountAuthPolicy.needPassword, credentials: nil, attempt: 1), .abort(.needsLogin))
    }

    func testFailureMessages() {
        XCTAssertNotNil(NetworkMounter.Failure.needsLogin.errorDescription)
        XCTAssertTrue(NetworkMounter.Failure.notBrowsable("smb://nas/docs").errorDescription?.contains("smb://nas/docs") == true)
        XCTAssertEqual(NetworkMounter.Failure.failed("Connection refused").errorDescription, "Connection refused")
        XCTAssertEqual(NetworkMounter.Failure.failed("").errorDescription, "Couldn\u{2019}t connect.")
    }
}
