import Foundation

/// Tema = yalnızca adlar ve anlatım. Ekonomi, konumlar ve kart etkileri `Board`/`Cards` içindedir ve değişmez.
/// Bütün eşleştirmeler kalıcı kare/kart kimlikleri üzerinden yapılır.
public struct Theme: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    let names: [String: String]          // kare kimliği → ad
    let flavors: [String: String]        // kart kimliği → anlatım cümlesi
    public let transportSummary: String

    public func name(of square: SquareDef) -> String {
        if let n = names[square.id] { return n }
        switch square.kind {
        case .start: return "Başlangıç"
        case .jail: return "Nezarethane"
        case .goToJail: return "Nezarethaneye Git"
        case .rest: return "Mola"
        case .card(.chance): return "Şans"
        case .card(.community): return "Kamu Fonu"
        case .tax: return square.id == "tax1" ? "Gelir Vergisi" : "Emlak Vergisi"
        default: return square.id
        }
    }
    public func name(ofIndex index: Int) -> String { name(of: Board.squares[index]) }
    public func flavor(of card: CardDef) -> String { flavors[card.id] ?? "" }

    /// Kartın mekanik etkisi her temada aynı cümleyle, yalnızca yer adları değişerek anlatılır.
    public func effectText(of card: CardDef) -> String {
        switch card.effect {
        case .collect(let a): return "Bankadan \(Money.text(a)) al."
        case .pay(let a): return "Bankaya \(Money.text(a)) öde."
        case .collectFromEach(let a): return "Her oyuncudan \(Money.text(a)) al."
        case .payEach(let a): return "Her oyuncuya \(Money.text(a)) öde."
        case .moveTo(let i):
            return i == 0 ? "Başlangıç'a ilerle ve maaşını al." : "\(name(ofIndex: i)) karesine ilerle. Başlangıç'tan geçersen maaşını al."
        case .moveBack(let n): return "\(n) kare geri git."
        case .nearestTransport(let m): return "En yakın ulaşım karesine ilerle. Sahipsizse satın alabilirsin; sahipliyse kiranın \(m) katını öde."
        case .nearestUtility: return "En yakın kuruluşa ilerle. Sahipsizse satın alabilirsin; sahipliyse zar at ve toplamın \(Rules.utilityBoth) katını öde."
        case .goToJail: return "Doğruca nezarethaneye git. Başlangıç'tan geçme, maaş alma."
        case .jailFree: return "Nezarethaneden ücretsiz çıkış. Bu kartı kullanana ya da takas edene kadar sakla."
        case .repairs(let h, let o): return "Bakım masrafı: her ev için \(Money.text(h)), her otel için \(Money.text(o)) öde."
        }
    }

    public static func theme(id: String) -> Theme { all.first { $0.id == id } ?? istanbul }
    public static let all: [Theme] = [turkiye, istanbul, dunya]
}

public enum Money {
    public static func text(_ value: Int) -> String {
        let digits = String(abs(value))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(".") }
            out.append(ch)
        }
        return (value < 0 ? "-₺" : "₺") + out
    }
}

private let propertyIDs = (1...22).map { String(format: "p%02d", $0) }
private let chanceIDs = (1...16).map { String(format: "s%02d", $0) }
private let communityIDs = (1...16).map { String(format: "k%02d", $0) }

private func makeNames(properties: [String], transports: [String], utilities: [String], rest: String) -> [String: String] {
    precondition(properties.count == 22 && transports.count == 4 && utilities.count == 2)
    var d = Dictionary(uniqueKeysWithValues: zip(propertyIDs, properties))
    for (i, t) in transports.enumerated() { d["t\(i + 1)"] = t }
    for (i, u) in utilities.enumerated() { d["u\(i + 1)"] = u }
    d["rest"] = rest
    return d
}

private func makeFlavors(chance: [String], community: [String]) -> [String: String] {
    precondition(chance.count == 16 && community.count == 16)
    return Dictionary(uniqueKeysWithValues: Array(zip(chanceIDs, chance)) + Array(zip(communityIDs, community)))
}

