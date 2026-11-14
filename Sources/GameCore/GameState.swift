import Foundation

/// Kayda yazılabilen, tekrarlanabilir rastgele sayı üreteci (SplitMix64).
/// Çevrim içi sürümde aynı üreteç sunucuda çalışacak; istemci zar üretmez.
public struct SeededRNG: Codable, Equatable, Sendable {
    var state: UInt64
    public init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(below n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func shuffled<T>(_ items: [T]) -> [T] {
        var a = items
        guard a.count > 1 else { return a }
        for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, int(below: i + 1)) }
        return a
    }
}

public struct Player: Codable, Equatable, Identifiable, Sendable {
    public let id: Int            // oyuncu dizisindeki sıra ile aynıdır
    public var name: String
    public var pawn: String       // piyon kimliği (görsel katman yorumlar)
    public internal(set) var cash: Int
    public internal(set) var position: Int
    public internal(set) var inJail: Bool
    public internal(set) var jailRolls: Int
    public internal(set) var jailCards: [String]
    public internal(set) var bankrupt: Bool
}

public struct Holding: Codable, Equatable, Sendable {
    public internal(set) var owner: Int
    /// 0 = boş, 1–4 = ev, 5 = otel
    public internal(set) var level: Int
    public internal(set) var mortgaged: Bool
}

public enum Creditor: Codable, Equatable, Sendable { case bank, player(Int) }

public struct Payment: Codable, Equatable, Sendable {
    public let from: Int
    public let to: Creditor
    public let amount: Int
}

public enum Lot: Codable, Equatable, Sendable {
    case property(Int)
    case building(hotel: Bool)
}

public struct Auction: Codable, Equatable, Sendable {
    public let lot: Lot
    public internal(set) var highBid: Int
    public internal(set) var highBidder: Int?
    /// Hâlâ artırmada olan oyuncular (sıra düzeninde).
    public internal(set) var bidders: [Int]
    public internal(set) var turn: Int
    public var currentBidder: Int { bidders[turn] }
}

enum Continuation: Codable, Equatable, Sendable {
    case endOfMove
    case moveAfterJailFine(d1: Int, d2: Int)
}

public enum Phase: Codable, Equatable, Sendable {
    case awaitingRoll
    case jailDecision
    case buyDecision(square: Int)
    case auction(Auction)
    case card(id: String)
    case debt(Payment)
    case placeBuilding(player: Int, hotel: Bool)
    /// Hamle bitti; oyuncu yönetim işlemleri yapıp sırayı devreder.
    case manage
    case gameOver(winner: Int)
}

public enum Event: Codable, Equatable, Sendable {
    case turnStarted(player: Int)
    case rolled(player: Int, d1: Int, d2: Int)
    case moved(player: Int, from: Int, to: Int, forward: Bool)
    case salary(player: Int, amount: Int)
    case paid(from: Int, to: Creditor, amount: Int)
    case received(player: Int, amount: Int)
    case bought(player: Int, square: Int, price: Int)
    case auctionStarted(lot: Lot)
    case auctionWon(player: Int, lot: Lot, bid: Int)
    case auctionNoSale(lot: Lot)
    case drewCard(player: Int, card: String)
    case jailed(player: Int)
    case released(player: Int)
    case built(player: Int, square: Int, level: Int)
    case soldBuilding(player: Int, square: Int, level: Int)
    case mortgaged(player: Int, square: Int)
    case unmortgaged(player: Int, square: Int)
    case traded(from: Int, to: Int)
    case bankrupt(player: Int, to: Creditor)
    case won(player: Int)
}

public struct TradeOffer: Codable, Equatable, Sendable {
    public var from: Int
    public var to: Int
    public var cashFrom: Int
    public var cashTo: Int
    public var squaresFrom: [Int]
    public var squaresTo: [Int]
    public var jailCardsFrom: Int
    public var jailCardsTo: Int
    /// Devralınan ipotekli tapulardan hemen ipoteği kaldırılacak olanlar.
    public var unmortgageNow: [Int]

    public init(from: Int, to: Int, cashFrom: Int = 0, cashTo: Int = 0, squaresFrom: [Int] = [], squaresTo: [Int] = [],
                jailCardsFrom: Int = 0, jailCardsTo: Int = 0, unmortgageNow: [Int] = []) {
        self.from = from; self.to = to; self.cashFrom = cashFrom; self.cashTo = cashTo
        self.squaresFrom = squaresFrom; self.squaresTo = squaresTo
        self.jailCardsFrom = jailCardsFrom; self.jailCardsTo = jailCardsTo; self.unmortgageNow = unmortgageNow
    }
}

