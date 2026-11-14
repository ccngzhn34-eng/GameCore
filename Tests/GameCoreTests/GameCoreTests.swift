import XCTest
@testable import GameCore

// DİKKAT: Bu testler yazıldıkları ortamda ÇALIŞTIRILMADI (Swift araç zinciri yoktu).
// Mac'te:  cd Packages/GameCore && swift test

final class GameCoreTests: XCTestCase {

    private func game(_ n: Int = 3, seed: UInt64 = 7) -> GameState {
        GameState.newGame(players: (0..<n).map { (name: "O\($0 + 1)", pawn: "p\($0)") }, seed: seed)
    }
    private func own(_ s: inout GameState, _ squares: [Int], by p: Int, level: Int = 0, mortgaged: Bool = false) {
        for sq in squares { s.holdings[sq] = Holding(owner: p, level: level, mortgaged: mortgaged) }
    }
    private func totalCash(_ s: GameState) -> Int { s.players.reduce(0) { $0 + $1.cash } }

    // MARK: Veri bütünlüğü

    func testBoardStructure() {
        XCTAssertEqual(Board.squares.count, 40)
        XCTAssertEqual(Board.squares.filter { $0.group != nil }.count, 22)
        XCTAssertEqual(Board.transports.count, 4)
        XCTAssertEqual(Board.utilities.count, 2)
        XCTAssertEqual(Set(Board.squares.map(\.id)).count, 40, "kare kimlikleri benzersiz olmalı")
        XCTAssertEqual((0..<8).map { Board.indices(ofGroup: $0).count }, [2, 3, 3, 3, 3, 3, 3, 2])
        for sq in Board.squares where sq.group != nil {
            XCTAssertEqual(sq.rents.count, 6)
            XCTAssertEqual(sq.rents, sq.rents.sorted(), "\(sq.id) kiraları artan olmalı")
            XCTAssertGreaterThan(sq.houseCost, 0)
        }
        XCTAssertEqual(Board.squares[29].rents, [220, 1_100, 3_300, 7_900, 9_700, 11_450])
    }

    func testDecksAndThemesCoverEveryID() {
        XCTAssertEqual(Cards.chance.count, 16)
        XCTAssertEqual(Cards.community.count, 16)
        XCTAssertEqual(Set(Cards.all.map(\.id)).count, 32)
        for theme in Theme.all {
            for sq in Board.squares where sq.isOwnable { XCTAssertNotNil(theme.names[sq.id], "\(theme.id) \(sq.id)") }
            for card in Cards.all { XCTAssertFalse(theme.flavor(of: card).isEmpty, "\(theme.id) \(card.id)") }
            XCTAssertEqual(Set(Board.squares.filter(\.isOwnable).map { theme.name(of: $0) }).count, 28, "\(theme.id) adları benzersiz olmalı")
        }
    }

    func testMoneyFormatting() {
        XCTAssertEqual(Money.text(0), "₺0")
        XCTAssertEqual(Money.text(950), "₺950")
        XCTAssertEqual(Money.text(2_700), "₺2.700")
        XCTAssertEqual(Money.text(1_234_567), "₺1.234.567")
    }

    // MARK: Zar, başlangıç, çiftler

    func testRollMovesAndOffersPurchase() throws {
        var s = game()
        s.scriptedDice = [1, 3]
        try s.apply(.roll)
        XCTAssertEqual(s.players[0].position, 4)
        XCTAssertEqual(s.phase, .buyDecision(square: 4))
        try s.apply(.buy)
        XCTAssertEqual(s.owner(of: 4), 0)
        XCTAssertEqual(s.players[0].cash, Rules.startCash - 900)
        XCTAssertEqual(s.phase, .manage)
        try s.apply(.endTurn)
        XCTAssertEqual(s.current, 1)
        XCTAssertEqual(s.phase, .awaitingRoll)
    }

