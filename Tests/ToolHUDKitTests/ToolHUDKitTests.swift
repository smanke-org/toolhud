import Foundation
import Testing
@testable import ToolHUDKit

// MARK: - Shortcuts

@Test func shortcutsReadInMenuOrder() {
    let s = Shortcut(keyCode: KeyCode.t, modifiers: [.command, .shift, .control, .option], key: "T")
    #expect(s.display == "⌃⌥⇧⌘T")
    #expect(Shortcut.defaultHUD.display == "⌃⌥⌘Space")
}

@Test func keyNamesCoverSpecialKeys() {
    #expect(KeyNames.name(keyCode: 122, characters: nil) == "F1")
    #expect(KeyNames.name(keyCode: 90, characters: nil) == "F20")
    #expect(KeyNames.name(keyCode: KeyCode.space, characters: " ") == "Space")
    #expect(KeyNames.name(keyCode: KeyCode.left, characters: nil) == "←")
    #expect(KeyNames.name(keyCode: KeyCode.t, characters: "t") == "T")
}

@Test func systemShortcutsAreRecognized() {
    #expect(SystemShortcuts.purpose(of: Shortcut(keyCode: KeyCode.space, modifiers: [.command], key: "Space")) == "Spotlight")
    #expect(SystemShortcuts.purpose(of: .defaultHUD) == nil)
}

@Test func lensShortcutsHaveOwners() {
    let owner = LensCatalog.owner(of: .controlOptionCommand(KeyCode.t, "T"))
    #expect(owner?.app.name == "TextLens")
    #expect(owner?.feature.id == "capture")
    #expect(LensCatalog.owner(of: .defaultHUD) == nil)
}

@Test func defaultHUDShortcutIsFreeAmongLensApps() {
    for app in LensCatalog.builtIn {
        for feature in app.features {
            #expect(feature.shortcut?.sameKeys(as: .defaultHUD) != true, "\(app.name) \(feature.id)")
        }
    }
}

// MARK: - Slots and rings

@Test func defaultRingHasTwelveDistinctLensButtons() {
    let slots = DefaultRing.slots
    #expect(slots.count == DefaultRing.maxCount)
    #expect(Set(slots.map(\.id)).count == slots.count)
    for slot in slots {
        #expect(slot.mode == .lens)
        let app = slot.lensApp.flatMap(LensCatalog.app)
        #expect(app != nil)
        #expect(app?.feature(slot.lensFeature ?? "") != nil)
    }
}

@Test func slotsDecodeLeniently() throws {
    let json = #"{"name":"Old","mode":"lens","lensApp":"com.smanke.TextLens"}"#
    let slot = try JSONDecoder().decode(Slot.self, from: Data(json.utf8))
    #expect(slot.name == "Old")
    #expect(slot.symbol == "circle")
    #expect(slot.sendTo == .frontmost)
    #expect(slot.lensFeature == nil)
}

@Test func slotsRoundTrip() throws {
    var slot = Slot(LensCatalog.clickLens, "box")
    slot.color = SlotColor(hex: "#FF6FAE")
    slot.mode = .keystroke
    slot.sendTo = .app(bundleID: "com.apple.Safari", name: "Safari")
    let data = try JSONEncoder().encode(slot)
    #expect(try JSONDecoder().decode(Slot.self, from: data) == slot)
}

@Test func ringFilesRoundTripWithFreshIdentities() throws {
    let slots = Array(DefaultRing.slots.prefix(3))
    let data = try RingFile(visualization: .stargate, slots: slots).encoded()
    let read = try RingFile.decode(data)
    #expect(read.visualization == .stargate)
    #expect(read.slots.map(\.name) == slots.map(\.name))
    #expect(Set(read.slots.map(\.id)).isDisjoint(with: slots.map(\.id)))
}

@Test func otherFilesAreNotRings() {
    #expect(throws: RingFile.ReadError.self) { try RingFile.decode(Data(#"{"hello":1}"#.utf8)) }
    let empty = try! RingFile(visualization: nil, slots: []).encoded()
    #expect(throws: RingFile.ReadError.self) { try RingFile.decode(empty) }
}

@Test func colorsParseHex() {
    let c = SlotColor(hex: "#5B9BFF")
    #expect(c?.hex == "#5B9BFF")
    #expect(SlotColor(hex: "nope") == nil)
}

// MARK: - Lens catalog

@Test func lensURLsUseTheFeatureAsHost() {
    let url = LensCatalog.textLens.url(for: "capture")
    #expect(url?.scheme == "textlens")
    #expect(url?.host == "capture")
    #expect(url?.query == "source=toolhud")
}

