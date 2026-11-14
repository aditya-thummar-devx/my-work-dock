import AppKit
import CoreImage.CIFilterBuiltins
import Foundation

/// The data encoded into the ADB wireless pairing QR code.
struct AdbQRPayload: Equatable {
    /// The mDNS service name advertised by the ADB pairing server.
    var serviceName: String
    /// The pairing password shown alongside the QR code.
    var password: String

    /// The WIFI-style string that Android's pairing flow expects.
    var qrString: String { "WIFI:T:ADB;S:\(serviceName);P:\(password);;" }
}

/// Generates ADB wireless pairing payloads and their QR code images.
enum AdbQRGenerator {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")

    /// Returns a fresh `AdbQRPayload` with a unique service name and a random 8-character alphanumeric password.
    static func makePayload() -> AdbQRPayload {
        let uuidPrefix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(8)
        let serviceName = "mwd-\(uuidPrefix)"
        let password = randomAlphanumeric(length: 8)
        return AdbQRPayload(serviceName: serviceName, password: password)
    }

    /// Renders the QR code for `payload` as an `NSImage` scaled to `size` points.
    static func qrImage(for payload: AdbQRPayload, size: CGFloat = 160) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.qrString.utf8)
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return nil }
        let extent = ciImage.extent
        guard extent.width > 0 else { return nil }

        let scale = size / extent.width
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }

    // MARK: Private

    private static func randomAlphanumeric(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        precondition(status == errSecSuccess, "no secure random bytes")
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }
}