extension Theme {
    public static let istanbul = Theme(
        id: "istanbul", title: "İstanbul İlçeleri", subtitle: "22 ilçe · 4 ulaşım hattı",
        names: makeNames(
            properties: ["Sultangazi", "Esenler", "Bağcılar", "Küçükçekmece", "Pendik", "Ümraniye", "Kartal", "Başakşehir",
                         "Fatih", "Eyüpsultan", "Zeytinburnu", "Ataşehir", "Üsküdar", "Maltepe", "Şişli", "Beyoğlu", "Kadıköy",
                         "Beykoz", "Adalar", "Bakırköy", "Sarıyer", "Beşiktaş"],
            transports: ["Marmaray", "Metrobüs", "Boğaz Vapuru", "Tramvay"],
            utilities: ["Elektrik İdaresi", "Su İdaresi"], rest: "Çay Molası"),
        flavors: makeFlavors(
            chance: ["Sabah ezanıyla yola çıktın, şehir daha uyanmadan turu tamamladın.", "Boğaz'a nazır bir toplantıya çağrıldın.",
                     "Finans merkezinde acil bir imza seni bekliyor.", "Anadolu yakasında yeni bir arsa gezisi var.",
                     "Kısa bir alışveriş turu için yola çıktın.", "Bilet cebinde, ilk durağa yetişmen gerek.",
                     "Trafik kilit; en yakın toplu taşımaya koşuyorsun.", "Köprü kapalı; aktarma yapacaksın.",
                     "Mahallede kesinti var, idareye uğraman gerek.", "Yanlış sokağa girdin, geri dönüyorsun.",
                     "Zabıta işyerini mühürledi, ifadeye çağrıldın.", "Tanıdık bir avukat kartını bıraktı.",
                     "Balıkçı teknene ortak çıktı, payını aldın.", "Boğaz turu işin sezonu iyi kapattı.",
                     "Köprü geçiş cezası posta kutunda.", "Kentsel dönüşüm: binaların elden geçiyor."],
            community: ["Belediye yeni dönem ödemelerini dağıtıyor.", "Eski bir tapu davası lehine sonuçlandı.", "Kira yardımı hesabına yattı.",
                        "Semt pazarındaki tezgâhın iyi kazandırdı.", "Apartman aidat fazlası iade edildi.", "Simit tezgâhından küçük bir kâr.",
                        "Yaz konserlerinden gelir payın geldi.", "Doğal gaz faturası kabarık geldi.", "Çatı aktarması masraf çıkardı.",
                        "Otopark abonmanını yeniledin.", "Mahalle iftarında herkes sana katkı yaptı.", "Komşulara tatlı ısmarladın.",
                        "Ruhsatsız tadilat şikâyeti: ifadeye gidiyorsun.", "Muhtar senin için kefil oldu.",
                        "Deprem güçlendirmesi zorunlu oldu.", "Vakıf bursu ödülü kazandın."])
        , transportSummary: "Marmaray, metrobüs, vapur, tramvay")

