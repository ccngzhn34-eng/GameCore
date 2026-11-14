import Foundation

// Kural motoru. Her `apply` çağrısı atomiktir: hata olursa durum değişmez.
// Arayüz animasyonları dönen olay listesinden üretilir; motorun kendisi anlıktır.

extension GameState {
    @discardableResult
    public mutating func apply(_ action: Action) throws -> [Event] {
        var next = self
        let mark = next.log.count
        try next.perform(action)
        let events = Array(next.log[mark...])
        if next.log.count > 80 { next.log.removeFirst(next.log.count - 80) }
        next.revision += 1
        self = next
        return events
    }

    private var canManage: Bool {
        switch phase {
        case .awaitingRoll, .jailDecision, .manage, .buyDecision: return true
        default: return false
        }
    }
    private var inDebt: Bool { if case .debt = phase { return true }; return false }

    private mutating func perform(_ action: Action) throws {
        switch action {
        case .roll: try roll()
        case .payJailFine:
            guard phase == .jailDecision else { throw RuleError.wrongPhase }
            guard players[current].cash >= Rules.jailFine else { throw RuleError.insufficientFunds }
            players[current].cash -= Rules.jailFine
            log.append(.paid(from: current, to: .bank, amount: Rules.jailFine))
            release(current)
            phase = .awaitingRoll
        case .useJailCard:
            guard phase == .jailDecision else { throw RuleError.wrongPhase }
            guard !players[current].jailCards.isEmpty else { throw RuleError.notAllowed(.noJailCard) }
            returnJailCard(players[current].jailCards.removeFirst())
            release(current)
            phase = .awaitingRoll
        case .buy:
            guard case .buyDecision(let sq) = phase else { throw RuleError.wrongPhase }
            let price = Board.squares[sq].price
            guard players[current].cash >= price else { throw RuleError.insufficientFunds }
            players[current].cash -= price
            holdings[sq] = Holding(owner: current, level: 0, mortgaged: false)
            log.append(.bought(player: current, square: sq, price: price))
            settle()
        case .sendToAuction:
            guard case .buyDecision(let sq) = phase else { throw RuleError.wrongPhase }
            if !startPropertyAuction(sq) { settle() }
        case .bid(let amount): try bid(amount)
        case .passBid: try passBid()
        case .acknowledgeCard: try acknowledgeCard()
        case .build(let sq): try build(sq)
        case .sellBuilding(let sq): try sellBuilding(sq)
        case .placeBuilding(let sq): try placeBuilding(sq)
        case .mortgage(let sq):
            guard canManage || inDebt else { throw RuleError.wrongPhase }
            let p = actingPlayer
            if let e = mortgageCheck(sq, player: p) { throw e }
            holdings[sq]?.mortgaged = true
            players[p].cash += Board.squares[sq].mortgageValue
            log.append(.mortgaged(player: p, square: sq))
        case .unmortgage(let sq):
            guard canManage else { throw RuleError.wrongPhase }
            let p = actingPlayer
            guard let h = holdings[sq], h.owner == p else { throw RuleError.notOwner }
            guard h.mortgaged else { throw RuleError.notAllowed(.notMortgaged) }
            let cost = unmortgageCost(sq)
            guard players[p].cash >= cost else { throw RuleError.insufficientFunds }
            players[p].cash -= cost
            holdings[sq]?.mortgaged = false
            log.append(.unmortgaged(player: p, square: sq))
        case .trade(let offer): try trade(offer)
        case .settleDebt:
            guard case .debt(let pay) = phase else { throw RuleError.wrongPhase }
            guard players[pay.from].cash >= pay.amount else { throw RuleError.insufficientFunds }
            settle()
        case .declareBankruptcy:
            guard case .debt(let pay) = phase else { throw RuleError.wrongPhase }
            guard liquidationValue(of: pay.from) < pay.amount else { throw RuleError.notAllowed(.canStillPay) }
            goBankrupt(pay.from, to: pay.to)
            settle()
        case .endTurn:
            guard phase == .manage else { throw RuleError.wrongPhase }
            advanceTurn()
        }
    }