    func testPassingStartPaysSalary() throws {
        var s = game()
        s.players[0].position = 38
        s.scriptedDice = [1, 2]            // 38 → 1
        try s.apply(.roll)
        XCTAssertEqual(s.players[0].position, 1)
        XCTAssertEqual(s.players[0].cash, Rules.startCash + Rules.salary)
    }

    func testDoublesGrantAnotherRollAndThirdDoubleJails() throws {
        var s = game()
        own(&s, Array(0..<40).filter { Board.squares[$0].isOwnable }, by: 0)   // kendi mülkleri: karar çıkmasın
        s.scriptedDice = [1, 1, 1, 1, 3, 3]      // 2 → 4 → üçüncü çift
        try s.apply(.roll)
        XCTAssertEqual(s.phase, .awaitingRoll)
        XCTAssertThrowsError(try s.apply(.endTurn))
        try s.apply(.roll)
        XCTAssertEqual(s.phase, .awaitingRoll)
        try s.apply(.roll)
        XCTAssertTrue(s.players[0].inJail)
        XCTAssertEqual(s.players[0].position, Board.jailIndex)
        XCTAssertEqual(s.phase, .manage)
    }

    // MARK: Kira

    func testPropertyRentDoublesWithFullGroupAndUsesHouseTable() {
        var s = game()
        own(&s, [1], by: 1)
        XCTAssertEqual(s.rent(for: 1, diceTotal: 7), 40)
        own(&s, [2], by: 1)
        XCTAssertEqual(s.rent(for: 1, diceTotal: 7), 80)
        s.holdings[1]?.level = 3
        XCTAssertEqual(s.rent(for: 1, diceTotal: 7), Board.squares[1].rents[3])
        s.holdings[1]?.level = 0
        s.holdings[1]?.mortgaged = true
        XCTAssertEqual(s.rent(for: 1, diceTotal: 7), 0, "ipotekli tapu kira almaz")
        XCTAssertEqual(s.rent(for: 2, diceTotal: 7), 100, "grup tamsa ipoteksiz tapu çift kira alır")
    }

    func testTransportAndUtilityRent() {
        var s = game()
        own(&s, [5], by: 1)
        XCTAssertEqual(s.rent(for: 5, diceTotal: 7), 250)
        own(&s, [15, 25], by: 1)
        XCTAssertEqual(s.rent(for: 5, diceTotal: 7), 1_000)
        XCTAssertEqual(s.rent(for: 5, diceTotal: 7, transportMultiplier: 2), 2_000)
        own(&s, [13], by: 2)
        XCTAssertEqual(s.rent(for: 13, diceTotal: 7), 280)
        own(&s, [27], by: 2)
        XCTAssertEqual(s.rent(for: 13, diceTotal: 7), 700)
    }

    func testLandingOnOwnedPropertyTransfersRentAutomatically() throws {
        var s = game()
        own(&s, [4], by: 1)
        s.scriptedDice = [1, 3]
        try s.apply(.roll)
        XCTAssertEqual(s.players[0].cash, Rules.startCash - 70)
        XCTAssertEqual(s.players[1].cash, Rules.startCash + 70)
        XCTAssertEqual(s.phase, .manage)
    }

    // MARK: Açık artırma

    func testDecliningStartsAuctionIncludingDecliner() throws {
        var s = game()
        s.scriptedDice = [1, 3]
        try s.apply(.roll)
        try s.apply(.sendToAuction)
        guard case .auction(let a) = s.phase else { return XCTFail("artırma başlamalı") }
        XCTAssertEqual(a.bidders, [1, 2, 0])
        XCTAssertThrowsError(try s.apply(.bid(5)))
        try s.apply(.bid(100))        // 1
        try s.apply(.passBid)         // 2
        try s.apply(.bid(150))        // 0
        try s.apply(.passBid)         // 1
        XCTAssertEqual(s.owner(of: 4), 0)
        XCTAssertEqual(s.players[0].cash, Rules.startCash - 150)
        XCTAssertEqual(s.phase, .manage)
    }

