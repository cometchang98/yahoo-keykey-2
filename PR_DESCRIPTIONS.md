# Draft pull request descriptions

Drafts for three branches on `cometchang98/yahoo-keykey-2`, each based so it can be
opened against `teddychan/yahoo-keykey-2` `main`. These PRs were not opened.

`upstream-pr` on the fork is unchanged.

Suggested bases:

| Branch | Base | Depends on |
|---|---|---|
| `fix/adhoc-build-runtime` | `main` | nothing |
| `feat/zhuyin-hsu-layout` | `main` | nothing |
| `feat/smart-zhuyin` | `feat/zhuyin-hsu-layout`, then retarget to `main` after that merges | the Hsu layout PR |

Both the build-fix PR and the Hsu PR add an `## Unreleased` heading to `CHANGELOG.md`.
Whichever lands second needs that heading combined. They do not otherwise touch the same files.

---

## PR: fix/adhoc-build-runtime

**Title:** Fix plain `build-app.sh` builds crashing at launch

### 摘要

一般執行 `tools/build-app.sh` 時，app 是用 ad-hoc 簽章。這個簽章如果帶著 hardened runtime，Library Validation 會拒絕同樣是 ad-hoc 的 Sparkle.framework，程式一打開就崩潰，輸入法選單也不會出現。這次讓 ad-hoc 階段不要加上 runtime。正式發行仍會用 Developer ID 重新簽名，並自己加上 `--options runtime`，所以上架的版本不受影響。

### What and why

`tools/build-app.sh` always signs ad-hoc. Until now it passed `--options runtime` for every build except `KEYKEY_DEBUG_ID=1`. An ad-hoc signature has no Team ID, so the hardened runtime's Library Validation refuses to load the equally ad-hoc `Sparkle.framework`. The process dies at launch with a dyld "different Team IDs" error, and the input method never registers its menu.

That exception used to cover only debug builds, so a plain `./tools/build-app.sh` — and anyone building from source without a Developer ID — produced a bundle that crashed immediately.

This change leaves `RUNTIME_OPT` empty for every ad-hoc signature. The notarized path is unaffected, because it does not reuse that signature:

- `tools/package-release.sh` (about lines 56–71), when `DEVELOPER_ID_APP` is set, re-signs Sparkle inside-out and then the app with `codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP"`. When the variable is unset, the script keeps the ad-hoc signature on purpose and warns that Gatekeeper will block it.
- `.github/workflows/release.yml` calls `teddychan/dragon-release-ci/.github/workflows/release-macos.yml@v6` with `build_kind: script`. That workflow's "Build the LM data + app (swiftc, ad-hoc) [script]" step runs `tools/build-app.sh`, and the following step, "Sign (Developer ID + hardened runtime) [script]", re-signs the nested Sparkle binaries, the framework, and the app with `codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY"`.

So a Developer ID release still ships with the hardened runtime. The ad-hoc stage does not need to carry it, and carrying it is what made those builds crash.

### How to test

On a Mac:

1. `./tools/build-app.sh` with `KEYKEY_DEBUG_ID` unset and `DEVELOPER_ID_APP` unset.
2. `codesign -dv --verbose=4 build/YahooKeyKey2.app` should not list the runtime flag. The same for `Sparkle.framework`.
3. Launch the app (or install it as an input method). It should get past dyld and show its menu. Previously this build died on launch.
4. With `DEVELOPER_ID_APP` set, `./tools/package-release.sh` should re-sign. `codesign -dv` on that app should show `runtime`, and `codesign --verify --strict` should pass.

`bash -n tools/build-app.sh` is clean. The script itself cannot be executed on Linux (`codesign`, the macOS SDK).

### Screenshots

Placeholder — ad-hoc build, no runtime flag, app launched:

```
codesign -dv build/YahooKeyKey2.app
# CodeDirectory v=... flags=0x2(adhoc)
# (no "runtime")
```

Placeholder — Developer ID build from `package-release.sh` or the release workflow:

```
codesign -dv build/YahooKeyKey2.app
# flags=0x10000(runtime)
# Authority=Developer ID Application: ...
```

### Dependencies

None. Independent of the 許氏 and 智慧選字 branches. The only overlap is the new `## Unreleased` block in `CHANGELOG.md`.

---

## PR: feat/zhuyin-hsu-layout

**Title:** Add the 許氏 (Hsu) keyboard for 注音