    public static let turkiye = Theme(
        id: "turkiye", title: "Türkiye", subtitle: "22 şehir · 4 ulaşım hattı",
        names: makeNames(
            properties: ["Kars", "Sinop", "Mardin", "Şanlıurfa", "Gaziantep", "Erzurum", "Trabzon", "Samsun",
                         "Konya", "Kayseri", "Eskişehir", "Adana", "Mersin", "Nevşehir", "Bursa", "Çanakkale", "Edirne",
                         "Antalya", "Muğla", "İzmir", "Ankara", "İstanbul"],
            transports: ["Yüksek Hızlı Tren", "Otogar", "Feribot", "Havalimanı"],
            utilities: ["Enerji Santrali", "Baraj"], rest: "Dinlenme Tesisi"),
        flavors: makeFlavors(
            chance: ["Yurt turunu tamamladın, yeni sezon başlıyor.", "Büyük şehirde bir ihale seni bekliyor.",
                     "Güneyde hasat zamanı, tarlana uğra.", "Doğuda kış festivaline davetlisin.",
                     "Batıda bir fuara katılıyorsun.", "Biletin kesildi, ilk sefere yetiş.",
                     "Yol çalışması var; en yakın terminale yönel.", "Uçuş iptal, aktarma arıyorsun.",
                     "Santralde arıza var, yerinde görmelisin.", "Yanlış sapaktan çıktın, geri dönüyorsun.",
                     "Vergi denetiminde eksik çıktı, ifadeye çağrıldın.", "Eski bir dost senin için araya girdi.",
                     "Çay hasadı beklenenden iyi geldi.", "Turizm sezonu rekor kırdı.",
                     "Otoyol geçiş ücretini unutmuşsun.", "Kış bastırdı: binalarının bakımı gerekiyor."],
            community: ["Devlet teşvik ödemeleri dağıtılıyor.", "Kooperatif kâr payını ödedi.", "Tarım desteği hesabına yattı.",
                        "Yöresel ürün fuarından gelir elde ettin.", "Sigorta prim iadesi geldi.", "El sanatları tezgâhından küçük bir kâr.",
                        "Festival gelirinden payını aldın.", "Akaryakıt zammı bütçeni sarstı.", "Sel hasarı için onarım yaptırdın.",
                        "Araç muayenesi ve bakım masrafı çıktı.", "Köy düğününde takı sana takıldı.", "Bayramda herkese ikram yaptın.",
                        "İmar izinsiz yapı tespit edildi: ifadeye gidiyorsun.", "Vali yardımcısı senin için kefil oldu.",
                        "Yapı denetimi tadilat istedi.", "Girişimcilik ödülü kazandın."])
        , transportSummary: "Yüksek hızlı tren, otogar, feribot, havalimanı")

    public static let dunya = Theme(
        id: "dunya", title: "Dünya", subtitle: "22 şehir · 4 ulaşım hattı",
        names: makeNames(
            properties: ["Hanoi", "Lima", "Kahire", "Marakeş", "Nairobi", "Mumbai", "Bangkok", "İstanbul",
                         "Meksiko", "Rio de Janeiro", "Buenos Aires", "Prag", "Lizbon", "Atina", "Roma", "Barselona", "Londra",
                         "Sidney", "Singapur", "Tokyo", "Paris", "New York"],
            transports: ["Kıtalararası Uçuş", "Ekspres Tren", "Liman", "Metro"],
            utilities: ["Güneş Enerjisi", "Su Arıtma"], rest: "Transit Salonu"),
        flavors: makeFlavors(
            chance: ["Dünya turunu tamamladın, pasaportun doldu.", "Büyük bir açılış için davetiye aldın.",
                     "Avrupa'da bir sergiye katılıyorsun.", "Güney Asya'da yeni bir ortaklık görüşmesi var.",
                     "Akdeniz'de kısa bir iş gezisi çıktı.", "Aktarma biletin hazır, ilk terminale git.",
                     "Uçuşun rötar yaptı; en yakın bağlantıya yönel.", "Grev var, başka hat arıyorsun.",
                     "Tesiste denetim günü, hazır bulunmalısın.", "Yanlış kapıya gittin, geri dönüyorsun.",
                     "Gümrükte beyan sorunu çıktı, alıkonuldun.", "Konsolosluk senin için devreye girdi.",
                     "Döviz kuru lehine döndü.", "Uluslararası fuar siparişleri patladı.",
                     "Fazla bagaj ücreti ödedin.", "Uluslararası standartlar: binaların yenileniyor."],
            community: ["Küresel fon yıllık dağıtımını yaptı.", "Uluslararası tahkim lehine sonuçlandı.", "İhracat desteği hesabına yattı.",
                        "Kültür festivali gelirinden pay aldın.", "Vize harcı iadesi geldi.", "Hediyelik eşya standından küçük bir kâr.",
                        "Telif gelirin ödendi.", "Seyahat sigortası primi yenilendi.", "Fırtına hasarını onartıyorsun.",
                        "Vize ve harç masrafları çıktı.", "Doğum günün için herkes hediye yolladı.", "Tüm ortaklara yemek ısmarladın.",
                        "Evraklarında eksik bulundu: alıkonuldun.", "Büyükelçi senin için kefil oldu.",
                        "Yeşil bina yönetmeliği tadilat istiyor.", "Uluslararası tasarım ödülü kazandın."])
        , transportSummary: "Kıtalararası uçuş, ekspres, liman, metro")
}
