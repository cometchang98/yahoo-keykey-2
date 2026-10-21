import XCTest
@testable import KeyKeyEngine

// 智慧注音: whole sentences of 注音, walked by the language model.
final class SmartZhuyinEngineTests: XCTestCase {
    // 你好 is a phrase of its own; 是 and 事 share ㄕˋ so a tone-aware walk has a real choice.
    private let lm = """
    ㄋㄧˇ 你 -3.0
    ㄋㄧˇ 妳 -5.0
    ㄏㄠˇ 好 -3.0
    ㄋㄧˇ-ㄏㄠˇ 你好 -2.0
    ㄕˋ 是 -2.5
    ㄕˋ 事 -3.5
    ㄨㄛˇ 我 -2.0
    ㄨㄛˇ-ㄕˋ 我是 -2.0
    """

    private func engine(layout: ZhuyinKeyboardLayout = .hsu) -> SmartZhuyinEngine {
        SmartZhuyinEngine(index: TonelessLanguageModelIndex(text: lm, keepTones: true), layout: layout)
    }

    private func type(_ keys: String, into e: SmartZhuyinEngine) {
        for key in keys { _ = e.handleKey(key) }
    }

    func testASentenceIsChosenWithoutPickingAnyCharacter() {
        let e = engine()
        type("nefhwf", into: e)                    // ㄋㄧˇ ㄏㄠˇ on 許氏
        XCTAssertEqual(e.composingText, "你好")
    }

    func testAToneEndsEachSyllableSoTheSentenceGrows() {
        let e = engine()
        type("nef", into: e)
        XCTAssertEqual(e.composingText, "你")
        type("hw", into: e)                        // ㄏㄠ still unfinished: shown as 注音
        XCTAssertEqual(e.composingText, "你ㄏㄠ")
        type("f", into: e)
        XCTAssertEqual(e.composingText, "你好")
    }

    func testSpaceIsTheFirstToneAndFinishesASyllable() {
        let lm = "ㄇ 媽 -3.0\nㄇㄚ 媽 -3.0"
        let e = SmartZhuyinEngine(index: TonelessLanguageModelIndex(text: lm, keepTones: true), layout: .hsu)
        type("mm", into: e)                        // ㄇ then… a lone second m is ㄢ: ㄇㄢ
        XCTAssertTrue(e.applyFirstTone())
        XCTAssertFalse(e.applyFirstTone(), "nothing left to finish")
    }

    func testTonesDecideBetweenReadings() {
        let e = engine()
        type("cj", into: e)                        // ㄕˋ
        XCTAssertEqual(e.candidates, ["是", "事"])
        e.selectCandidate(1)
        XCTAssertEqual(e.composingText, "事")
    }

    func testPhraseBeatsItsCharacters() {
        let e = engine()
        type("xhfcj", into: e)                     // ㄨㄛˇ ㄕˋ
        XCTAssertEqual(e.composingText, "我是")
        XCTAssertEqual(e.cursorReading, "ㄨㄛˇ ㄕˋ")
    }

    func testBackspaceReopensTheLastToneThenTheSyllable() {
        let e = engine()
        type("nefhwf", into: e)
        e.backspace()                              // takes the tone back off ㄏㄠˇ
        XCTAssertEqual(e.composingText, "你ㄏㄠ")
        e.backspace()                              // ㄏㄠ → the key `h` alone, which 許氏 reads as ㄛ
        XCTAssertEqual(e.composingText, "你ㄛ")
        e.backspace()
        XCTAssertEqual(e.composingText, "你")
    }

    func testCommitReturnsTheSentenceAndClears() {
        let e = engine()
        type("nefhwf", into: e)
        XCTAssertEqual(e.commit(), "你好")
        XCTAssertEqual(e.composingText, "")
    }

    func testAKeyOutsideTheLayoutIsNotConsumed() {
        let e = engine()
        XCTAssertFalse(e.handleKey("q"))
        XCTAssertFalse(e.handleKey("1"))
    }

    func testAnUnknownReadingStaysVisibleAsZhuyin() {
        let e = engine()
        type("bj", into: e)                        // ㄅˋ — not in this model
        XCTAssertEqual(e.composingText, "ㄅˋ")
    }

    func testDachenWorksToo() {
        let e = engine(layout: .dachen)
        type("su3cl3", into: e)                    // ㄋㄧˇ ㄏㄠˇ → s u 3 / c l 3
        XCTAssertEqual(e.composingText, "你好")
    }

    func testTheCursorWordIsMarkedOnlyOnceTheUserMovesBackOntoIt() {
        let e = engine()
        type("nefhwf", into: e)                    // 你好 — a single word on this small model
        XCTAssertEqual(e.segments, [ComposingSegment(text: "你好", isCursor: false)],
                       "typing at the end marks nothing")
        let e2 = engine()
        type("xhfcj", into: e2)
        e2.selectCandidate(0)
        type("cj", into: e2)                       // 我是 + 是: two words
        XCTAssertTrue(e2.moveCursorLeft())
        XCTAssertEqual(e2.segments.filter(\.isCursor).count, 1)
        XCTAssertEqual(e2.segments.firstIndex(where: \.isCursor), 0)
        type("cj", into: e2)                       // typing again returns to the end
        XCTAssertTrue(e2.segments.allSatisfy { !$0.isCursor })
    }
}