### 摘要

注音新增許氏鍵盤。這是 26 個英文字母的排列，一個鍵可以代表好幾個符號，要看旁邊的鍵才知道是哪一個（`m` 是ㄇ或ㄢ，`j` 是ㄐ、ㄓ或四聲）。空白鍵是一聲，其他聲調是 `d` ˊ、`f` ˇ、`j` ˋ、`s` ˙。可以在設定或輸入法選單裡，跟標準（大千）、倚天一起選。注音仍然一次打一個字。拆鍵規則移植自 McBopomofo（MIT）。

### What and why

許氏 is the 26-letter 注音 keyboard: one key stands for several symbols, and the keys around it decide which. `m` is ㄇ or ㄢ, `j` is ㄐ, ㄓ, or the fourth tone. Space is the first tone; the other tones are `d` ˊ, `f` ˇ, `j` ˋ, `s` ˙.

大千 and 倚天 are plain key-to-symbol maps. 許氏 is not, so the layout protocol grew four operations that 大千 and 倚天 implement as the old behaviour:

- `combine` — fold a key into the current syllable
- `claims` — whether this layout types 注音 with that key
- `isToneKey` — a tone correction rather than the next character (never on 許氏, because `d f j s` are also ㄉ ㄈ ㄐ ㄙ)
- `backspaced` — take back the last key, which for 許氏 means re-reading the remaining sequence

`ZhuyinEngine`, `ZhuyinSyllable` (a slot-wise initializer), and `ZhuyinPunctuation` (許氏 leaves punctuation on the shared table) use that protocol. The reading rules in `ZhuyinHsuLayout.swift` are a port of McBopomofo's Hsu table (`Mandarin.h` / `Mandarin.cpp`), MIT licensed, the same project this app's language model comes from. `CREDITS.md` says so.

The keyboard is selectable from 設定… ▸ 一般 and from the input menu (許氏鍵盤), next to 標準（大千） and 倚天. 注音 still types one character at a time. 智慧選字 is not in this branch. The other 26-key layouts (倚天 26 鍵, IBM) are still not offered.

### How to test

Engine tests (no Mac required for these):

```bash
swift test --package-path Packages/KeyKeyEngine -Xswiftc -warnings-as-errors
```

`ZhuyinHsuLayoutTests` spells syllables through the engine, including `nef` → ㄋㄧˇ, `hwf` → ㄏㄠˇ, `cj` → ㄕˋ, backspace, Space as the first tone, and the rule that a finished syllable yields to the next character.

On a Mac, `swift test --package-path Packages/KeyKeyApp` covers the persisted raw value `hsu` (`PreferencesTests.testZhuyinLayoutRawValues`). That package links DragonKit, which imports AppKit, so it does not build on Linux.

Then, by hand, in 注音:

1. 設定… ▸ 一般 ▸ 注音鍵盤, or the input menu, and choose 許氏. 大千 stays the default.
2. `nef` should offer 你, `hwf` 好, `cj` 是 (once the bundled ㄅ半 table is loaded).
3. Space after a symbol is the first tone. `d` `f` `j` `s` after a finished syllable start the next character; they do not rewrite the tone.
4. `,` and `.` stay punctuation. `1`–`9` pick a candidate, because those keys are not 注音 keys on 許氏.
5. Switch back to 大千 and confirm `su3` is still ㄋㄧˇ.

### Screenshots / examples

Placeholder — the picker:

```
設定… ▸ 一般 ▸ 注音鍵盤
  ○ 標準（大千）
  ○ 倚天 (ETen)
  ● 許氏 (Hsu)
```

Placeholder — marked text, one character at a time:

```
nef  →  ㄋㄧˇ  →  你
hwf  →  ㄏㄠˇ  →  好
cj   →  ㄕˋ   →  是
```

### Credit