    // MARK: Zar ve hareket

    private mutating func rollDie() -> Int {
        if !scriptedDice.isEmpty { return scriptedDice.removeFirst() }
        return rng.int(below: 6) + 1
    }

    private mutating func roll() throws {
        let p = current
        if phase == .jailDecision {
            let d1 = rollDie(), d2 = rollDie()
            lastDice = [d1, d2]
            log.append(.rolled(player: p, d1: d1, d2: d2))
            rollAgain = false
            if d1 == d2 {
                // Çift atarak çıkan oyuncu atılan zar kadar ilerler, yeniden zar atmaz.
                release(p)
                move(by: d1 + d2)
            } else {
                players[p].jailRolls += 1
                if players[p].jailRolls >= Rules.maxJailRolls {
                    // Üçüncü başarısız denemede ceza zorunludur; ardından atılan zar kadar ilerlenir.
                    payments.append(Payment(from: p, to: .bank, amount: Rules.jailFine))
                    continuation = .moveAfterJailFine(d1: d1, d2: d2)
                    settle()
                } else {
                    phase = .manage
                }
            }
            return
        }
        guard phase == .awaitingRoll else { throw RuleError.wrongPhase }
        let d1 = rollDie(), d2 = rollDie()
        lastDice = [d1, d2]
        log.append(.rolled(player: p, d1: d1, d2: d2))
        if d1 == d2 {
            doubles += 1
            if doubles >= 3 {
                sendToJail(p)
                phase = .manage
                return
            }
            rollAgain = true
        } else {
            rollAgain = false
        }
        move(by: d1 + d2)
    }

    private mutating func move(by steps: Int) {
        let p = current
        let from = players[p].position
        let to = (from + steps) % Board.size
        players[p].position = to
        log.append(.moved(player: p, from: from, to: to, forward: true))
        if to < from { paySalary(p) }
        resolveLanding(diceTotal: steps)
    }

    private mutating func paySalary(_ p: Int) {
        players[p].cash += Rules.salary
        log.append(.salary(player: p, amount: Rules.salary))
    }

    private mutating func sendToJail(_ p: Int) {
        let from = players[p].position
        players[p].position = Board.jailIndex
        players[p].inJail = true
        players[p].jailRolls = 0
        if p == current { rollAgain = false; doubles = 0 }
        log.append(.moved(player: p, from: from, to: Board.jailIndex, forward: false))
        log.append(.jailed(player: p))
    }

    private mutating func release(_ p: Int) {
        players[p].inJail = false
        players[p].jailRolls = 0
        log.append(.released(player: p))
    }

    private mutating func returnJailCard(_ id: String) {
        guard let card = Cards.card(id) else { return }
        if card.deck == .chance { chanceDeck.append(id) } else { communityDeck.append(id) }
    }

    private mutating func resolveLanding(diceTotal: Int, transportMultiplier: Int = 1, utilityFreshRoll: Bool = false) {
        let p = current
        let sq = players[p].position
        let def = Board.squares[sq]
        switch def.kind {
        case .start, .jail, .rest:
            settle()
        case .goToJail:
            sendToJail(p)
            settle()
        case .tax(let amount):
            payments.append(Payment(from: p, to: .bank, amount: amount))
            settle()
        case .card(let deck):
            let id: String
            if deck == .chance { id = chanceDeck.removeFirst() } else { id = communityDeck.removeFirst() }
            // Hapisten çıkış kartı kullanılana kadar desteye dönmez; diğerleri en alta gider.
            if Cards.card(id)?.effect != .jailFree { returnJailCard(id) }
            log.append(.drewCard(player: p, card: id))
            phase = .card(id: id)
        case .property, .transport, .utility:
            guard let h = holdings[sq] else {
                phase = .buyDecision(square: sq)
                return
            }
            if h.owner == p || h.mortgaged {
                settle()
                return
            }
            var amount: Int
            if utilityFreshRoll, def.kind == .utility {
                let d1 = rollDie(), d2 = rollDie()
                lastDice = [d1, d2]
                log.append(.rolled(player: p, d1: d1, d2: d2))
                amount = rent(for: sq, diceTotal: d1 + d2, utilityMultiplier: Rules.utilityBoth)
            } else {
                amount = rent(for: sq, diceTotal: diceTotal, transportMultiplier: transportMultiplier)
            }
            amount = max(0, amount)
            // Dijital uyarlama: kira, sahibinin talebi beklenmeden otomatik tahsil edilir.
            if amount > 0 { payments.append(Payment(from: p, to: .player(h.owner), amount: amount)) }
            settle()
        }
    }

