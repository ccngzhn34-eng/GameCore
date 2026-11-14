import Foundation

/// Kayıt dosyası zarfı. Dosya okuma/yazma platform katmanındadır; burada yalnızca biçim ve doğrulama var.
public struct SaveFile: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var rulesVersion: String
    public var savedAt: Date
    public var themeID: String
    public var state: GameState
}

public enum SaveError: Error, Equatable, Sendable {
    /// Kayıt bu uygulamanın bilmediği bir veri sürümüyle yazılmış.
    case unsupportedSchema(found: Int, supported: Int)
    case rulesMismatch(found: String, expected: String)
    case corrupt(String)
}

public enum SaveCodec {
    public static let schemaVersion = 1

    public static func encode(_ state: GameState, themeID: String, date: Date = Date()) throws -> Data {
        let file = SaveFile(schemaVersion: schemaVersion, rulesVersion: Rules.version, savedAt: date, themeID: themeID, state: state)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(file)
    }

    public static func decode(_ data: Data) throws -> SaveFile {
        struct Header: Decodable { let schemaVersion: Int; let rulesVersion: String }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let header: Header
        do { header = try decoder.decode(Header.self, from: data) } catch { throw SaveError.corrupt("başlık okunamadı") }
        guard header.schemaVersion == schemaVersion else {
            throw SaveError.unsupportedSchema(found: header.schemaVersion, supported: schemaVersion)
        }
        guard header.rulesVersion == Rules.version else {
            throw SaveError.rulesMismatch(found: header.rulesVersion, expected: Rules.version)
        }
        let file: SaveFile
        do { file = try decoder.decode(SaveFile.self, from: data) } catch { throw SaveError.corrupt("içerik okunamadı") }
        try validate(file.state)
        return file
    }

    /// Bozuk ya da elle değiştirilmiş kayıtların oyunu çökertmesini önleyen tutarlılık denetimi.
    static func validate(_ s: GameState) throws {
        guard (2...6).contains(s.players.count) else { throw SaveError.corrupt("oyuncu sayısı") }
        guard s.players.indices.allSatisfy({ s.players[$0].id == $0 }) else { throw SaveError.corrupt("oyuncu kimliği") }
        guard s.players.allSatisfy({ (0..<Board.size).contains($0.position) && $0.cash >= 0 }) else { throw SaveError.corrupt("oyuncu durumu") }
        guard s.players.indices.contains(s.current) else { throw SaveError.corrupt("sıra") }
        for (sq, h) in s.holdings {
            guard (0..<Board.size).contains(sq), Board.squares[sq].isOwnable, s.players.indices.contains(h.owner), (0...5).contains(h.level)
            else { throw SaveError.corrupt("tapu \(sq)") }
            if h.level > 0 { guard Board.squares[sq].group != nil, !h.mortgaged else { throw SaveError.corrupt("bina \(sq)") } }
        }
        guard s.housesLeft >= 0, s.hotelsLeft >= 0 else { throw SaveError.corrupt("bina stoğu") }
        var held = s.players.flatMap(\.jailCards)
        // Çekilmiş ama henüz onaylanmamış çıkış kartı ne destede ne oyuncudadır.
        if case .card(let id) = s.phase, Cards.card(id)?.effect == .jailFree { held.append(id) }
        let all = (s.chanceDeck + s.communityDeck + held).sorted()
        guard all == Cards.all.map(\.id).sorted() else { throw SaveError.corrupt("kart destesi") }
    }
}
