// Şehir Patronları — tahta ve ekonomi verisi.
// Bu tablo ÖZGÜNDÜR: hiçbir ticari oyunun tapu/kira değerleri kopyalanmamıştır.
// Kurallar ve veriler temadan ve arayüzden bağımsızdır (yalnızca Foundation).
import Foundation

public enum Rules {
    /// Kural seti sürümü. Kayıt dosyasına yazılır.
    public static let version = "SP-1"
    public static let startCash = 15_000
    public static let salary = 2_000
    public static let jailFine = 500
    public static let houseStock = 32
    public static let hotelStock = 12
    public static let maxJailRolls = 3
    public static let minBid = 10
    public static let transportRents = [250, 500, 1_000, 2_000]
    /// Kuruluş kirası = zar toplamı × çarpan (tek kuruluş / iki kuruluş).
    public static let utilitySingle = 40
    public static let utilityBoth = 100
    /// İpotek kaldırma faizi: ipotek değerinin %10'u, yukarı yuvarlanır.
    public static func mortgageInterest(_ mortgage: Int) -> Int { (mortgage + 9) / 10 }
}

public enum Deck: String, Codable, Sendable, CaseIterable { case chance, community }

public enum SquareKind: Equatable, Sendable {
    case start
    case property(group: Int)
    case transport
    case utility
    case card(Deck)
    case tax(Int)
    case jail
    case rest
    case goToJail
}

public struct SquareDef: Equatable, Sendable, Identifiable {
    public let index: Int
    /// Kalıcı kimlik. Tema değişse de aynı kalır.
    public let id: String
    public let kind: SquareKind
    public let price: Int
    /// Mülkler için: [boş arsa, 1 ev, 2 ev, 3 ev, 4 ev, otel]
    public let rents: [Int]
    public let houseCost: Int

    public var mortgageValue: Int { price / 2 }
    public var isOwnable: Bool {
        switch kind { case .property, .transport, .utility: return true; default: return false }
    }
    public var group: Int? { if case .property(let g) = kind { return g }; return nil }
}

public enum Board {
    public static let size = 40
    public static let jailIndex = 10
    public static let groupCount = 8

    public static let squares: [SquareDef] = makeSquares()

    public static func indices(ofGroup g: Int) -> [Int] { squares.filter { $0.group == g }.map(\.index) }
    public static let transports: [Int] = squares.filter { $0.kind == .transport }.map(\.index)
    public static let utilities: [Int] = squares.filter { $0.kind == .utility }.map(\.index)
    public static func square(id: String) -> SquareDef? { squares.first { $0.id == id } }

    private enum Spec {
        case start, jail, rest, goToJail
        case prop(String, Int, Int)      // kimlik, grup, fiyat
        case transport(String), utility(String)
        case card(Deck, String), tax(String, Int)
    }

    /// Kira ölçeği fiyattan türetilir (özgün formül); testler tabloyu doğrular.
    static func rents(forPrice price: Int) -> [Int] {
        let base = ((price * 8) / 100 + 5) / 10 * 10
        func r50(_ v: Int) -> Int { (v + 25) / 50 * 50 }
        return [base, base * 5, base * 15, r50(base * 36), r50(base * 44), r50(base * 52)]
    }