    // MARK: Kartlar

    private mutating func acknowledgeCard() throws {
        guard case .card(let id) = phase, let card = Cards.card(id) else { throw RuleError.wrongPhase }
        let p = current
        let dice = lastDice.reduce(0, +)
        switch card.effect {
        case .collect(let a):
            players[p].cash += a
            log.append(.received(player: p, amount: a))
            settle()
        case .pay(let a):
            payments.append(Payment(from: p, to: .bank, amount: a))
            settle()
        case .collectFromEach(let a):
            for other in activePlayers where other != p { payments.append(Payment(from: other, to: .player(p), amount: a)) }
            settle()
        case .payEach(let a):
            for other in activePlayers where other != p { payments.append(Payment(from: p, to: .player(other), amount: a)) }
            settle()
        case .moveTo(let target):
            jump(p, to: target, forward: true)
            resolveLanding(diceTotal: dice)
        case .moveBack(let n):
            jump(p, to: (players[p].position - n + Board.size) % Board.size, forward: false)
            resolveLanding(diceTotal: dice)
        case .nearestTransport(let mult):
            jump(p, to: nearest(Board.transports, after: players[p].position), forward: true)
            resolveLanding(diceTotal: dice, transportMultiplier: mult)
        case .nearestUtility:
            jump(p, to: nearest(Board.utilities, after: players[p].position), forward: true)
            resolveLanding(diceTotal: dice, utilityFreshRoll: true)
        case .goToJail:
            sendToJail(p)
            settle()
        case .jailFree:
            players[p].jailCards.append(id)
            settle()
        case .repairs(let perHouse, let perHotel):
            var total = 0
            for (_, h) in holdings where h.owner == p { total += h.level == 5 ? perHotel : h.level * perHouse }
            if total > 0 { payments.append(Payment(from: p, to: .bank, amount: total)) }
            settle()
        }
    }

    private func nearest(_ targets: [Int], after position: Int) -> Int {
        targets.first { $0 > position } ?? targets[0]
    }

    private mutating func jump(_ p: Int, to target: Int, forward: Bool) {
        let from = players[p].position
        players[p].position = target
        log.append(.moved(player: p, from: from, to: target, forward: forward))
        if forward && target < from { paySalary(p) }
    }

    // MARK: Ödemeler, borç, sıra

    /// Bekleyen ödemeleri, banka artırmalarını ve hamle sonunu sırayla çözer.
    private mutating func settle() {
        if declareWinnerIfAlone() { return }
        while let pay = payments.first {
            if players[pay.from].bankrupt { payments.removeFirst(); continue }
            if case .player(let c) = pay.to, players[c].bankrupt { payments.removeFirst(); continue }
            guard players[pay.from].cash >= pay.amount else {
                phase = .debt(pay)
                return
            }
            payments.removeFirst()
            players[pay.from].cash -= pay.amount
            if case .player(let c) = pay.to { players[c].cash += pay.amount }
            log.append(.paid(from: pay.from, to: pay.to, amount: pay.amount))
        }
        while !auctionQueue.isEmpty {
            let sq = auctionQueue.removeFirst()
            if startPropertyAuction(sq) { return }
        }
        switch continuation {
        case .moveAfterJailFine(let d1, let d2):
            continuation = .endOfMove
            if !players[current].bankrupt {
                release(current)
                move(by: d1 + d2)
                return
            }
            finishMove()
        case .endOfMove:
            finishMove()
        }
    }