@Test func declaredFeaturesReplaceTheBuiltInList() {
    let info: [String: Any] = [
        "CFBundleURLTypes": [["CFBundleURLSchemes": ["TextLens"]]],
        "ToolHUDActions": [
            ["id": "capture", "title": "Capture text", "symbol": "text.viewfinder"],
            ["id": "new-thing", "title": "Something new", "activates": true],
            ["title": "no id"],
        ] as [[String: Any]],
    ]
    #expect(LensCatalog.schemes(in: info) == ["textlens"])
    let app = LensCatalog.resolve(bundleID: "com.smanke.TextLens", name: "TextLens", info: info)
    #expect(app?.features.map(\.id) == ["capture", "new-thing"])
    // The plist carries no shortcuts; the built-in default is kept for the fallback.
    #expect(app?.feature("capture")?.shortcut?.display == "⌃⌥⌘T")
    #expect(app?.feature("new-thing")?.activates == true)
}

@Test func unknownAppsJoinOnlyByDeclaring() {
    let declaring: [String: Any] = [
        "CFBundleURLTypes": [["CFBundleURLSchemes": ["windowkeeper"]]],
        "ToolHUDActions": [["id": "save", "title": "Save layout"]],
    ]
    let app = LensCatalog.resolve(bundleID: "com.smanke.WindowKeeper", name: "WindowKeeper", info: declaring)
    #expect(app?.scheme == "windowkeeper")
    #expect(app?.features.first?.symbol == "circle")
    #expect(LensCatalog.resolve(bundleID: "com.smanke.WindowKeeper", name: "WindowKeeper", info: [:]) == nil)
    #expect(LensCatalog.resolve(bundleID: "com.smanke.TextLens", name: "TextLens", info: [:])?.features.count
        == LensCatalog.textLens.features.count)
}

// MARK: - Geometry

@Test func bearingsRunClockwiseFromUp() {
    #expect(HUDLayout.bearing(of: HUDPoint(0, -10)) == 0)
    #expect(abs(HUDLayout.bearing(of: HUDPoint(10, 0)) - 90) < 1e-9)
    #expect(abs(HUDLayout.bearing(of: HUDPoint(0, 10)) - 180) < 1e-9)
    #expect(abs(HUDLayout.bearing(of: HUDPoint(-10, 0)) - 270) < 1e-9)
}

@Test func slicesAreCenteredOnTheirButtons() {
    // Eight buttons: each owns 45°, centered on its own angle, so 350° still means the top one.
    #expect(HUDLayout.index(forBearing: 350, count: 8) == 0)
    #expect(HUDLayout.index(forBearing: 22, count: 8) == 0)
    #expect(HUDLayout.index(forBearing: 23, count: 8) == 1)
    #expect(HUDLayout.index(forBearing: 180, count: 8) == 4)
    #expect(HUDLayout.index(forBearing: 359.999, count: 3) == 0)
}

@Test func angularSelectionIgnoresTheDeadZone() {
    let centers = HUDLayout.centers(for: .halo, count: 4)
    #expect(HUDLayout.selection(at: HUDPoint(0, -20), centers: centers, style: .angular) == nil)
    #expect(HUDLayout.selection(at: HUDPoint(0, -200), centers: centers, style: .angular) == 0)
    #expect(HUDLayout.selection(at: HUDPoint(500, 10), centers: centers, style: .angular) == 1)
}

@Test func everyButtonIsSelectableAtItsOwnCenter() {
    for viz in Visualization.allCases {
        for count in DefaultRing.minCount...DefaultRing.maxCount {
            let centers = HUDLayout.centers(for: viz, count: count, phase: 37)
            #expect(centers.count == count)
            for (i, center) in centers.enumerated() {
                #expect(HUDLayout.selection(at: center, centers: centers, style: viz.selection) == i,
                        "\(viz) \(count) #\(i)")
            }
        }
    }
}

@Test func buttonsStayOnTheCanvas() {
    let limit = HUDLayout.canvas / 2
    for viz in Visualization.allCases {
        for count in DefaultRing.minCount...DefaultRing.maxCount {
            for c in HUDLayout.centers(for: viz, count: count, phase: 200) {
                #expect(abs(c.x) < limit - 30 && abs(c.y) < limit - 30, "\(viz) \(count)")
            }
        }
    }
}

@Test func deckGridsStayCompact() {
    #expect(HUDLayout.deckColumns(2) == 2)
    #expect(HUDLayout.deckColumns(4) == 2)
    #expect(HUDLayout.deckColumns(6) == 3)
    #expect(HUDLayout.deckColumns(12) == 4)
    let deck = HUDLayout.deck(4)
    #expect(deck[0].x == -deck[1].x && deck[0].y == deck[1].y)
}

@Test func clampingKeepsTheHUDOnScreen() {
    let bounds = (minX: 0.0, minY: 0.0, maxX: 1000.0, maxY: 800.0)
    let p = HUDLayout.clamp(x: 10, y: 790, radius: 100, bounds: bounds)
    #expect(p.x == 100 && p.y == 700)
    let tiny = HUDLayout.clamp(x: 10, y: 10, radius: 600, bounds: bounds)
    #expect(tiny.x == 500 && tiny.y == 400)
}

