import Foundation

/// Reads and removes the personal metadata in JPEG and PNG files without
/// decoding the picture: EXIF (camera, dates), GPS location, IPTC and XMP.
/// Pure byte work, so it can be tested with small synthetic files and
/// strips JPEG and PNG losslessly. GdkPixbuf can't do either: it reads no
/// metadata and writes none.
enum ImageMetadata {
    struct Report: Equatable {
        /// "Location", "EXIF", "IPTC", "XMP" — only what is really there.
        var kinds: [String] = []
        /// EXIF orientation 1–8, if the file has one.
        var orientation: Int?
    }

    /// TIFF tags that describe the pixels, not the picture: they don't count.
    private static let structuralIFD0: Set<UInt16> = [
        0x0100, 0x0101, 0x0102, 0x0103, 0x0106, 0x0112, 0x011A, 0x011B, 0x011C, 0x0128, 0x0213,
        0x8769, 0x8825,
    ]
    private static let structuralExif: Set<UInt16> = [0xA001, 0xA002, 0xA003]

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    private static let exifHeader = Array("Exif\0\0".utf8)
    private static let xmpHeader = Array("http://ns.adobe.com/xap/1.0/\0".utf8)
    private static let photoshopHeader = Array("Photoshop 3.0\0".utf8)

    // MARK: Inspect

    static func isJPEG(_ data: Data) -> Bool { data.starts(with: [0xFF, 0xD8]) }
    static func isPNG(_ data: Data) -> Bool { data.starts(with: pngSignature) }

    static func inspect(_ data: Data) -> Report {
        if isJPEG(data) { return inspectJPEG(data) }
        if isPNG(data) { return inspectPNG(data) }
        return Report()
    }

    private static func inspectJPEG(_ data: Data) -> Report {
        var report = Report()
        var kinds = Kinds()
        for segment in jpegSegments(data) where segment.marker == 0xE1 || segment.marker == 0xED {
            let payload = data[segment.payload]
            if payload.starts(with: exifHeader) {
                applyTIFF(Data(payload.dropFirst(exifHeader.count)), to: &report, kinds: &kinds)
            } else if payload.starts(with: xmpHeader) {
                kinds.xmp = true
            } else if segment.marker == 0xED, payload.starts(with: photoshopHeader) {
                kinds.iptc = true
            }
        }
        report.kinds = kinds.list
        return report
    }

    private static func inspectPNG(_ data: Data) -> Report {
        var report = Report()
        var kinds = Kinds()
        for chunk in pngChunks(data) {
            let body = data[chunk.payload]
            switch chunk.type {
            case "eXIf": applyTIFF(Data(body), to: &report, kinds: &kinds)
            case "iTXt" where body.starts(with: Array("XML:com.adobe.xmp".utf8)): kinds.xmp = true
            default: break
            }
        }
        report.kinds = kinds.list
        return report
    }

    private struct Kinds {
        var location = false, exif = false, iptc = false, xmp = false
        var list: [String] {
            var kinds: [String] = []
            if location { kinds.append("Location") }
            if exif { kinds.append("EXIF") }
            if iptc { kinds.append("IPTC") }
            if xmp { kinds.append("XMP") }
            return kinds
        }
    }

    // MARK: TIFF (the EXIF payload)

    private static func applyTIFF(_ tiff: Data, to report: inout Report, kinds: inout Kinds) {
        let bytes = [UInt8](tiff)
        guard bytes.count >= 8 else { return }
        let little: Bool
        if bytes[0] == 0x49, bytes[1] == 0x49 { little = true } else if bytes[0] == 0x4D, bytes[1] == 0x4D { little = false } else { return }
        func u16(_ at: Int) -> Int? {
            guard at >= 0, at + 2 <= bytes.count else { return nil }
            return little ? Int(bytes[at]) | Int(bytes[at + 1]) << 8 : Int(bytes[at]) << 8 | Int(bytes[at + 1])
        }
        func u32(_ at: Int) -> Int? {
            guard at >= 0, at + 4 <= bytes.count else { return nil }
            if little { return Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24 }
            return Int(bytes[at]) << 24 | Int(bytes[at + 1]) << 16 | Int(bytes[at + 2]) << 8 | Int(bytes[at + 3])
        }
        /// (tag, value-field offset) of each entry in the IFD at `offset`.
        func entries(at offset: Int) -> [(tag: UInt16, valueAt: Int)] {
            guard let count = u16(offset), count < 1000 else { return [] }
            var result: [(UInt16, Int)] = []
            for index in 0..<count {
                let entry = offset + 2 + index * 12
                guard let tag = u16(entry) else { break }
                result.append((UInt16(tag), entry + 8))
            }
            return result
        }
        guard let first = u32(4) else { return }
        for (tag, valueAt) in entries(at: first) {
            switch tag {
            case 0x0112:
                if let value = u16(valueAt), (1...8).contains(value) { report.orientation = value }
            case 0x8769:
                if let pointer = u32(valueAt), entries(at: pointer).contains(where: { !structuralExif.contains($0.tag) }) { kinds.exif = true }
            case 0x8825:
                if let pointer = u32(valueAt), !entries(at: pointer).isEmpty { kinds.location = true }
            default:
                if !structuralIFD0.contains(tag) { kinds.exif = true }
            }
        }
    }