    private mutating func declareWinnerIfAlone() -> Bool {
        let alive = activePlayers
        guard alive.count == 1 else { return false }
        payments.removeAll()
        auctionQueue.removeAll()
        phase = .gameOver(winner: alive[0])
        log.append(.won(player: alive[0]))
        return true
    }

    private mutating func finishMove() {
        let p = players[current]
        if p.bankrupt {
            advanceTurn()
        } else if rollAgain && !p.inJail {
            phase = .awaitingRoll
        } else {
            rollAgain = false
            phase = .manage
        }
    }

    private mutating func advanceTurn() {
        doubles = 0
        rollAgain = false
        continuation = .endOfMove
        var next = current
        repeat { next = (next + 1) % players.count } while players[next].bankrupt
        current = next
        turn += 1
        phase = players[next].inJail ? .jailDecision : .awaitingRoll
        log.append(.turnStarted(player: next))
    }

    private mutating func goBankrupt(_ p: Int, to creditor: Creditor) {
        // Binalar yarı fiyatına bankaya döner.
        for sq in squares(ownedBy: p) {
            if let h = holdings[sq], h.level > 0 {
                players[p].cash += h.level * Board.squares[sq].houseCost / 2
                holdings[sq]?.level = 0
            }
        }
        var receiver: Int? = nil
        if case .player(let c) = creditor, !players[c].bankrupt { receiver = c }
        if let c = receiver {
            players[c].cash += players[p].cash
            for sq in squares(ownedBy: p) {
                holdings[sq]?.owner = c
                // İpotekli tapuyu devralan, faizi (%10) hemen öder.
                if holdings[sq]?.mortgaged == true {
                    payments.append(Payment(from: c, to: .bank, amount: Rules.mortgageInterest(Board.squares[sq].mortgageValue)))
                }
            }
            players[c].jailCards += players[p].jailCards
        } else {
            // Bankaya iflas: tapular ipoteksiz olarak açık artırmaya çıkar.
            for sq in squares(ownedBy: p) {
                holdings[sq] = nil
                auctionQueue.append(sq)
            }
            for card in players[p].jailCards { returnJailCard(card) }
        }
        players[p].jailCards = []
        players[p].cash = 0
        players[p].inJail = false
        players[p].bankrupt = true
        payments.removeAll { $0.from == p || $0.to == .player(p) }
        if p == current { rollAgain = false }
        log.append(.bankrupt(player: p, to: creditor))
    }

    // MARK: Açık artırma

    /// Sıradaki oyuncudan başlayarak teklif verebilecek herkesi artırmaya alır.
    private func biddingOrder(_ eligible: (Int) -> Bool, startingAfter start: Int) -> [Int] {
        (1...players.count).map { (start + $0) % players.count }.filter { !players[$0].bankrupt && eligible($0) }
    }

    private mutating func startPropertyAuction(_ sq: Int) -> Bool {
        let bidders = biddingOrder({ players[$0].cash >= Rules.minBid }, startingAfter: current)
        guard !bidders.isEmpty else {
            log.append(.auctionNoSale(lot: .property(sq)))
            return false
        }
        phase = .auction(Auction(lot: .property(sq), highBid: 0, highBidder: nil, bidders: bidders, turn: 0))
        log.append(.auctionStarted(lot: .property(sq)))
        return true
    }

    private mutating func bid(_ amount: Int) throws {
        guard case .auction(var a) = phase else { throw RuleError.wrongPhase }
        let p = a.currentBidder
        guard amount >= minimumBid(for: p, in: a) else { throw RuleError.notAllowed(.bidTooLow) }
        guard amount <= players[p].cash else { throw RuleError.insufficientFunds }
        a.highBid = amount
        a.highBidder = p
        if a.bidders.count == 1 {
            concludeAuction(a)
        } else {
            a.turn = (a.turn + 1) % a.bidders.count
            phase = .auction(a)
        }
    }

