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

@Test func expansionLensActionsUseItsScheme() {
    let app = LensCatalog.expansionLens
    #expect(LensCatalog.app("com.smanke.ExpansionLens") == app)
    #expect(app.features.map(\.id) == ["open", "quicksearch", "new", "newfromclipboard", "editlast", "toggle", "on", "off", "settings"])
    #expect(app.url(for: "newfromclipboard")?.absoluteString == "expansionlens://newfromclipboard?source=toolhud")
    #expect(app.downloadURL?.absoluteString == "https://github.com/smanke-org/ExpansionLens/releases/latest")
    #expect(LensCatalog.textLens.downloadURL == nil)
}

@Test func captureLensActionsUseItsScheme() {
    let app = LensCatalog.captureLens
    #expect(LensCatalog.app("com.smanke.CaptureLens") == app)
    #expect(app.features.map(\.id) == ["capture", "screen", "window", "area", "recapture", "library"])
    #expect(app.url(for: "capture")?.absoluteString == "capturelens://capture?source=toolhud")
    #expect(app.downloadURL?.absoluteString == "https://github.com/smanke-org/CaptureLens/releases/latest")
    let owner = LensCatalog.owner(of: Shortcut(keyCode: KeyCode.digits[3], modifiers: [.option, .shift, .command], key: "4"))
    #expect(owner?.app.name == "CaptureLens")
    #expect(owner?.feature.id == "capture")
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

@Test func everyButtonIsHitAtItsOwnCenter() {
    for viz in Visualization.allCases {
        for count in DefaultRing.minCount...DefaultRing.maxCount {
            let centers = viz == .commandDeck ? HUDLayout.deck(count).map { HUDPoint($0.x, $0.y + 3) }
                                              : HUDLayout.centers(for: viz, count: count, phase: 37)
            #expect(centers.count == count)
            for (i, center) in centers.enumerated() {
                #expect(HUDLayout.button(at: center, in: viz, count: count, phase: 37) == i, "\(viz) \(count) #\(i)")
            }
        }
    }
}

@Test func pointingInADirectionNoLongerChoosesAButton() {
    // Halo used to pick by direction: anywhere above the center chose the top slice.
    #expect(HUDLayout.button(at: HUDPoint(0, -60), in: .halo, count: 8) == nil, "the hub")
    #expect(HUDLayout.button(at: HUDPoint(0, -260), in: .halo, count: 8) == nil, "past the ring")
    #expect(HUDLayout.button(at: HUDPoint(0, -150), in: .halo, count: 8) == 0, "on the slice")
    // Orbit: between two buttons is nothing.
    let orbit = HUDLayout.centers(for: .orbit, count: 8)
    let between = HUDPoint((orbit[0].x + orbit[1].x) / 2, (orbit[0].y + orbit[1].y) / 2)
    #expect(HUDLayout.button(at: between, in: .orbit, count: 8) == nil)
}

@Test func theMarginForgivesANearMissButNoMore() {
    let c = HUDLayout.centers(for: .orbit, count: 8)[2]   // straight right, radius 167
    #expect(HUDLayout.button(at: HUDPoint(c.x + 32 + 7, c.y), in: .orbit, count: 8) == 2)
    #expect(HUDLayout.button(at: HUDPoint(c.x + 32 + 10, c.y), in: .orbit, count: 8) == nil)
    #expect(HUDLayout.button(at: HUDPoint(c.x + 32 + 10, c.y), in: .orbit, count: 8, margin: 12) == 2)
}

@Test func theDialIsHitWhereItHasTurnedTo() {
    let count = 8, step = 360.0 / 8
    // Turned so button 2 is at the top.
    let top = HUDLayout.polar(160, 0)
    #expect(HUDLayout.button(at: top, in: .dial, count: count, dialTurn: 2 * step) == 2)
    #expect(HUDLayout.button(at: top, in: .dial, count: count, dialTurn: 0) == 0)
}

@Test func glassPillsAreHitAcrossTheirWidth() {
    let count = 8
    let right = HUDLayout.centers(for: .glassPills, count: count)[2]   // a side pill, growing outward
    let frame = HUDLayout.pillFrame(2, count: count, anchor: right, width: 180)
    #expect(HUDLayout.button(at: HUDPoint(frame.center.x + 85, right.y), in: .glassPills, count: count, pillWidths: [2: 180]) == 2)
    #expect(HUDLayout.button(at: HUDPoint(frame.center.x + 110, right.y), in: .glassPills, count: count, pillWidths: [2: 180]) == nil)
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

// MARK: - Settings gear

@Test func everyLookHasAGearClearOfItsButtons() throws {
    for look in Visualization.allCases {
        for count in DefaultRing.minCount...DefaultRing.maxCount {
            let gear = try #require(HUDLayout.gearCenter(for: look, count: count), "\(look)")
            // Inside the canvas, and far enough from every button that pointing at one
            // never lands on the gear.
            #expect(abs(gear.x) < HUDLayout.canvas / 2 && abs(gear.y) < HUDLayout.canvas / 2)
            let centers = look == .planetary ? HUDLayout.centers(for: look, count: count, phase: 0)
                                             : HUDLayout.centers(for: look, count: count)
            for center in centers {
                #expect(center.distance(to: gear) > HUDLayout.gearReach + 30, "\(look) \(count)")
            }
        }
    }
}

@Test func haloGearSitsInsideTheCenterDisk() throws {
    let gear = try #require(HUDLayout.gearCenter(for: .halo, count: 8))
    #expect(gear.length + HUDLayout.gearReach < 86)
}

@Test func pointingAtTheGearIsRecognizedOnlyNearIt() throws {
    let gear = try #require(HUDLayout.gearCenter(for: .halo, count: 8))
    #expect(HUDLayout.pointsAtGear(gear, in: .halo, count: 8))
    #expect(HUDLayout.pointsAtGear(HUDPoint(gear.x + 10, gear.y + 10), in: .halo, count: 8))
    #expect(!HUDLayout.pointsAtGear(HUDPoint(gear.x, gear.y + 30), in: .halo, count: 8))
}

// MARK: - The Halo's button pad

@Test func defaultPadHasEightLensButtonsNotOnTheRing() {
    let pad = DefaultPad.slots
    #expect(pad.count == DefaultPad.maxCount)
    #expect(DefaultPad.keyLetters.count == DefaultPad.maxCount && DefaultPad.usKeyCodes.count == DefaultPad.maxCount)
    let ring = Set(DefaultRing.slots.map { "\($0.lensApp ?? "")/\($0.lensFeature ?? "")" })
    for slot in pad {
        let app = slot.lensApp.flatMap(LensCatalog.app)
        #expect(app?.feature(slot.lensFeature ?? "") != nil)
        #expect(!ring.contains("\(slot.lensApp ?? "")/\(slot.lensFeature ?? "")"))
    }
}

/// Every look, side and size of pad, with the ring's size where it changes the look.
private func everyPad() -> [PadSpec] {
    Visualization.allCases.flatMap { look in
        [2, 8, 12].flatMap { ring in
            PadPosition.allCases.flatMap { position in
                (DefaultPad.minCount...DefaultPad.maxCount).map { PadSpec(look: look, ringCount: ring, position: position, count: $0) }
            }
        }
    }
}

@Test func everyPadButtonIsHitAtItsCenter() {
    for pad in everyPad() {
        let items = HUDLayout.padItems(pad)
        #expect(items.count == pad.count)
        for (i, item) in items.enumerated() {
            #expect(HUDLayout.padButton(at: item.center, in: pad) == i, "\(pad) \(i)")
        }
        #expect(HUDLayout.padButton(at: HUDPoint(0, 0), in: pad) == nil)
    }
}

@Test func padsRunInAColumnBesideAndARowAboveOrBelow() {
    for look in Visualization.allCases {
        func pad(_ position: PadPosition) -> [HUDPoint] {
            HUDLayout.padItems(PadSpec(look: look, ringCount: 8, position: position, count: 4)).map(\.center)
        }
        let right = pad(.right), left = pad(.left), above = pad(.above), below = pad(.below)
        #expect(right[0].y < right[1].y && right[1].y < right[2].y, "\(look)")
        #expect(above[0].x < above[1].x && above[1].x < above[2].x, "\(look)")
        #expect(right.allSatisfy { $0.x > 150 } && left.allSatisfy { $0.x < -150 }, "\(look)")
        #expect(above.allSatisfy { $0.y < -100 } && below.allSatisfy { $0.y > 100 }, "\(look)")
    }
}

@Test func thePadStaysClearOfItsLook() {
    for pad in everyPad() {
        let look = HUDLayout.lookExtent(pad.look, count: pad.ringCount)
        let tray = HUDLayout.padTray(pad)
        switch pad.position {
        case .right: #expect(tray.center.x - tray.width / 2 > look.maxX, "\(pad)")
        case .left: #expect(tray.center.x + tray.width / 2 < look.minX, "\(pad)")
        case .above: #expect(tray.center.y + tray.height / 2 < look.minY, "\(pad)")
        case .below: #expect(tray.center.y - tray.height / 2 > look.maxY, "\(pad)")
        }
        // Every button lies inside the tray.
        for item in HUDLayout.padItems(pad) {
            #expect(item.center.x - item.width / 2 >= tray.center.x - tray.width / 2 - 0.001, "\(pad)")
            #expect(item.center.x + item.width / 2 <= tray.center.x + tray.width / 2 + 0.001, "\(pad)")
            #expect(item.center.y - item.height / 2 >= tray.center.y - tray.height / 2 - 0.001, "\(pad)")
            #expect(item.center.y + item.height / 2 <= tray.center.y + tray.height / 2 + 0.001, "\(pad)")
        }
        // A ring button's center never lands on the pad.
        for c in HUDLayout.centers(for: pad.look, count: pad.ringCount) {
            #expect(HUDLayout.padButton(at: c, in: pad) == nil, "\(pad)")
        }
    }
}

@Test func theDrawingGrowsToHoldThePad() {
    let plain = HUDLayout.drawingBounds(pad: nil)
    #expect(plain == HUDLayout.Bounds(minX: -300, minY: -300, maxX: 300, maxY: 300))
    for pad in everyPad() {
        let box = HUDLayout.drawingBounds(pad: pad)
        #expect(box.minX <= -300 && box.minY <= -300 && box.maxX >= 300 && box.maxY >= 300)
        let tray = HUDLayout.padTray(pad)
        #expect(tray.center.x - tray.width / 2 >= box.minX && tray.center.x + tray.width / 2 <= box.maxX, "\(pad)")
        #expect(tray.center.y - tray.height / 2 >= box.minY && tray.center.y + tray.height / 2 <= box.maxY, "\(pad)")
    }
    let right = HUDLayout.drawingBounds(pad: PadSpec(look: .halo, ringCount: 8, position: .right, count: 4))
    #expect(right.maxX > 300 && right.minX == -300)
}

@Test func nestedHiveCellsGoToTheNearestCell() {
    let pad = PadSpec(look: .hive, ringCount: 8, position: .right, count: 4)
    let items = HUDLayout.padItems(pad)
    // Halfway between two nested cells' centers, nudged toward the second.
    let a = items[0].center, b = items[1].center
    let p = HUDPoint(a.x + (b.x - a.x) * 0.6, a.y + (b.y - a.y) * 0.6)
    #expect(HUDLayout.padButton(at: p, in: pad) == 1)
}

@Test func clampingKeepsAOneSidedHUDOnScreen() {
    let bounds = (minX: 0.0, minY: 0.0, maxX: 1000.0, maxY: 800.0)
    let extent = HUDLayout.Bounds(minX: -100, minY: -100, maxX: 400, maxY: 100)
    let p = HUDLayout.clamp(x: 900, y: 400, extent: extent, bounds: bounds)
    #expect(p.x == 600 && p.y == 400)
    let q = HUDLayout.clamp(x: 10, y: 10, extent: extent, bounds: bounds)
    #expect(q.x == 100 && q.y == 100)
}

@Test func ringFilesCarryThePadAndOldOnesStillRead() throws {
    let ring = RingFile(visualization: .halo, slots: Array(DefaultRing.slots.prefix(8)),
                        pad: Array(DefaultPad.slots.prefix(3)), padPosition: .below)
    let back = try RingFile.decode(ring.encoded())
    #expect(back.pad?.map(\.name) == ring.pad?.map(\.name))
    #expect(back.pad?.first?.id != ring.pad?.first?.id)
    #expect(back.padPosition == .below)
    let old = try RingFile.decode(RingFile(visualization: .halo, slots: DefaultRing.slots).encoded())
    #expect(old.pad == nil && old.padPosition == nil)
}

// MARK: - Activity

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func day(_ key: String) -> Date { ActivityLog.date(for: key, calendar: utc)!.addingTimeInterval(3600) }

@Test func activityLogCountsDaysAndLifetime() {
    var log = ActivityLog()
    log.record(at: day("2026-10-20"), calendar: utc)
    log.record(at: day("2026-10-20"), calendar: utc)
    log.record(at: day("2026-10-18"), calendar: utc)
    #expect(log.days == ["2026-10-20": 2, "2026-10-18": 1])
    #expect(log.firstDay == "2026-10-18")
    #expect(log.lifetime == 3)
    #expect(log.total(since: day("2026-10-19"), calendar: utc) == 2)
}

@Test func activityTrimKeepsLifetimeAndFirstDay() {
    var log = ActivityLog()
    log.record(at: day("2025-01-01"), calendar: utc)
    log.record(at: day("2026-10-20"), calendar: utc)
    log.trim(keepDays: 400, now: day("2026-10-24"), calendar: utc)
    #expect(log.days == ["2026-10-20": 1])
    #expect(log.firstDay == "2025-01-01")
    #expect(log.lifetime == 2)
}

@Test func activityCombinesMacs() {
    let a = ActivityLog(firstDay: "2026-10-10", days: ["2026-10-20": 3], lifetime: 10)
    let b = ActivityLog(firstDay: "2026-09-01", days: ["2026-10-20": 2, "2026-10-21": 1], lifetime: 5)
    let all = ActivityLog.combined([a, b])
    #expect(all.days == ["2026-10-20": 5, "2026-10-21": 1])
    #expect(all.firstDay == "2026-09-01")
    #expect(all.lifetime == 15)
}

@Test func activityRangeWidensWithHistory() {
    let today = day("2026-10-24")
    #expect(ActivityStats.range(firstDay: nil, today: today, calendar: utc) == .week)
    #expect(ActivityStats.range(firstDay: day("2026-10-18"), today: today, calendar: utc) == .week)
    #expect(ActivityStats.range(firstDay: day("2026-10-17"), today: today, calendar: utc) == .month)
    #expect(ActivityStats.range(firstDay: day("2026-06-01"), today: today, calendar: utc) == .halfYear)
    #expect(ActivityStats.range(firstDay: day("2025-01-01"), today: today, calendar: utc) == .year)
}

@Test func activityBarsBucketCounts() {
    let today = day("2026-10-24")
    let counts = [day("2026-10-24"): 4, day("2026-10-18"): 2, day("2026-10-17"): 9]
    let week = ActivityStats.bars(counts: counts, range: .week, today: today, calendar: utc)
    #expect(week.count == 7)
    #expect(week.first?.count == 2)   // the 17th is outside the week
    #expect(week.last?.count == 4)
    let year = ActivityStats.bars(counts: counts, range: .year, today: today, calendar: utc)
    #expect(year.count == 12)
    #expect(year.last?.count == 15)
}

@Test func deviceActivitySurvivesSealing() throws {
    let (_, key) = try SyncCrypto.createKeyring(passphrase: "correct horse", iterations: 1_000)
    let record = DeviceActivity(deviceID: "abc", deviceName: "Test Mac", updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                appVersion: "1.2.0", log: ActivityLog(firstDay: "2026-10-01", days: ["2026-10-01": 7], lifetime: 7))
    let sealed = try SyncCrypto.seal(DeviceActivity.encoder.encode(record), using: key)
    let back = try DeviceActivity.decoder.decode(DeviceActivity.self, from: SyncCrypto.open(sealed, using: key))
    #expect(back == record)
}

@Test func typedSpacesBecomeVisible() {
    #expect(KeySequence.showingSpaces(" ") == "[Space]")
    #expect(KeySequence.showingSpaces("K L") == "K[Space]L")
    #expect(KeySequence.showingSpaces("[Page Up]") == "[Page Up]")
    let parsed = KeySequence.parse(KeySequence.showingSpaces(" "), modifiers: [.command, .shift], lookup: { _ in nil })
    #expect(parsed.sequence.display == "⇧⌘Space")
    #expect(parsed.unknown.isEmpty)
}

// MARK: - Button list edits

private func names(_ n: Int) -> [Slot] { (0..<n).map { Slot(name: "B\($0)", symbol: "circle", mode: .keystroke) } }

@Test func deletingAButtonKeepsTheListLength() {
    var slots = names(12), count = 5
    SlotListEdit.delete(at: 1, slots: &slots, count: &count, minCount: 2)
    #expect(count == 4)
    #expect(slots.count == 12)
    #expect(slots.prefix(4).map(\.name) == ["B0", "B2", "B3", "B4"])
    #expect(slots.last?.name == "New button")
    count = 2
    SlotListEdit.delete(at: 0, slots: &slots, count: &count, minCount: 2)
    #expect(count == 2)
    #expect(slots.first?.name == "B0")
}

@Test func duplicatingAButtonPutsTheCopyNext() {
    var slots = names(12), count = 3
    SlotListEdit.duplicate(at: 0, slots: &slots, count: &count, maxCount: 12)
    #expect(count == 4)
    #expect(slots.count == 12)
    #expect(slots.prefix(4).map(\.name) == ["B0", "B0 copy", "B1", "B2"])
    #expect(slots[0].id != slots[1].id)
    count = 12
    SlotListEdit.duplicate(at: 0, slots: &slots, count: &count, maxCount: 12)
    #expect(count == 12)
}