public enum Action: Codable, Equatable, Sendable {
    case roll
    case payJailFine
    case useJailCard
    case buy
    case sendToAuction
    case bid(Int)
    case passBid
    case acknowledgeCard
    case build(Int)
    case sellBuilding(Int)
    case placeBuilding(Int)
    case mortgage(Int)
    case unmortgage(Int)
    case trade(TradeOffer)
    case settleDebt
    case declareBankruptcy
    case endTurn
}

public enum RuleError: Error, Equatable, Sendable {
    case wrongPhase
    case insufficientFunds
    case notOwner
    case notAllowed(Reason)

    public enum Reason: String, Sendable {
        case groupIncomplete, groupMortgaged, unevenBuild, unevenSell, noStock, maxLevel, noBuildings
        case hasBuildings, alreadyMortgaged, notMortgaged, notOwnable, bidTooLow, invalidTrade
        case canStillPay, noJailCard, invalidSite
    }
}

public struct GameState: Codable, Equatable, Sendable {
    public internal(set) var players: [Player]
    /// Kare sırası → sahiplik. Kayıtta yalnızca sahipli kareler bulunur.
    public internal(set) var holdings: [Int: Holding]
    public internal(set) var chanceDeck: [String]
    public internal(set) var communityDeck: [String]
    public internal(set) var current: Int
    public internal(set) var doubles: Int
    public internal(set) var rollAgain: Bool
    public internal(set) var lastDice: [Int]
    public internal(set) var phase: Phase
    public internal(set) var payments: [Payment]
    public internal(set) var auctionQueue: [Int]
    var continuation: Continuation
    var resumePhase: Phase?
    public internal(set) var turn: Int
    /// Her başarılı işlemde artar; yinelenen isteklerin ayıklanması (çevrim içi) için.
    public internal(set) var revision: Int
    public internal(set) var log: [Event]
    var rng: SeededRNG
    /// Yalnızca testler: sıradaki zarları belirler.
    var scriptedDice: [Int]

    public static func newGame(players specs: [(name: String, pawn: String)], seed: UInt64) -> GameState {
        precondition((2...6).contains(specs.count), "2–6 oyuncu gerekir")
        var rng = SeededRNG(seed: seed)
        let chance = rng.shuffled(Cards.ids(.chance))
        let community = rng.shuffled(Cards.ids(.community))
        let players = specs.enumerated().map {
            Player(id: $0.offset, name: $0.element.name, pawn: $0.element.pawn, cash: Rules.startCash, position: 0,
                   inJail: false, jailRolls: 0, jailCards: [], bankrupt: false)
        }
        return GameState(players: players, holdings: [:], chanceDeck: chance, communityDeck: community, current: 0, doubles: 0,
                         rollAgain: false, lastDice: [], phase: .awaitingRoll, payments: [], auctionQueue: [],
                         continuation: .endOfMove, resumePhase: nil, turn: 1, revision: 0,
                         log: [.turnStarted(player: 0)], rng: rng, scriptedDice: [])
    }
}

// MARK: - Sorgular (arayüz ve testler için)

extension GameState {
    public var activePlayers: [Int] { players.indices.filter { !players[$0].bankrupt } }

    /// Şu an karar vermesi beklenen oyuncu.
    public var actingPlayer: Int {
        switch phase {
        case .auction(let a): return a.currentBidder
        case .debt(let p): return p.from
        case .placeBuilding(let player, _): return player
        case .gameOver(let winner): return winner
        default: return current
        }
    }

    public var housesLeft: Int { Rules.houseStock - holdings.values.reduce(0) { $0 + ($1.level < 5 ? $1.level : 0) } }
    public var hotelsLeft: Int { Rules.hotelStock - holdings.values.filter { $0.level == 5 }.count }

    public func owner(of square: Int) -> Int? { holdings[square]?.owner }
    public func squares(ownedBy player: Int) -> [Int] { holdings.filter { $0.value.owner == player }.map(\.key).sorted() }

    public func ownsWholeGroup(_ group: Int, player: Int) -> Bool {
        Board.indices(ofGroup: group).allSatisfy { holdings[$0]?.owner == player }
    }

    func groupLevels(_ group: Int) -> [Int] { Board.indices(ofGroup: group).map { holdings[$0]?.level ?? 0 } }

