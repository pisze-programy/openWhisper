import Foundation

/// Minimal detokenizer for Parakeet TDT's BPE/SentencePiece vocab.
///
/// Reads the ``vocab`` map out of a HuggingFace ``tokenizer.json`` (which is
/// keyed on the BPE piece string and values are integer IDs). At decode time
/// we map IDs back to pieces, replace the SentencePiece whitespace marker
/// ``▁`` (U+2581) with a real space, and concatenate.
///
/// Encoding isn't implemented; we only ever use this to turn the decoder's
/// argmax stream into human-readable text.
public final class Tokenizer {
    public let idToPiece: [String]       // idToPiece[id] == piece
    public let specialIDs: Set<Int>      // ids to skip when ``skipSpecial`` is true

    /// SentencePiece whitespace marker.
    public static let metaSpace: Character = "\u{2581}"

    public init(tokenizerJSONURL url: URL) throws {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ParakeetError.tokenizerLoadFailed(url: url, underlying: error)
        }

        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ParakeetError.tokenizerLoadFailed(url: url, underlying: error)
        }

        guard let root = obj as? [String: Any],
              let model = root["model"] as? [String: Any],
              let vocab = model["vocab"] as? [String: Any]
        else {
            let e = NSError(
                domain: "ParakeetTokenizer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing model.vocab in tokenizer.json"]
            )
            throw ParakeetError.tokenizerLoadFailed(url: url, underlying: e)
        }

        // Added tokens cover IDs outside the main vocab (blank, <pad>, etc.).
        let addedTokens = (root["added_tokens"] as? [[String: Any]]) ?? []

        // Collect (piece, id) pairs.
        var pairs: [(String, Int)] = []
        pairs.reserveCapacity(vocab.count + addedTokens.count)
        for (piece, any) in vocab {
            if let n = any as? Int { pairs.append((piece, n)) }
            else if let n = any as? NSNumber { pairs.append((piece, n.intValue)) }
        }
        // Specials that extend the range (e.g. blank at id 8192).
        for tok in addedTokens {
            guard let id = tok["id"] as? Int ?? (tok["id"] as? NSNumber)?.intValue,
                  let content = tok["content"] as? String
            else { continue }
            pairs.append((content, id))
        }

        let maxID = pairs.map(\.1).max() ?? -1
        var pieces = [String](repeating: "", count: maxID + 1)
        for (p, i) in pairs where i >= 0 && i <= maxID {
            pieces[i] = p
        }
        self.idToPiece = pieces

        // Heuristic: anything in angle-brackets (``<unk>``, ``<|pnc|>``,
        // ``<blank>`` ...) is a control token and suppressed by default.
        var specials = Set<Int>()
        for (i, p) in pieces.enumerated() where p.hasPrefix("<") && p.hasSuffix(">") {
            specials.insert(i)
        }
        // Also honour explicit `special: true` flags on added tokens.
        for tok in addedTokens {
            guard let id = tok["id"] as? Int ?? (tok["id"] as? NSNumber)?.intValue
            else { continue }
            if (tok["special"] as? Bool) == true {
                specials.insert(id)
            }
        }
        self.specialIDs = specials
    }

    /// Translate token IDs into a string. Mirrors the Metaspace decoder
    /// behaviour of the HF tokenizer: ``▁`` -> space, initial space stripped.
    public func decode(_ ids: [Int], skipSpecial: Bool = true) -> String {
        var chars = [Character]()
        chars.reserveCapacity(ids.count * 3)
        for id in ids {
            guard id >= 0, id < idToPiece.count else { continue }
            if skipSpecial && specialIDs.contains(id) { continue }
            let piece = idToPiece[id]
            for ch in piece {
                chars.append(ch == Tokenizer.metaSpace ? " " : ch)
            }
        }
        // SentencePiece inserts a leading ``▁`` on the first real word.
        var text = String(chars)
        if text.hasPrefix(" ") { text.removeFirst() }
        return text
    }
}