    func testAuctionWithNoBidsLeavesPropertyUnowned() throws {
        var s = game(2)
        s.scriptedDice = [1, 3]
        try s.apply(.roll)
        try s.apply(.sendToAuction)
        try s.apply(.passBid)
        try s.apply(.passBid)
        XCTAssertNil(s.owner(of: 4))
        XCTAssertEqual(s.phase, .manage)
    }

    // MARK: Bina

    func testEvenBuildingAndSelling() throws {
        var s = game()
        own(&s, [1], by: 0)
        XCTAssertEqual(s.buildCheck(1, player: 0), .notAllowed(.groupIncomplete))
        own(&s, [2], by: 0)
        try s.apply(.build(1))
        XCTAssertThrowsError(try s.apply(.build(1))) { XCTAssertEqual($0 as? RuleError, .notAllowed(.unevenBuild)) }
        try s.apply(.build(2))
        try s.apply(.build(2))
        XCTAssertEqual(s.players[0].cash, Rules.startCash - 1_500)
        XCTAssertEqual(s.housesLeft, 29)
        XCTAssertThrowsError(try s.apply(.sellBuilding(1))) { XCTAssertEqual($0 as? RuleError, .notAllowed(.unevenSell)) }
        try s.apply(.sellBuilding(2))
        XCTAssertEqual(s.players[0].cash, Rules.startCash - 1_500 + 250)
        XCTAssertThrowsError(try s.apply(.mortgage(1))) { XCTAssertEqual($0 as? RuleError, .notAllowed(.hasBuildings)) }
    }

    func testHotelReturnsFourHousesToStock() throws {
        var s = game()
        own(&s, [1, 2], by: 0, level: 4)
        XCTAssertEqual(s.housesLeft, 24)
        try s.apply(.build(1))
        XCTAssertEqual(s.holdings[1]?.level, 5)
        XCTAssertEqual(s.housesLeft, 28)
        XCTAssertEqual(s.hotelsLeft, 11)
    }

    func testHouseStockExhaustionBlocksBuilding() {
        var s = game()
        // 32 evin tamamı tahtada: 8 arsa × 4 ev
        own(&s, [4, 7, 9, 11, 12, 14, 17, 18], by: 1, level: 4)
        own(&s, [1, 2], by: 0)
        XCTAssertEqual(s.housesLeft, 0)
        XCTAssertEqual(s.buildCheck(1, player: 0), .notAllowed(.noStock))
    }

    func testScarceHousesAreAuctionedBetweenEligibleBuilders() throws {
        var s = game()
        own(&s, [4, 7, 9, 11, 12, 14], by: 2, level: 4)     // 24 ev
        own(&s, [17, 18], by: 2, level: 3)                  // 6 ev
        own(&s, [19], by: 2, level: 1)                      // 1 ev → bankada 1 ev kaldı
        own(&s, [1, 2], by: 0)
        own(&s, [36, 39], by: 1)
        XCTAssertEqual(s.housesLeft, 1)
        try s.apply(.build(1))
        guard case .auction(let a) = s.phase, a.lot == .building(hotel: false) else { return XCTFail("bina artırması bekleniyordu") }
        XCTAssertEqual(a.bidders.first, 0)
        try s.apply(.bid(500))          // 0
        try s.apply(.bid(2_100))        // 1 (en ucuz arsası 2.000)
        if case .auction(let b) = s.phase, b.bidders.contains(2) { try s.apply(.passBid) }   // 2
        try s.apply(.passBid)           // 0
        XCTAssertEqual(s.phase, .placeBuilding(player: 1, hotel: false))
        try s.apply(.placeBuilding(39))
        XCTAssertEqual(s.holdings[39]?.level, 1)
        XCTAssertEqual(s.players[1].cash, Rules.startCash - 2_100)
        XCTAssertEqual(s.phase, .awaitingRoll)
        XCTAssertEqual(s.housesLeft, 0)
    }