The Hsu key-reading rules are a port of [McBopomofo](https://github.com/openvanilla/McBopomofo) `Source/Engine/Mandarin/Mandarin.h` and `Mandarin.cpp`, MIT License. Only the rules the Hsu keys can reach are carried over.

### Dependencies

None. Does not include 智慧選字 or the ad-hoc signing fix. `feat/smart-zhuyin` is stacked on this branch and should not merge first: `SmartZhuyinEngine` calls `combine` / `claims` / `backspaced`.

---

## PR: feat/smart-zhuyin

**Title:** Add 智慧選字 for 注音, off by default

**Base:** `feat/zhuyin-hsu-layout` (retarget to `main` after the Hsu PR merges)

### 摘要

注音新增智慧選字：可以整句打注音，由語言模型選字，就像原來的好打注音。預設關閉，所以現在一次打一個字的人不會被改掉，要自己在設定或輸入法選單裡打開。游標一次移動一個字，詞裡面的單字可以單獨改（太長 → 太常）。這支分支疊在許氏鍵盤之上，大千、倚天、許氏都能用。

### What and why

智慧選字 is whole-sentence 注音, the old Yahoo! KeyKey 好打注音 behaviour. You type a run of syllables, each one ended by its tone (Space for the first tone), and the language model picks the characters. `ㄋㄧˇ ㄏㄠˇ` becomes 你好 without choosing either character. It works on 大千, 倚天, and 許氏, because keys go through the same layout protocol as ㄅ半.

The cursor sits on a syllable, not on a word. The model may have joined 太長 into one word, but moving back onto 長 offers 常. The candidate list there is: the word the walk chose, then every single character for that syllable, then longer words that run through it. Picking one pins that stretch and the walk continues around it. Only the character under the cursor is underlined. Characters you pick by hand are credited to that reading's list, and so is a character you keep accepting as the default, so three accepted 是 still lead one hand-picked 氏.

It is **off by default** (`Preferences.zhuyinSmartEnabled` registers `false`). Existing users keep the one-character-at-a-time ㄅ半 until they turn it on in 設定… ▸ 一般 or the input menu (智慧選字（整句）). Nothing changes in 倉頡, 速成, or 拼音. The tone-aware index (`TonelessLanguageModelIndex` with `keepTones: true`) is held only while a controller is in 注音 with the setting on.

### How to test

Engine tests:

```bash
swift test --package-path Packages/KeyKeyEngine -Xswiftc -warnings-as-errors
```

`SmartZhuyinEngineTests` covers the sentence walk, the per-character cursor, 太長 → 太常, hand-picked characters leading next time, and accepted defaults counting as much as a pick. It does not need the real `data.txt`.

On a Mac, `swift test --package-path Packages/KeyKeyApp` should show `Preferences.zhuyinSmartEnabled` false after `registerDefaults()`, and the round trip through UserDefaults. That package does not build on Linux (DragonKit imports AppKit).

Then, by hand:

1. Fresh settings, switch to 注音. 智慧選字 should be off. Typing should still be one character at a time, on 大千 and on 許氏.
2. Turn it on. On 許氏, `nefhwf` (ㄋㄧˇ ㄏㄠˇ) should compose 你好. A longer sentence such as `jen tem tem vej hnf hwf` (Space is the first tone) should come out as 今天天氣很好 when the bundled model has those words.
3. Cursor correction: on 許氏, `tij` then `vkd` is ㄊㄞˋ ㄔㄤˊ. If the model joins them as 太長, press ← until 長 is underlined and pick 常. The marked text becomes 太常. The other character stays.
4. Space or Return commits the sentence. Turning the setting off returns to ㄅ半 immediately, including in other apps the input method is loaded into.
5. On 大千 and 倚天 the number keys are 注音 keys, so candidates are picked with the arrows and Space, not with 1–9.

### Screenshots / examples

Placeholder — the setting, off:

```
設定… ▸ 一般
  注音鍵盤          標準（大千）
  注音智慧選字（整句）   ☐     ← off until the user opts in
```

Placeholder — cursor correction (太長 → 太常):

```
許氏 keys:  tij vkd
marked:     太長
← onto 長:  太[長]          candidates: 長, 常, …
pick 常:    太常
```

Placeholder — the underlined character in the marked text. A screenshot of TextEdit with 長 drawn in the selected-clause style (thick underline) and 常 in the candidate window would show the same thing.

### Credit

No new Hsu rules in this branch. The layout it types through, including 許氏, is the McBopomofo port (MIT) from the Hsu PR. The language model is the same McBopomofo data this app already ships.

### Dependencies

Stacked on `feat/zhuyin-hsu-layout`. Open it against that branch, or retarget to `main` only after the Hsu PR has merged. It does not build on `main` alone: `SmartZhuyinEngine` calls `ZhuyinKeyboardLayout.combine`, `claims`, and `backspaced`, which that PR adds.

Independent of `fix/adhoc-build-runtime`.
