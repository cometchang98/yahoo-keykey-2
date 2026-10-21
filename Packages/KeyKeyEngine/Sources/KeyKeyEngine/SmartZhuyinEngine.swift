import Foundation

/// 智慧注音: type a whole sentence of 注音 and let the language model pick the characters.
///
/// The classic Yahoo! KeyKey 好打注音 behaviour, as opposed to the one-character-at-a-time ㄅ半
/// (`ZhuyinEngine`). Keys go through the same keyboard layout as ㄅ半 — including 許氏, whose keys
/// need a syllable's neighbours to be read — and a tone (or Space, the first tone) ends each
/// syllable. The finished readings are walked as a whole, exactly as `PinyinEngine` walks its
/// syllables, so 你好 comes out from `ㄋㄧˇ ㄏㄠˇ` without choosing either character. Arrows move
/// between the chosen words and a digit swaps a word for another candidate.
/// One stretch of the marked text, so the controller can underline the word the cursor is on.
public struct ComposingSegment: Equatable {
    public let text: String
    public let isCursor: Bool
    public init(text: String, isCursor: Bool) { self.text = text; self.isCursor = isCursor }
}

public final class SmartZhuyinEngine {
    /// Upper bound on syllables in one composition (keeps the per-keystroke walk cheap).
    public static let maxComposingSyllables = 24

    private let layout: ZhuyinKeyboardLayout
    private let walker: Walker
    private let userRank: (Character) -> Double

    private var finished: [ZhuyinSyllable] = []   // syllables a tone has ended
    private var current = ZhuyinSyllable()        // the syllable being typed
    private var nodes: [WalkNode] = []
    private var cursor = 0                        // index into `nodes`
    // True once the user has moved the cursor off the end to revisit a word. Only then is a word
    // marked: while typing at the end the cursor is the end, and marking the last word is noise.
    private var browsing = false

    /// `index` must be built with `keepTones: true`: its keys are full readings (ㄋㄧˇ-ㄏㄠˇ).
    public init(index: TonelessLanguageModelIndex, layout: ZhuyinKeyboardLayout,
                userRank: @escaping (Character) -> Double = { _ in 0 }) {
        self.layout = layout
        self.walker = Walker(index: index)
        self.userRank = userRank
    }

    // MARK: Input

    @discardableResult
    public func handleKey(_ key: Character) -> Bool {
        guard let next = layout.combine(key, into: current) else { return false }
        browsing = false
        // A syllable past the cap is refused, but the key is still ours: it must not leak to the app.
        if finished.count >= Self.maxComposingSyllables, next.isComplete { return true }
        current = next
        endSyllableIfComplete()
        return true
    }

    /// Whether `key` is a 注音 key on the active layout. The controller asks before treating a
    /// digit as a candidate pick or a punctuation key as punctuation.
    public func mapsKey(_ key: Character) -> Bool { layout.claims(key) }

    /// The Space bar is the first tone — it finishes a syllable that has symbols but no tone.
    /// False when there is nothing to finish, leaving Space to commit the sentence.
    @discardableResult
    public func applyFirstTone() -> Bool {
        guard !current.isComplete, current.applyFirstTone() else { return false }
        browsing = false
        if finished.count >= Self.maxComposingSyllables { current.clear(); return true }
        endSyllableIfComplete()
        return true
    }

    public func backspace() {
        browsing = false
        if current.isEmpty {
            // Back into the last finished syllable, tone off, so it can be retyped.
            guard let last = finished.popLast() else { return }
            current = layout.backspaced(last)
        } else {
            current = layout.backspaced(current)
        }
        rewalk()
    }

    // MARK: Cursor + candidates

    /// Candidates for the word under the cursor (empty if there is none).
    public var candidates: [String] {
        guard cursor >= 0, cursor < nodes.count else { return [] }
        return nodes[cursor].candidates
    }

    /// The 注音 reading of the word under the cursor, space-joined (ㄋㄧˇ ㄏㄠˇ), or nil.
    public var cursorReading: String? {
        guard cursor >= 0, cursor < nodes.count else { return nil }
        let range = nodes[cursor].readingRange
        guard range.upperBound <= finished.count else { return nil }
        return finished[range].compactMap(\.reading).joined(separator: " ")
    }

    public func selectCandidate(_ index: Int) {
        guard cursor >= 0, cursor < nodes.count,
              index >= 0, index < nodes[cursor].candidates.count else { return }
        nodes[cursor].chosenIndex = index
    }

    @discardableResult
    public func moveCursorLeft() -> Bool {
        guard cursor > 0 else { return false }
        cursor -= 1
        browsing = true
        return true
    }

    @discardableResult
    public func moveCursorRight() -> Bool {
        guard cursor < nodes.count - 1 else { return false }
        cursor += 1
        browsing = true
        return true
    }

    // MARK: Output

    /// The sentence so far, then the 注音 of the syllable still being typed.
    public var composingText: String {
        nodes.map(\.chosenText).joined() + current.displayText
    }

    /// The marked text split into words, with the cursor's word flagged once the user has moved
    /// back onto it. The last segment is the unfinished syllable, if any.
    public var segments: [ComposingSegment] {
        var result = nodes.enumerated().map {
            ComposingSegment(text: $0.element.chosenText, isCursor: browsing && $0.offset == cursor)
        }
        if !current.isEmpty { result.append(ComposingSegment(text: current.displayText, isCursor: false)) }
        return result
    }

    @discardableResult
    public func commit() -> String {
        let text = composingText
        finished = []; current = ZhuyinSyllable(); nodes = []; cursor = 0; browsing = false
        return text
    }

    // MARK: Private

    private func endSyllableIfComplete() {
        if current.isComplete {
            finished.append(current)
            current = ZhuyinSyllable()
            // A new word may now reach back over earlier ones; follow the end of the sentence.
            cursor = Int.max
        }
        rewalk()
    }

    private func rewalk() {
        let readings = finished.compactMap(\.reading)
        nodes = walker.walk(readings: readings, rawSyllables: readings, userBonus: userRank)
        cursor = min(max(0, cursor), max(0, nodes.count - 1))
    }
}