    func testHotelBreakdownWithoutHousesSellsGroupDown() throws {
        var s = game()
        own(&s, [4, 7, 9, 11, 12, 14, 17, 18], by: 1, level: 4)   // 32 ev tahtada
        own(&s, [1, 2], by: 0, level: 5)
        let before = s.players[0].cash
        try s.apply(.sellBuilding(1))
        XCTAssertEqual(s.holdings[1]?.level, 0)
        XCTAssertEqual(s.holdings[2]?.level, 0)
        XCTAssertEqual(s.players[0].cash, before + 10 * 250)
    }

    // MARK: İpotek

    func testMortgageAndUnmortgageWithInterest() throws {
        var s = game()
        own(&s, [39], by: 0)
        try s.apply(.mortgage(39))
        XCTAssertEqual(s.players[0].cash, Rules.startCash + 2_100)
        XCTAssertEqual(s.unmortgageCost(39), 2_310)
        try s.apply(.unmortgage(39))
        XCTAssertEqual(s.players[0].cash, Rules.startCash - 210)
        XCTAssertEqual(s.holdings[39]?.mortgaged, false)
    }

    func testTradeOfMortgagedDeedChargesInterestOrLiftsMortgage() throws {
        var s = game()
        own(&s, [39], by: 0, mortgaged: true)
        own(&s, [36], by: 0, mortgaged: true)
        let offer = TradeOffer(from: 0, to: 1, cashTo: 1_000, squaresFrom: [39, 36], unmortgageNow: [36])
        try s.apply(.trade(offer))
        XCTAssertEqual(s.owner(of: 39), 1)
        XCTAssertEqual(s.holdings[39]?.mortgaged, true)
        XCTAssertEqual(s.holdings[36]?.mortgaged, false)
        XCTAssertEqual(s.players[0].cash, Rules.startCash + 1_000)
        // 39: 210 faiz · 36: 1.800 ipotek + 180 faiz
        XCTAssertEqual(s.players[1].cash, Rules.startCash - 1_000 - 210 - 1_980)
    }

    func testTradeRejectsDeedsFromGroupsWithBuildings() {
        var s = game()
        own(&s, [1, 2], by: 0, level: 1)
        XCTAssertThrowsError(try s.apply(.trade(TradeOffer(from: 0, to: 1, squaresFrom: [1])))) {
            XCTAssertEqual($0 as? RuleError, .notAllowed(.hasBuildings))
        }
    }

    func testJailCardCanBeTraded() throws {
        var s = game()
        s.chanceDeck.removeAll { $0 == "s12" }
        s.players[0].jailCards = ["s12"]
        try s.apply(.trade(TradeOffer(from: 0, to: 1, cashTo: 300, jailCardsFrom: 1)))
        XCTAssertEqual(s.players[1].jailCards, ["s12"])
        XCTAssertEqual(s.players[0].cash, Rules.startCash + 300)
    }

    // MARK: Nezarethane

    func testGoToJailSquareEndsMoveWithoutSalary() throws {
        var s = game()
        s.players[0].position = 28
        s.scriptedDice = [1, 1]         // 30: Nezarethaneye Git (çift olsa da tekrar atış yok)
        try s.apply(.roll)
        XCTAssertTrue(s.players[0].inJail)
        XCTAssertEqual(s.players[0].cash, Rules.startCash)
        XCTAssertEqual(s.phase, .manage)
    }

    func testJailExitByFineCardAndDoubles() throws {
        var s = game()
        own(&s, Array(0..<40).filter { Board.squares[$0].isOwnable }, by: 0)
        s.players[0].position = Board.jailIndex; s.players[0].inJail = true
        s.phase = .jailDecision
        var fine = s
        try fine.apply(.payJailFine)
        XCTAssertFalse(fine.players[0].inJail)
        XCTAssertEqual(fine.players[0].cash, Rules.startCash - Rules.jailFine)
        XCTAssertEqual(fine.phase, .awaitingRoll)

        var card = s
        card.communityDeck.removeAll { $0 == "k14" }
        card.players[0].jailCards = ["k14"]
        try card.apply(.useJailCard)
        XCTAssertFalse(card.players[0].inJail)
        XCTAssertEqual(card.communityDeck.last, "k14", "kart destenin altına döner")

        var dbl = s
        dbl.scriptedDice = [2, 2]
        try dbl.apply(.roll)
        XCTAssertFalse(dbl.players[0].inJail)
        XCTAssertEqual(dbl.players[0].position, 14)
        XCTAssertEqual(dbl.phase, .manage, "çiftle çıkan yeniden zar atmaz")
    }

