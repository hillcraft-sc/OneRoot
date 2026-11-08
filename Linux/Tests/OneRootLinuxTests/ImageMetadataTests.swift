import XCTest
@testable import OneRootLinux

final class ImageMetadataTests: XCTestCase {
    /// A big-endian TIFF block: IFD0 with Orientation, Make (EXIF-ish) and a
    /// GPS pointer to an IFD with one entry.
    private func tiff(orientation: Int, withGPS: Bool, withMake: Bool) -> [UInt8] {
        func s(_ v: Int) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
        func l(_ v: Int) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
        var entries: [[UInt8]] = [s(0x0112) + s(3) + l(1) + s(orientation) + [0, 0]]
        if withMake { entries.append(s(0x010F) + s(2) + l(2) + [0x58, 0, 0, 0]) }
        let ifd0Size = 2 + entries.count * 12 + 4 + (withGPS ? 12 : 0)
        let gpsOffset = 8 + ifd0Size
        if withGPS { entries.append(s(0x8825) + s(4) + l(1) + l(gpsOffset)) }
        var bytes: [UInt8] = [0x4D, 0x4D, 0x00, 0x2A] + l(8)
        bytes += s(entries.count) + entries.flatMap { $0 } + l(0)
        if withGPS { bytes += s(1) + (s(0x0001) + s(2) + l(2) + [0x4E, 0, 0, 0]) + l(0) }
        return bytes
    }

    private func jpeg(exif: [UInt8]?, extra: [UInt8] = []) -> Data {
        var bytes: [UInt8] = [0xFF, 0xD8]
        // JFIF APP0.
        bytes += [0xFF, 0xE0, 0x00, 0x10] + Array("JFIF\0".utf8) + [1, 1, 0, 0, 1, 0, 1, 0, 0]
        if let exif {
            let body = Array("Exif\0\0".utf8) + exif
            bytes += [0xFF, 0xE1, UInt8((body.count + 2) >> 8), UInt8((body.count + 2) & 0xFF)] + body
        }
        bytes += extra
        // Scan start and fake image data, then EOI.
        bytes += [0xFF, 0xDA, 0x00, 0x02, 0x11, 0x22, 0x33, 0xFF, 0xD9]
        return Data(bytes)
    }

    func testFindsLocationExifAndOrientation() {
        let data = jpeg(exif: tiff(orientation: 6, withGPS: true, withMake: true))
        let report = ImageMetadata.inspect(data)
        XCTAssertEqual(report.kinds, ["Location", "EXIF"])
        XCTAssertEqual(report.orientation, 6)
    }

    func testOrientationAloneIsNotPersonalMetadata() {
        let report = ImageMetadata.inspect(jpeg(exif: tiff(orientation: 3, withGPS: false, withMake: false)))
        XCTAssertEqual(report.kinds, [])
        XCTAssertEqual(report.orientation, 3)
    }

    func testFindsXMPAndIPTC() {
        let xmp = Array("http://ns.adobe.com/xap/1.0/\0<x/>".utf8)
        let iptc = Array("Photoshop 3.0\0".utf8) + [1, 2, 3]
        func segment(_ marker: UInt8, _ body: [UInt8]) -> [UInt8] { [0xFF, marker, UInt8((body.count + 2) >> 8), UInt8((body.count + 2) & 0xFF)] + body }
        let report = ImageMetadata.inspect(jpeg(exif: nil, extra: segment(0xE1, xmp) + segment(0xED, iptc)))
        XCTAssertEqual(report.kinds, ["IPTC", "XMP"])
    }

    func testStrippingRemovesEverythingButKeepsOrientationAndImageData() throws {
        let data = jpeg(exif: tiff(orientation: 6, withGPS: true, withMake: true), extra: [0xFF, 0xFE, 0x00, 0x05, 0x61, 0x62, 0x63])
        let stripped = try XCTUnwrap(ImageMetadata.strippedJPEG(data, orientation: 6))
        let report = ImageMetadata.inspect(stripped)
        XCTAssertEqual(report.kinds, [])
        XCTAssertEqual(report.orientation, 6)
        // The comment is gone and the scan data is untouched.
        XCTAssertNil(stripped.range(of: Data([0x61, 0x62, 0x63])))
        XCTAssertTrue(stripped.suffix(9) == Data([0xFF, 0xDA, 0x00, 0x02, 0x11, 0x22, 0x33, 0xFF, 0xD9]))
        XCTAssertTrue(stripped.starts(with: [0xFF, 0xD8, 0xFF, 0xE0]))
    }

    func testStrippingAnUprightPhotoLeavesNoExifAtAll() throws {
        let data = jpeg(exif: tiff(orientation: 1, withGPS: true, withMake: false))
        let stripped = try XCTUnwrap(ImageMetadata.strippedJPEG(data, orientation: 1))
        XCTAssertNil(stripped.range(of: Data("Exif".utf8)))
        XCTAssertEqual(ImageMetadata.inspect(stripped), ImageMetadata.Report())
    }

    func testTruncatedFilesDoNotCrash() {
        let data = jpeg(exif: tiff(orientation: 6, withGPS: true, withMake: true))
        for length in stride(from: 0, to: data.count, by: 3) {
            _ = ImageMetadata.inspect(data.prefix(length))
        }
        _ = ImageMetadata.inspect(Data([0xFF, 0xD8, 0xFF, 0xE1, 0xFF, 0xFF]))
    }

    func testNotAnImageIsEmpty() {
        XCTAssertEqual(ImageMetadata.inspect(Data("hello".utf8)), ImageMetadata.Report())
        XCTAssertNil(ImageMetadata.strippedJPEG(Data("hello".utf8), orientation: nil))
        XCTAssertNil(ImageMetadata.strippedPNG(Data("hello".utf8)))
    }
}