// MARK: - Sync encryption

@Test func sealedDataOpensOnlyWithItsKey() throws {
    let (keyring, key) = try SyncCrypto.createKeyring(passphrase: "correct horse", iterations: 1_000)
    let plain = Data(String(repeating: "settings ", count: 100).utf8)
    let sealed = try SyncCrypto.seal(plain, using: key)
    #expect(sealed.prefix(4) == Data("THE1".utf8))
    #expect(try SyncCrypto.open(sealed, using: key) == plain)
    let unwrapped = try SyncCrypto.unwrap(keyring, passphrase: "correct horse")
    #expect(SyncCrypto.keyID(for: unwrapped) == keyring.keyID)
    #expect(throws: SyncCrypto.CryptoError.self) { try SyncCrypto.unwrap(keyring, passphrase: "wrong") }
    let (_, other) = try SyncCrypto.createKeyring(passphrase: "x", iterations: 1_000)
    #expect(throws: SyncCrypto.CryptoError.self) { try SyncCrypto.open(sealed, using: other) }
}

// MARK: - Key sequences

/// A US-English stand-in for the keyboard layout lookup.
private func usKey(_ c: Character) -> (keyCode: UInt16, shift: Bool)? {
    let plain: [Character: UInt16] = ["a": 0, "s": 1, "d": 2, "k": 40, "t": 17, "/": 44, "1": 18, " ": 49]
    if let code = plain[c] { return (code, false) }
    if c == "?" { return (44, true) }
    return nil
}

@Test func lettersAreTheirKeysWithoutShift() {
    let parsed = KeySequence.parse("K", modifiers: [.command], lookup: usKey)
    #expect(parsed.unknown.isEmpty)
    #expect(parsed.sequence.keys == [KeyPress(keyCode: 40, key: "K")])
    #expect(parsed.sequence.display == "⌘K")
}

@Test func severalKeysArePressedInTurnWithTheSameModifiers() {
    let parsed = KeySequence.parse("ks", modifiers: [.command, .shift], lookup: usKey)
    #expect(parsed.sequence.keys.map(\.keyCode) == [40, 1])
    #expect(parsed.sequence.display == "⇧⌘K ⇧⌘S")
}

@Test func shiftedSymbolsHoldShiftForThatKeyOnly() {
    let parsed = KeySequence.parse("?a", modifiers: [.control], lookup: usKey)
    #expect(parsed.sequence.keys == [KeyPress(keyCode: 44, key: "?", shift: true), KeyPress(keyCode: 0, key: "A")])
    #expect(parsed.sequence.display == "⌃⇧? ⌃A")
}

@Test func specialKeysComeFromSymbolsAndBrackets() {
    let parsed = KeySequence.parse("↩[F5][Space]⇥", modifiers: [], lookup: usKey)
    #expect(parsed.unknown.isEmpty)
    #expect(parsed.sequence.keys.map(\.keyCode) == [KeyCode.returnKey, 96, KeyCode.space, KeyCode.tab])
    #expect(parsed.sequence.keys.map(\.key) == ["↩", "F5", "Space", "⇥"])
}

@Test func untypeableCharactersAreReported() {
    let parsed = KeySequence.parse("aé[Nope]", modifiers: [], lookup: usKey)
    #expect(parsed.sequence.keys.count == 1)
    #expect(parsed.unknown == ["é", "[Nope]"])
}

@Test func everySpecialKeyInTheMenuParses() {
    for key in KeyNames.insertable {
        let parsed = KeySequence.parse(key.token, modifiers: [], lookup: usKey)
        #expect(parsed.unknown.isEmpty && parsed.sequence.keys.count == 1, "\(key.title)")
    }
}

@Test func buttonsSavedAsOneShortcutStillPressIt() throws {
    let json = #"{"name":"Old","symbol":"keyboard","mode":"keystroke","shortcut":{"keyCode":17,"modifiers":11,"key":"T"},"sendTo":{"frontmost":{}}}"#
    let slot = try JSONDecoder().decode(Slot.self, from: Data(json.utf8))
    #expect(slot.keys == nil)
    #expect(slot.keySequence?.display == "⌃⌥⌘T")
    #expect(slot.keySequence?.text == "T")
    // The field's text reads back as the same key.
    #expect(KeySequence.parse("T", modifiers: slot.keySequence!.modifiers, lookup: usKey).sequence.keys.map(\.keyCode) == [17])
}

@Test func keySequencesRoundTripThroughRingFiles() throws {
    var slot = Slot.empty()
    slot.keys = KeySequence.parse("k↩", modifiers: [.command], lookup: usKey).sequence
    let file = try RingFile.decode(RingFile(visualization: .halo, slots: [slot]).encoded())
    #expect(file.slots.first?.keys == slot.keys)
}