    func testThirdFailedJailRollForcesFineThenMoves() throws {
        var s = game()
        own(&s, Array(0..<40).filter { Board.squares[$0].isOwnable }, by: 0)
        s.players[0].position = Board.jailIndex; s.players[0].inJail = true; s.players[0].jailRolls = 2
        s.phase = .jailDecision
        s.scriptedDice = [1, 2]
        try s.apply(.roll)
        XCTAssertFalse(s.players[0].inJail)
        XCTAssertEqual(s.players[0].position, 13)
        XCTAssertEqual(s.players[0].cash, Rules.startCash - Rules.jailFine)
    }

    // MARK: Kartlar

    func testEveryCardEffect() throws {
        for card in Cards.all {
            var s = game()
            own(&s, [1, 2], by: 0, level: 2)
            s.players[0].position = card.deck == .chance ? 6 : 3
            s.lastDice = [1, 2]
            if card.effect == .jailFree {
                s.chanceDeck.removeAll { $0 == card.id }; s.communityDeck.removeAll { $0 == card.id }
            }
            s.phase = .card(id: card.id)
            let pos = s.players[0].position
            try s.apply(.acknowledgeCard)
            let p = s.players[0]
            switch card.effect {
            case .collect(let a): XCTAssertEqual(p.cash, Rules.startCash + a, card.id)
            case .pay(let a): XCTAssertEqual(p.cash, Rules.startCash - a, card.id)
            case .collectFromEach(let a):
                XCTAssertEqual(p.cash, Rules.startCash + 2 * a, card.id)
                XCTAssertEqual(s.players[1].cash, Rules.startCash - a, card.id)
            case .payEach(let a):
                XCTAssertEqual(p.cash, Rules.startCash - 2 * a, card.id)
                XCTAssertEqual(s.players[2].cash, Rules.startCash + a, card.id)
            case .moveTo(let t):
                XCTAssertEqual(p.position, t, card.id)
                if t < pos { XCTAssertEqual(p.cash, Rules.startCash + Rules.salary, card.id) }
            case .moveBack(let n): XCTAssertEqual(p.position, pos - n, card.id)
            case .nearestTransport: XCTAssertEqual(p.position, 15, card.id)
            case .nearestUtility: XCTAssertEqual(p.position, 13, card.id)
            case .goToJail: XCTAssertTrue(p.inJail, card.id)
            case .jailFree: XCTAssertEqual(p.jailCards, [card.id])
            case .repairs(let h, _): XCTAssertEqual(p.cash, Rules.startCash - 4 * h, card.id)
            }
            XCTAssertNoThrow(try SaveCodec.validate(s), card.id)
        }
    }

    func testNearestTransportCardChargesDoubleRent() throws {
        var s = game()
        own(&s, [15], by: 1)
        s.players[0].position = 6
        s.lastDice = [2, 4]
        s.phase = .card(id: "s07")
        try s.apply(.acknowledgeCard)
        XCTAssertEqual(s.players[0].cash, Rules.startCash - 500)
        XCTAssertEqual(s.players[1].cash, Rules.startCash + 500)
    }

    func testDrawnCardGoesToBottomOfDeck() throws {
        var s = game()
        s.chanceDeck = ["s13"] + s.chanceDeck.filter { $0 != "s13" }
        s.scriptedDice = [2, 4]         // 6: Şans
        try s.apply(.roll)
        XCTAssertEqual(s.phase, .card(id: "s13"))
        XCTAssertEqual(s.chanceDeck.last, "s13")
        XCTAssertEqual(s.chanceDeck.count, 16)
    }

