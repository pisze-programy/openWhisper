import Foundation

// MARK: - English

struct EnglishNumberWordParser: NumberWordNormalizer.NumberWordParser {
    let languageCode = "en"

    private static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    private static let scales: [String: Int] = [
        "hundred": 100, "thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000,
    ]

    func smallValue(_ word: String) -> Int? { Self.units[word] }
    func scaleValue(_ word: String) -> Int? { Self.scales[word] }
    func isConnector(_ text: String) -> Bool {
        text == "-" || text == "\u{2011}" || text.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
    func isParticle(_ word: String) -> Bool { word == "and" }
    func add(_ value: Int, to base: Int) -> Int { base + value }
}

// MARK: - German

struct GermanNumberWordParser: NumberWordNormalizer.NumberWordParser {
    let languageCode = "de"

    private static let units: [String: Int] = [
        "null": 0, "eins": 1, "ein": 1, "eine": 1, "zwei": 2, "drei": 3, "vier": 4,
        "fünf": 5, "fuenf": 5, "sechs": 6, "sieben": 7, "acht": 8, "neun": 9,
        "zehn": 10, "elf": 11, "zwölf": 12, "zwoelf": 12, "dreizehn": 13,
        "vierzehn": 14, "fünfzehn": 15, "fuenfzehn": 15, "sechzehn": 16,
        "siebzehn": 17, "achtzehn": 18, "neunzehn": 19,
        "zwanzig": 20, "dreißig": 30, "dreissig": 30, "vierzig": 40, "fünfzig": 50,
        "fuenfzig": 50, "sechzig": 60, "siebzig": 70, "achtzig": 80, "neunzig": 90,
    ]
    private static let scales: [String: Int] = [
        "hundert": 100, "tausend": 1_000, "million": 1_000_000, "milliarde": 1_000_000_000,
    ]
    // German builds tens+units inverted: "einundzwanzig" = 1 + 20.
    private static let invertedCompounds: Set<String> = [
        "undzwanzig", "unddreißig", "unddreissig", "undvierzig", "undfünfzig",
        "undfuenfzig", "undsechzig", "undsiebzig", "undachtzig", "undneunzig",
    ]

    func smallValue(_ word: String) -> Int? {
        if let v = Self.units[word] { return v }
        for suffix in Self.invertedCompounds {
            guard word.hasSuffix(suffix) else { continue }
            let unit = String(word.dropLast(suffix.count))
            let base = suffix.replacingOccurrences(of: "und", with: "")
            if let tens = Self.units[base], let unitValue = Self.units[unit] {
                return tens + unitValue
            }
        }
        return nil
    }
    func scaleValue(_ word: String) -> Int? { Self.scales[word] }
    func isConnector(_ text: String) -> Bool {
        text == "-" || text == "\u{2011}" || text.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
    func isParticle(_ word: String) -> Bool { word == "und" }
    func add(_ value: Int, to base: Int) -> Int { base + value }
}

// MARK: - Polish

struct PolishNumberWordParser: NumberWordNormalizer.NumberWordParser {
    let languageCode = "pl"

    private static let units: [String: Int] = [
        "zero": 0, "jeden": 1, "jedna": 1, "jedno": 1, "dwa": 2, "dwie": 2,
        "trzy": 3, "cztery": 4, "pięć": 5, "piec": 5, "sześć": 6, "szesc": 6,
        "siedem": 7, "osiem": 8, "dziewięć": 9, "dziewiec": 9,
        "dziesięć": 10, "dziesiec": 10, "jedenaście": 11, "jedenascie": 11,
        "dwanaście": 12, "dwanascie": 12, "trzynaście": 13, "trzynascie": 13,
        "czternaście": 14, "czternascie": 14, "piętnaście": 15, "pietnascie": 15,
        "szesnaście": 16, "szesnascie": 16, "siedemnaście": 17, "siedemnascie": 17,
        "osiemnaście": 18, "osiemnascie": 18, "dziewiętnaście": 19, "dziewietnascie": 19,
        "dwadzieścia": 20, "dwadziescia": 20, "trzydzieści": 30, "trzydziesci": 30,
        "czterdzieści": 40, "czterdziesci": 40, "pięćdziesiąt": 50, "piecdziesiat": 50,
        "sześćdziesiąt": 60, "szescdziesiat": 60, "siedemdziesiąt": 70, "siedemdziesiat": 70,
        "osiemdziesiąt": 80, "osiemdziesiat": 80, "dziewięćdziesiąt": 90, "dziewiecdziesiat": 90,
    ]
    private static let scales: [String: Int] = [
        "sto": 100, "dwieście": 200, "dwiescie": 200, "trzysta": 300,
        "czterysta": 400, "pięćset": 500, "piecset": 500, "sześćset": 600,
        "szescset": 600, "siedemset": 700, "osiemset": 800, "dziewięćset": 900,
        "dziewiecset": 900, "tysiąc": 1_000, "tysiac": 1_000, "tysiące": 1_000,
        "tysiace": 1_000, "tysięcy": 1_000, "tysiecy": 1_000,
        "milion": 1_000_000, "miliony": 1_000_000, "milionów": 1_000_000, "milionow": 1_000_000,
    ]

    func smallValue(_ word: String) -> Int? { Self.units[word] }
    func scaleValue(_ word: String) -> Int? { Self.scales[word] }
    func isConnector(_ text: String) -> Bool {
        text == "-" || text == "\u{2011}" || text.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
    func isParticle(_ word: String) -> Bool { false }
    func add(_ value: Int, to base: Int) -> Int { base + value }
}