    private mutating func passBid() throws {
        guard case .auction(var a) = phase else { throw RuleError.wrongPhase }
        a.bidders.remove(at: a.turn)
        if a.turn >= a.bidders.count { a.turn = 0 }
        if a.bidders.isEmpty || (a.bidders.count == 1 && a.highBidder == a.bidders[0]) {
            concludeAuction(a)
        } else {
            phase = .auction(a)
        }
    }

    private mutating func concludeAuction(_ a: Auction) {
        guard let winner = a.highBidder else {
            log.append(.auctionNoSale(lot: a.lot))
            afterAuction(a.lot)
            return
        }
        players[winner].cash -= a.highBid
        log.append(.auctionWon(player: winner, lot: a.lot, bid: a.highBid))
        switch a.lot {
        case .property(let sq):
            holdings[sq] = Holding(owner: winner, level: 0, mortgaged: false)
            afterAuction(a.lot)
        case .building(let hotel):
            phase = .placeBuilding(player: winner, hotel: hotel)
        }
    }

    private mutating func afterAuction(_ lot: Lot) {
        switch lot {
        case .property: settle()
        case .building:
            phase = resumePhase ?? .manage
            resumePhase = nil
        }
    }

    // MARK: Bina

    private mutating func build(_ sq: Int) throws {
        guard canManage else { throw RuleError.wrongPhase }
        let p = actingPlayer
        if let e = buildCheck(sq, player: p) { throw e }
        let hotel = holdings[sq]?.level == 4
        // Kıtlık: banka stoğu, bu binayı kurabilecek herkese birer tane yetmiyorsa bina açık artırmayla satılır.
        let rivals = activePlayers.filter { $0 != p && cheapestSite(for: $0, hotel: hotel, requireCash: true) != nil }
        let stock = hotel ? hotelsLeft : housesLeft
        if !rivals.isEmpty && stock < rivals.count + 1 {
            let eligible = Set(rivals + [p])
            let bidders = biddingOrder({ eligible.contains($0) }, startingAfter: (p + players.count - 1) % players.count)
            resumePhase = phase
            phase = .auction(Auction(lot: .building(hotel: hotel), highBid: 0, highBidder: nil, bidders: bidders, turn: 0))
            log.append(.auctionStarted(lot: .building(hotel: hotel)))
            return
        }
        players[p].cash -= Board.squares[sq].houseCost
        raise(sq, by: p)
    }

    private mutating func raise(_ sq: Int, by p: Int) {
        let level = (holdings[sq]?.level ?? 0) + 1
        holdings[sq]?.level = level
        log.append(.built(player: p, square: sq, level: level))
    }

    private mutating func placeBuilding(_ sq: Int) throws {
        guard case .placeBuilding(let p, let hotel) = phase else { throw RuleError.wrongPhase }
        if let e = buildCheck(sq, player: p, ignoringCash: true) { throw e }
        guard (holdings[sq]?.level == 4) == hotel else { throw RuleError.notAllowed(.invalidSite) }
        raise(sq, by: p)
        phase = resumePhase ?? .manage
        resumePhase = nil
    }

    private mutating func sellBuilding(_ sq: Int) throws {
        guard canManage || inDebt else { throw RuleError.wrongPhase }
        let p = actingPlayer
        if let e = sellCheck(sq, player: p) { throw e }
        let def = Board.squares[sq]
        guard let level = holdings[sq]?.level, let g = def.group else { return }
        if level == 5 && housesLeft < 4 {
            // Otel bozulurken bankada 4 ev yoksa grup, stoğun yettiği en yüksek dengeli düzeye kadar satılır.
            let lots = Board.indices(ofGroup: g)
            let levels = lots.map { holdings[$0]?.level ?? 0 }
            let usedNow = levels.filter { $0 < 5 }.reduce(0, +)
            var target = 0
            for candidate in stride(from: 4, through: 0, by: -1) {
                let needed = levels.map { min($0, candidate) }.reduce(0, +)
                if needed - usedNow <= housesLeft { target = candidate; break }
            }
            for (i, lot) in lots.enumerated() where levels[i] > target {
                players[p].cash += (levels[i] - target) * def.houseCost / 2
                holdings[lot]?.level = target
                log.append(.soldBuilding(player: p, square: lot, level: target))
            }
            return
        }
        holdings[sq]?.level = level - 1
        players[p].cash += def.houseCost / 2
        log.append(.soldBuilding(player: p, square: sq, level: level - 1))
    }