    // MARK: Borç ve iflas

    func testDebtMustBeRaisedBeforeBankruptcyIsAllowed() throws {
        var s = game()
        own(&s, [39], by: 1, level: 5)
        own(&s, [36], by: 1, level: 5)
        own(&s, [1], by: 0)
        s.players[0].cash = 100
        s.players[0].position = 36
        s.scriptedDice = [1, 2]         // 39: otel kirası 17.700 değil; tabloya göre
        try s.apply(.roll)
        guard case .debt(let pay) = s.phase else { return XCTFail("borç aşaması bekleniyordu") }
        XCTAssertEqual(pay.to, .player(1))
        XCTAssertEqual(pay.amount, Board.squares[39].rents[5])
        XCTAssertThrowsError(try s.apply(.settleDebt))
        XCTAssertThrowsError(try s.apply(.endTurn))
        let money = totalCash(s)
        try s.apply(.declareBankruptcy)
        XCTAssertTrue(s.players[0].bankrupt)
        XCTAssertEqual(s.owner(of: 1), 1, "tapular alacaklıya geçer")
        XCTAssertEqual(totalCash(s), money, "oyuncuya iflasta para yok olmaz")
        XCTAssertEqual(s.current, 1)
    }

    func testBankruptcyRefusedWhileAssetsCoverDebt() throws {
        var s = game()
        own(&s, [39], by: 0)
        s.players[0].cash = 100
        s.players[0].position = 5
        s.scriptedDice = [1, 2]         // 8: Gelir Vergisi 2.000
        try s.apply(.roll)
        XCTAssertThrowsError(try s.apply(.declareBankruptcy)) { XCTAssertEqual($0 as? RuleError, .notAllowed(.canStillPay)) }
        try s.apply(.mortgage(39))
        try s.apply(.settleDebt)
        XCTAssertEqual(s.players[0].cash, 100 + 2_100 - 2_000)
        XCTAssertEqual(s.phase, .manage)
    }

    func testBankruptcyToBankAuctionsDeedsUnmortgaged() throws {
        var s = game()
        own(&s, [1], by: 0, mortgaged: true)
        s.players[0].cash = 0
        s.players[0].position = 5
        s.scriptedDice = [1, 2]
        try s.apply(.roll)
        try s.apply(.declareBankruptcy)
        XCTAssertTrue(s.players[0].bankrupt)
        guard case .auction(let a) = s.phase else { return XCTFail("banka artırması bekleniyordu") }
        XCTAssertEqual(a.lot, .property(1))
        XCTAssertEqual(a.bidders, [1, 2])
        try s.apply(.bid(50))
        try s.apply(.passBid)
        XCTAssertEqual(s.holdings[1], Holding(owner: 1, level: 0, mortgaged: false))
        XCTAssertEqual(s.current, 1)
        XCTAssertEqual(s.phase, .awaitingRoll)
    }

    func testCreditorPaysInterestOnInheritedMortgagedDeeds() throws {
        var s = game()
        own(&s, [39], by: 1, level: 5)
        own(&s, [36], by: 1, level: 5)
        own(&s, [34], by: 0, mortgaged: true)
        s.players[0].cash = 0
        s.players[0].position = 36
        s.scriptedDice = [1, 2]
        try s.apply(.roll)
        try s.apply(.declareBankruptcy)
        XCTAssertEqual(s.owner(of: 34), 1)
        XCTAssertEqual(s.players[1].cash, Rules.startCash - 160)
    }

    func testLastPlayerStandingWins() throws {
        var s = game(2)
        own(&s, [39, 36], by: 1, level: 5)
        s.players[0].cash = 0
        s.players[0].position = 36
        s.scriptedDice = [1, 2]
        try s.apply(.roll)
        try s.apply(.declareBankruptcy)
        XCTAssertEqual(s.phase, .gameOver(winner: 1))
        XCTAssertThrowsError(try s.apply(.roll))
    }