    // MARK: Strip

    /// `data` without EXIF, GPS, IPTC, XMP and comments, byte for byte
    /// otherwise; a rotated photo keeps a tiny EXIF block holding only its
    /// orientation (dropping that would turn it on its side). `nil` if it
    /// isn't a JPEG this can read.
    static func strippedJPEG(_ data: Data, orientation: Int?) -> Data? {
        guard isJPEG(data) else { return nil }
        var output = Data([0xFF, 0xD8])
        var wroteOrientation = orientation == nil || orientation == 1
        func writeOrientation() {
            guard !wroteOrientation, let orientation else { return }
            output.append(orientationSegment(orientation))
            wroteOrientation = true
        }
        var end = 2
        for segment in jpegSegments(data) {
            end = segment.whole.upperBound
            let payload = data[segment.payload]
            let drop: Bool
            switch segment.marker {
            case 0xE1: drop = payload.starts(with: exifHeader) || payload.starts(with: xmpHeader)
            case 0xED: drop = payload.starts(with: photoshopHeader)
            case 0xFE: drop = true
            default: drop = false
            }
            // After a leading JFIF (APP0) segment, before anything else.
            if segment.marker != 0xE0 { writeOrientation() }
            if !drop { output.append(data[segment.whole]) }
        }
        writeOrientation()
        // Everything from the scan on is image data: copied as is.
        output.append(data[end...])
        return output
    }

    /// PNG without text, time and EXIF chunks; the picture chunks as is.
    static func strippedPNG(_ data: Data) -> Data? {
        guard isPNG(data) else { return nil }
        var output = Data(pngSignature)
        let dropped: Set<String> = ["tEXt", "zTXt", "iTXt", "eXIf", "tIME"]
        var end = pngSignature.count
        for chunk in pngChunks(data) {
            end = chunk.whole.upperBound
            if !dropped.contains(chunk.type) { output.append(data[chunk.whole]) }
        }
        output.append(data[end...])
        return output
    }

    private static func orientationSegment(_ orientation: Int) -> Data {
        var tiff: [UInt8] = [0x4D, 0x4D, 0x00, 0x2A, 0, 0, 0, 8, 0, 1]
        tiff += [0x01, 0x12, 0x00, 0x03, 0, 0, 0, 1, 0, UInt8(orientation), 0, 0]
        tiff += [0, 0, 0, 0]
        let body = exifHeader + tiff
        let length = body.count + 2
        return Data([0xFF, 0xE1, UInt8(length >> 8), UInt8(length & 0xFF)] + body)
    }

    // MARK: Containers

    private struct Segment {
        let marker: UInt8
        /// The marker, length and payload.
        let whole: Range<Int>
        let payload: Range<Int>
    }

    /// The JPEG's segments up to the start of the scan.
    private static func jpegSegments(_ data: Data) -> [Segment] {
        var segments: [Segment] = []
        var index = data.startIndex + 2
        while index + 4 <= data.endIndex {
            guard data[index] == 0xFF else { break }
            let marker = data[index + 1]
            if marker == 0xFF { index += 1; continue }
            // Markers with no length, and the scan itself: the metadata is over.
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) { index += 2; continue }
            if marker == 0xDA || marker == 0xD9 { break }
            let length = Int(data[index + 2]) << 8 | Int(data[index + 3])
            guard length >= 2, index + 2 + length <= data.endIndex else { break }
            segments.append(Segment(marker: marker, whole: index..<(index + 2 + length), payload: (index + 4)..<(index + 2 + length)))
            index += 2 + length
        }
        return segments
    }

    private struct Chunk {
        let type: String
        let whole: Range<Int>
        let payload: Range<Int>
    }

    private static func pngChunks(_ data: Data) -> [Chunk] {
        var chunks: [Chunk] = []
        var index = data.startIndex + pngSignature.count
        while index + 12 <= data.endIndex {
            let length = Int(data[index]) << 24 | Int(data[index + 1]) << 16 | Int(data[index + 2]) << 8 | Int(data[index + 3])
            let type = String(decoding: data[(index + 4)..<(index + 8)], as: UTF8.self)
            let whole = index..<(index + 12 + length)
            guard whole.upperBound <= data.endIndex else { break }
            chunks.append(Chunk(type: type, whole: whole, payload: (index + 8)..<(index + 8 + length)))
            index = whole.upperBound
            if type == "IEND" { break }
        }
        return chunks
    }
}