    // MARK: Takas

    /// İpotekli tapuları devralanın ödeyeceği tutar: her biri için %10 faiz, hemen kaldırılacaksa ayrıca ipotek değeri.
    public func mortgageDue(_ squares: [Int], unmortgageNow: [Int]) -> Int {
        var total = 0
        for sq in squares where holdings[sq]?.mortgaged == true {
            let m = Board.squares[sq].mortgageValue
            total += Rules.mortgageInterest(m) + (unmortgageNow.contains(sq) ? m : 0)
        }
        return total
    }

    private mutating func trade(_ o: TradeOffer) throws {
        guard canManage || inDebt else { throw RuleError.wrongPhase }
        let bad = RuleError.notAllowed(.invalidTrade)
        guard o.from == actingPlayer, o.to != o.from, players.indices.contains(o.to), !players[o.to].bankrupt else { throw bad }
        guard o.cashFrom >= 0, o.cashTo >= 0, o.jailCardsFrom >= 0, o.jailCardsTo >= 0 else { throw bad }
        guard !(o.cashFrom == 0 && o.cashTo == 0 && o.squaresFrom.isEmpty && o.squaresTo.isEmpty && o.jailCardsFrom == 0 && o.jailCardsTo == 0) else { throw bad }
        guard Set(o.squaresFrom).count == o.squaresFrom.count, Set(o.squaresTo).count == o.squaresTo.count else { throw bad }
        guard o.squaresFrom.allSatisfy({ holdings[$0]?.owner == o.from }), o.squaresTo.allSatisfy({ holdings[$0]?.owner == o.to }) else { throw RuleError.notOwner }
        // Grubunda bina bulunan tapu takas edilemez; önce binalar satılmalıdır.
        for sq in o.squaresFrom + o.squaresTo {
            if let g = Board.squares[sq].group, groupLevels(g).contains(where: { $0 > 0 }) { throw RuleError.notAllowed(.hasBuildings) }
        }
        guard players[o.from].jailCards.count >= o.jailCardsFrom, players[o.to].jailCards.count >= o.jailCardsTo else { throw bad }
        guard players[o.from].cash >= o.cashFrom, players[o.to].cash >= o.cashTo else { throw RuleError.insufficientFunds }

        let dueTo = mortgageDue(o.squaresFrom, unmortgageNow: o.unmortgageNow)      // teklifi alan öder
        let dueFrom = mortgageDue(o.squaresTo, unmortgageNow: o.unmortgageNow)      // teklifi veren öder
        guard players[o.from].cash - o.cashFrom + o.cashTo >= dueFrom,
              players[o.to].cash - o.cashTo + o.cashFrom >= dueTo else { throw RuleError.insufficientFunds }

        players[o.from].cash += o.cashTo - o.cashFrom - dueFrom
        players[o.to].cash += o.cashFrom - o.cashTo - dueTo
        for sq in o.squaresFrom { holdings[sq]?.owner = o.to }
        for sq in o.squaresTo { holdings[sq]?.owner = o.from }
        for sq in o.squaresFrom + o.squaresTo where o.unmortgageNow.contains(sq) { holdings[sq]?.mortgaged = false }
        for _ in 0..<o.jailCardsFrom { players[o.to].jailCards.append(players[o.from].jailCards.removeFirst()) }
        for _ in 0..<o.jailCardsTo { players[o.from].jailCards.append(players[o.to].jailCards.removeFirst()) }
        log.append(.traded(from: o.from, to: o.to))
    }
}