    // MARK: Atomiklik, kayıt, tema

    func testFailedActionLeavesStateUntouched() {
        var s = game()
        let before = s
        XCTAssertThrowsError(try s.apply(.buy))
        XCTAssertThrowsError(try s.apply(.build(1)))
        XCTAssertEqual(s, before)
    }

    func testSaveRoundTripAndVersionChecks() throws {
        var s = game(4, seed: 99)
        try s.apply(.roll)
        let data = try SaveCodec.encode(s, themeID: "istanbul")
        let file = try SaveCodec.decode(data)
        XCTAssertEqual(file.state, s)
        XCTAssertEqual(file.themeID, "istanbul")

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["schemaVersion"] = 99
        let newer = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try SaveCodec.decode(newer)) {
            XCTAssertEqual($0 as? SaveError, .unsupportedSchema(found: 99, supported: SaveCodec.schemaVersion))
        }
        XCTAssertThrowsError(try SaveCodec.decode(Data("{}".utf8)))
    }

    func testSameSeedGivesSameGame() throws {
        var a = game(3, seed: 42), b = game(3, seed: 42)
        XCTAssertEqual(a, b)
        try a.apply(.roll); try b.apply(.roll)
        XCTAssertEqual(a, b)
    }

    /// Rastgele oyunlar: değişmezler her adımda korunmalı ve oyun kilitlenmemeli.
    func testRandomPlayoutsKeepInvariants() throws {
        for seed in 1...40 {
            var s = game(2 + seed % 5, seed: UInt64(seed))
            var picker = SeededRNG(seed: UInt64(seed) &* 7919)
            var steps = 0
            while steps < 4_000 {
                if case .gameOver = s.phase { break }
                steps += 1
                let p = s.actingPlayer
                switch s.phase {
                case .awaitingRoll:
                    if let sq = s.squares(ownedBy: p).first(where: { s.buildCheck($0, player: p) == nil }), picker.int(below: 2) == 0 {
                        try s.apply(.build(sq))
                    } else { try s.apply(.roll) }
                case .jailDecision:
                    if !s.players[p].jailCards.isEmpty { try s.apply(.useJailCard) } else { try s.apply(.roll) }
                case .buyDecision(let sq):
                    if s.players[p].cash >= Board.squares[sq].price && picker.int(below: 3) > 0 { try s.apply(.buy) } else { try s.apply(.sendToAuction) }
                case .auction(let a):
                    let minBid = s.minimumBid(for: p, in: a)
                    if minBid <= s.players[p].cash && minBid < 1_500 && picker.int(below: 2) == 0 { try s.apply(.bid(minBid)) } else { try s.apply(.passBid) }
                case .card: try s.apply(.acknowledgeCard)
                case .placeBuilding(_, let hotel):
                    let site = try XCTUnwrap(s.squares(ownedBy: p).first { (s.holdings[$0]?.level == 4) == hotel && s.buildCheck($0, player: p, ignoringCash: true) == nil })
                    try s.apply(.placeBuilding(site))
                case .debt(let pay):
                    if s.players[p].cash >= pay.amount { try s.apply(.settleDebt) }
                    else if let sq = s.squares(ownedBy: p).first(where: { s.sellCheck($0, player: p) == nil }) { try s.apply(.sellBuilding(sq)) }
                    else if let sq = s.squares(ownedBy: p).first(where: { s.mortgageCheck($0, player: p) == nil }) { try s.apply(.mortgage(sq)) }
                    else { try s.apply(.declareBankruptcy) }
                case .manage: try s.apply(.endTurn)
                case .gameOver: break
                }
                XCTAssertNoThrow(try SaveCodec.validate(s), "seed \(seed) adım \(steps)")
                XCTAssertTrue(s.players.allSatisfy { $0.cash >= 0 })
                XCTAssertTrue((0...Rules.houseStock).contains(s.housesLeft) && (0...Rules.hotelStock).contains(s.hotelsLeft))
            }
        }
    }
}