    /// Bir kareye gelen oyuncunun ödeyeceği kira (ipotekliyse 0).
    public func rent(for square: Int, diceTotal: Int, transportMultiplier: Int = 1, utilityMultiplier: Int? = nil) -> Int {
        guard let h = holdings[square], !h.mortgaged else { return 0 }
        let def = Board.squares[square]
        switch def.kind {
        case .property(let g):
            if h.level > 0 { return def.rents[h.level] }
            return def.rents[0] * (ownsWholeGroup(g, player: h.owner) ? 2 : 1)
        case .transport:
            let n = Board.transports.filter { holdings[$0]?.owner == h.owner }.count
            return Rules.transportRents[max(0, n - 1)] * transportMultiplier
        case .utility:
            let n = Board.utilities.filter { holdings[$0]?.owner == h.owner }.count
            let mult = utilityMultiplier ?? (n >= 2 ? Rules.utilityBoth : Rules.utilitySingle)
            return diceTotal * mult
        default: return 0
        }
    }

    /// Ev/otel kurulabilir mi? `ignoringCash`: bina artırmasını kazanan için bedel önceden ödenmiştir.
    public func buildCheck(_ square: Int, player: Int, ignoringCash: Bool = false) -> RuleError? {
        let def = Board.squares[square]
        guard let g = def.group else { return .notAllowed(.notOwnable) }
        guard let h = holdings[square], h.owner == player else { return .notOwner }
        guard ownsWholeGroup(g, player: player) else { return .notAllowed(.groupIncomplete) }
        guard Board.indices(ofGroup: g).allSatisfy({ holdings[$0]?.mortgaged == false }) else { return .notAllowed(.groupMortgaged) }
        guard h.level < 5 else { return .notAllowed(.maxLevel) }
        guard h.level == groupLevels(g).min() else { return .notAllowed(.unevenBuild) }
        if h.level == 4 { guard hotelsLeft > 0 else { return .notAllowed(.noStock) } }
        else { guard housesLeft > 0 else { return .notAllowed(.noStock) } }
        if !ignoringCash && players[player].cash < def.houseCost { return .insufficientFunds }
        return nil
    }

    public func sellCheck(_ square: Int, player: Int) -> RuleError? {
        let def = Board.squares[square]
        guard let g = def.group else { return .notAllowed(.notOwnable) }
        guard let h = holdings[square], h.owner == player else { return .notOwner }
        guard h.level > 0 else { return .notAllowed(.noBuildings) }
        guard h.level == groupLevels(g).max() else { return .notAllowed(.unevenSell) }
        return nil
    }

    public func mortgageCheck(_ square: Int, player: Int) -> RuleError? {
        let def = Board.squares[square]
        guard def.isOwnable else { return .notAllowed(.notOwnable) }
        guard let h = holdings[square], h.owner == player else { return .notOwner }
        guard !h.mortgaged else { return .notAllowed(.alreadyMortgaged) }
        if let g = def.group, groupLevels(g).contains(where: { $0 > 0 }) { return .notAllowed(.hasBuildings) }
        return nil
    }

    public func unmortgageCost(_ square: Int) -> Int {
        let m = Board.squares[square].mortgageValue
        return m + Rules.mortgageInterest(m)
    }

    /// Oyuncunun binalarını satıp tapularını ipotek ederek ulaşabileceği en yüksek nakit.
    public func liquidationValue(of player: Int) -> Int {
        var total = players[player].cash
        for (sq, h) in holdings where h.owner == player {
            let def = Board.squares[sq]
            total += h.level * def.houseCost / 2
            if !h.mortgaged { total += def.mortgageValue }
        }
        return total
    }

    /// Belirli bina türü için oyuncunun en ucuz yasal arsası (bina artırmasında en düşük teklif).
    func cheapestSite(for player: Int, hotel: Bool, requireCash: Bool) -> Int? {
        squares(ownedBy: player)
            .filter { (holdings[$0]?.level == 4) == hotel && buildCheck($0, player: player, ignoringCash: !requireCash) == nil }
            .map { Board.squares[$0].houseCost }.min()
    }

    public func minimumBid(for player: Int, in auction: Auction) -> Int {
        var floor = Rules.minBid
        if case .building(let hotel) = auction.lot { floor = cheapestSite(for: player, hotel: hotel, requireCash: false) ?? Rules.minBid }
        return max(floor, auction.highBid + Rules.minBid)
    }
}