    private static func makeSquares() -> [SquareDef] {
        let specs: [Spec] = [
            .start,
            .prop("p01", 0, 500), .prop("p02", 0, 600), .card(.community, "c1"), .prop("p03", 1, 900),
            .transport("t1"), .card(.chance, "s1"), .prop("p04", 1, 1_000), .tax("tax1", 2_000), .prop("p05", 1, 1_100),
            .jail,
            .prop("p06", 2, 1_300), .prop("p07", 2, 1_400), .utility("u1"), .prop("p08", 2, 1_500),
            .transport("t2"), .card(.community, "c2"), .prop("p09", 3, 1_700), .prop("p10", 3, 1_800), .prop("p11", 3, 1_900),
            .rest,
            .prop("p12", 4, 2_100), .prop("p13", 4, 2_200), .card(.chance, "s2"), .prop("p14", 4, 2_300),
            .transport("t3"), .prop("p15", 5, 2_500), .utility("u2"), .prop("p16", 5, 2_600), .prop("p17", 5, 2_700),
            .goToJail,
            .prop("p18", 6, 2_900), .card(.community, "c3"), .prop("p19", 6, 3_000), .prop("p20", 6, 3_200),
            .transport("t4"), .prop("p21", 7, 3_600), .card(.chance, "s3"), .tax("tax2", 1_000), .prop("p22", 7, 4_200),
        ]
        precondition(specs.count == size)
        return specs.enumerated().map { (i, spec) -> SquareDef in
            let houseCost = [500, 1_000, 1_500, 2_000][i / 10]
            switch spec {
            case .start: return SquareDef(index: i, id: "start", kind: .start, price: 0, rents: [], houseCost: 0)
            case .jail: return SquareDef(index: i, id: "jail", kind: .jail, price: 0, rents: [], houseCost: 0)
            case .rest: return SquareDef(index: i, id: "rest", kind: .rest, price: 0, rents: [], houseCost: 0)
            case .goToJail: return SquareDef(index: i, id: "gotojail", kind: .goToJail, price: 0, rents: [], houseCost: 0)
            case .prop(let id, let g, let price):
                return SquareDef(index: i, id: id, kind: .property(group: g), price: price, rents: rents(forPrice: price), houseCost: houseCost)
            case .transport(let id): return SquareDef(index: i, id: id, kind: .transport, price: 2_000, rents: Rules.transportRents, houseCost: 0)
            case .utility(let id): return SquareDef(index: i, id: id, kind: .utility, price: 1_500, rents: [], houseCost: 0)
            case .card(let deck, let id): return SquareDef(index: i, id: "card." + id, kind: .card(deck), price: 0, rents: [], houseCost: 0)
            case .tax(let id, let amount): return SquareDef(index: i, id: id, kind: .tax(amount), price: 0, rents: [], houseCost: 0)
            }
        }
    }
}

// MARK: - Kartlar (özgün set; mekanik etki temadan bağımsız)

public enum CardEffect: Equatable, Sendable {
    case collect(Int)
    case pay(Int)
    case collectFromEach(Int)
    case payEach(Int)
    /// İleri doğru belirtilen kareye git; Başlangıç'tan geçilirse maaş alınır.
    case moveTo(Int)
    case moveBack(Int)
    /// En yakın ulaşım karesine ilerle; sahipliyse kira `rentMultiplier` katıdır.
    case nearestTransport(rentMultiplier: Int)
    /// En yakın kuruluşa ilerle; sahipliyse yeni zar atılır ve toplamın 100 katı ödenir.
    case nearestUtility
    case goToJail
    case jailFree
    case repairs(perHouse: Int, perHotel: Int)
}

public struct CardDef: Equatable, Sendable, Identifiable {
    public let id: String
    public let deck: Deck
    public let effect: CardEffect
}

public enum Cards {
    public static let all: [CardDef] = chance + community
    public static func card(_ id: String) -> CardDef? { all.first { $0.id == id } }
    public static func ids(_ deck: Deck) -> [String] { (deck == .chance ? chance : community).map(\.id) }

    static let chance: [CardDef] = make(.chance, "s", [
        .moveTo(0), .moveTo(39), .moveTo(21), .moveTo(11), .moveTo(26), .moveTo(5),
        .nearestTransport(rentMultiplier: 2), .nearestTransport(rentMultiplier: 2), .nearestUtility,
        .moveBack(3), .goToJail, .jailFree,
        .collect(600), .collect(1_400), .pay(200), .repairs(perHouse: 250, perHotel: 1_000),
    ])
    static let community: [CardDef] = make(.community, "k", [
        .moveTo(0), .collect(1_800), .collect(900), .collect(400), .collect(300), .collect(150), .collect(750),
        .pay(500), .pay(800), .pay(450),
        .collectFromEach(200), .payEach(100),
        .goToJail, .jailFree, .repairs(perHouse: 300, perHotel: 900), .collect(1_000),
    ])

    private static func make(_ deck: Deck, _ prefix: String, _ effects: [CardEffect]) -> [CardDef] {
        precondition(effects.count == 16)
        return effects.enumerated().map { CardDef(id: prefix + String(format: "%02d", $0.offset + 1), deck: deck, effect: $0.element) }
    }
}
