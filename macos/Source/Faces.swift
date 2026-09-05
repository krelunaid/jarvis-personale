import Foundation
import Security
import CoreGraphics
import ImageIO
import Vision

enum FaceCommand {
    case enroll(String)
    case list
    case forget(String)
    static func parse(_ text: String) -> FaceCommand? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("jarvis") {
            value = String(value.dropFirst(6)).trimmingCharacters(in: CharacterSet(charactersIn: " ,:."))
        }
        let lower = value.lowercased()
        for prefix in ["ricorda questo volto come ", "ricorda questo viso come ", "iscrivi questo volto come ", "memorizza questo volto come "] {
            if lower.hasPrefix(prefix) {
                let name = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? nil : .enroll(name)
            }
        }
        if ["chi hai in rubrica volti", "elenca i volti", "quali volti ricordi", "quali volti conosci", "mostra la rubrica volti", "rubrica volti"].contains(lower.trimmingCharacters(in: CharacterSet(charactersIn: "?"))) {
            return .list
        }
        if let range = lower.range(of: " dalla rubrica volti"), lower.hasPrefix("dimentica") || lower.hasPrefix("scorda") || lower.hasPrefix("cancella") || lower.hasPrefix("elimina") || lower.hasPrefix("togli") {
            let name = String(value[..<value.index(value.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.lowerBound))]).replacingOccurrences(of: "dimentica", with: "", options: .caseInsensitive).replacingOccurrences(of: "scorda", with: "", options: .caseInsensitive).replacingOccurrences(of: "cancella", with: "", options: .caseInsensitive).replacingOccurrences(of: "elimina", with: "", options: .caseInsensitive).replacingOccurrences(of: "togli", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : .forget(name)
        }
        for prefix in ["dimentica il volto di ", "dimentica il viso di ", "scorda il volto di ", "cancella il volto di ", "elimina il volto di "] {
            if lower.hasPrefix(prefix) {
                let name = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? nil : .forget(name)
            }
        }
        return nil
    }
}

struct FacePerson: Codable {
    let id: String
    var name: String
    var prints: [[Double]]
}

enum FacePrint {
    static let size = 32
    static let threshold = 0.86
    static let margin = 0.05
    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        return zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }
    static func fromLuminance(_ pixels: [Double]) -> [Double] {
        let norm = sqrt(pixels.reduce(0) { $0 + $1 * $1 })
        guard norm > 1e-9 else { return pixels }
        return pixels.map { $0 / norm }
    }
}

enum FaceBook {
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "local.jarvis.personal", kSecAttrAccount as String: "faces"]
    static func load() throws -> [FacePerson] {
        var q = query; q[kSecReturnData as String] = true; var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return [] }
        let decoded = try JSONSerialization.jsonObject(with: data)
        guard let items = decoded as? [[String: Any]] else { throw Failure(message: "Rubrica volti non leggibile. Il contenuto salvato non è stato modificato.") }
        return try items.map { item in
            guard let id = item["id"] as? String, let name = item["name"] as? String, let rawPrints = item["prints"] as? [[Any]] else {
                throw Failure(message: "Rubrica volti non leggibile. Il contenuto salvato non è stato modificato.")
            }
            let prints = rawPrints.map { row in row.compactMap { ($0 as? NSNumber)?.doubleValue ?? ($0 as? Double) } }
            return FacePerson(id: id, name: name, prints: prints)
        }
    }
    static func save(_ people: [FacePerson]) throws {
        let data = try JSONSerialization.data(withJSONObject: people.map { ["id": $0.id, "name": $0.name, "prints": $0.prints] })
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(message: "Non riesco a salvare la rubrica volti.") }
    }
    static func listText(_ people: [FacePerson]) -> String {
        people.isEmpty ? "Nessun volto in rubrica." : "In rubrica volti: " + people.map(\.name).joined(separator: ", ") + "."
    }
    static func match(_ print: [Double], people: [FacePerson]) -> String? {
        var bestName: String?
        var best = 0.0
        var second = 0.0
        for person in people {
            let score = person.prints.map { FacePrint.cosine(print, $0) }.max() ?? 0
            if score > best { second = best; best = score; bestName = person.name }
            else if score > second { second = score }
        }
        guard let bestName, best >= FacePrint.threshold, best - second >= FacePrint.margin else { return nil }
        return bestName
    }
    static func identify(known: [String], unknown: Int) -> String {
        if known.isEmpty && unknown == 0 { return "Riconoscimento volti locale: nessun volto rilevato. Non inventare identità." }
        var parts: [String] = []
        if !known.isEmpty { parts.append("Persone iscritte nel riquadro: " + known.joined(separator: ", ") + ".") }
        if unknown == 1 { parts.append("C’è 1 persona non in rubrica volti: dilla così, senza inventare un nome.") }
        else if unknown > 1 { parts.append("Ci sono \(unknown) persone non in rubrica volti: non inventare nomi.") }
        return "Riconoscimento volti locale (solo iscritti). " + parts.joined(separator: " ")
    }
    static func boxes(in jpeg: Data) -> [CGRect] {
        var found: [CGRect] = []
        let request = VNDetectFaceRectanglesRequest { req, _ in
            found = (req.results as? [VNFaceObservation])?.map(\.boundingBox) ?? []
        }
        let handler = VNImageRequestHandler(data: jpeg, options: [:])
        try? handler.perform([request])
        return found
    }
    static func descriptor(from jpeg: Data, box: CGRect) -> [Double]? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = image.width
        let height = image.height
        let px = CGRect(x: box.origin.x * CGFloat(width), y: (1 - box.origin.y - box.height) * CGFloat(height), width: box.width * CGFloat(width), height: box.height * CGFloat(height))
        let pad = max(4, min(px.width, px.height) * 0.18)
        let crop = CGRect(x: max(0, px.minX - pad), y: max(0, px.minY - pad), width: min(CGFloat(width), px.maxX + pad) - max(0, px.minX - pad), height: min(CGFloat(height), px.maxY + pad) - max(0, px.minY - pad)).integral
        guard crop.width > 8, crop.height > 8, let clipped = image.cropping(to: crop) else { return nil }
        let size = FacePrint.size
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(clipped, in: CGRect(x: 0, y: 0, width: size, height: size))
        var lum = [Double](repeating: 0, count: size * size)
        for i in 0..<(size * size) {
            let o = i * 4
            lum[i] = (0.299 * Double(pixels[o]) + 0.587 * Double(pixels[o + 1]) + 0.114 * Double(pixels[o + 2])) / 255
        }
        return FacePrint.fromLuminance(lum)
    }
    static func sight(_ jpeg: Data, people: [FacePerson]) -> (note: String, known: [String], unknown: Int) {
        let boxes = boxes(in: jpeg)
        var known: [String] = []
        var unknown = 0
        for box in boxes {
            guard let print = descriptor(from: jpeg, box: box), let name = match(print, people: people) else { unknown += 1; continue }
            if !known.contains(name) { known.append(name) }
        }
        return (identify(known: known, unknown: unknown), known, unknown)
    }
}
