import XCTest
import AppKit
import Carbon.HIToolbox
@testable import MyWorkDock

@MainActor
final class ShortcutTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test-shortcuts-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - KeyCombo Tests

    func testKeyComboInitializationAndDisplayString() {
        let optSpace = KeyCombo(keyCode: UInt16(kVK_Space), modifiers: .option)
        XCTAssertEqual(optSpace.displayString, "⌥ Space")
        XCTAssertEqual(optSpace.carbonModifiers, optionKey)

        let cmdShiftV = KeyCombo(keyCode: UInt16(kVK_ANSI_V), modifiers: [.command, .shift])
        XCTAssertEqual(cmdShiftV.displayString, "⇧⌘V")
        XCTAssertEqual(cmdShiftV.carbonModifiers, cmdKey | shiftKey)

        let fromCarbon = KeyCombo(keyCode: kVK_Space, carbonModifiers: optionKey)
        XCTAssertEqual(fromCarbon, optSpace)
    }

    func testKeyComboCodable() throws {
        let original = KeyCombo(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command, .option])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - ShortcutAction & Defaults

    func testDefaultCombosMatchExistingSystem() {
        let store = ShortcutStore(defaults: nil)
        XCTAssertTrue(store.masterEnabled)
        XCTAssertTrue(store.disabledActions.isEmpty)
        XCTAssertEqual(store.combo(for: .togglePanel).displayString, "⌥ Space")
        XCTAssertEqual(store.combo(for: .clipboard).displayString, "⇧⌘V")
        XCTAssertEqual(store.combo(for: .calendar).displayString, "⇧⌘M")
        XCTAssertEqual(store.combo(for: .notesTodo).displayString, "⇧⌘D")
        XCTAssertEqual(store.combo(for: .notesCommands).displayString, "⇧⌘C")
        XCTAssertEqual(store.combo(for: .notesPrompts).displayString, "⇧⌘P")
        XCTAssertEqual(store.combo(for: .notesLinks).displayString, "⇧⌘L")
        XCTAssertEqual(store.combo(for: .emulator).displayString, "⇧⌘E")
        XCTAssertEqual(store.combo(for: .claudex).displayString, "⇧⌘X")
    }

    func testAllShortcutActionsHaveCategoriesAndGlyphs() {
        for action in ShortcutAction.allCases {
            XCTAssertFalse(action.label.isEmpty)
            _ = action.glyph
            _ = action.category
            _ = action.defaultCombo
        }
    }

    // MARK: - Master & Individual Toggles

    func testMasterToggle() {
        let store = ShortcutStore(defaults: defaults)
        XCTAssertTrue(store.masterEnabled)
        XCTAssertTrue(store.isEnabled(.clipboard))

        store.setMasterEnabled(false)
        XCTAssertFalse(store.masterEnabled)
        XCTAssertFalse(store.isEnabled(.clipboard))

        // Check persistence
        let restored = ShortcutStore(defaults: defaults)
        XCTAssertFalse(restored.masterEnabled)
    }

    func testIndividualActionToggle() {
        let store = ShortcutStore(defaults: defaults)
        XCTAssertTrue(store.isActionSwitchedOn(.clipboard))

        store.setActionSwitchedOn(.clipboard, false)
        XCTAssertFalse(store.isActionSwitchedOn(.clipboard))
        XCTAssertFalse(store.isEnabled(.clipboard))
        XCTAssertTrue(store.isEnabled(.calendar))

        let restored = ShortcutStore(defaults: defaults)
        XCTAssertFalse(restored.isActionSwitchedOn(.clipboard))
        XCTAssertTrue(restored.isActionSwitchedOn(.calendar))
    }

    // MARK: - Custom Bindings & Conflict Detection

    func testCustomBindingAndReset() {
        let store = ShortcutStore(defaults: defaults)
        let custom = KeyCombo(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command, .option])

        store.setCombo(custom, for: .clipboard)
        XCTAssertEqual(store.combo(for: .clipboard), custom)
        XCTAssertTrue(store.isCustomized(.clipboard))

        // Check persistence
        let restored = ShortcutStore(defaults: defaults)
        XCTAssertEqual(restored.combo(for: .clipboard), custom)

        // Reset to default
        store.resetToDefault(.clipboard)
        XCTAssertFalse(store.isCustomized(.clipboard))
        XCTAssertEqual(store.combo(for: .clipboard), ShortcutAction.clipboard.defaultCombo)
    }

    func testConflictDetection() {
        let store = ShortcutStore(defaults: nil)
        let optSpace = KeyCombo(keyCode: UInt16(kVK_Space), modifiers: .option)

        // Checking optSpace against clipboard should find conflict with togglePanel
        let conflict = store.conflictingAction(for: optSpace, excluding: .clipboard)
        XCTAssertEqual(conflict, .togglePanel)

        // Checking optSpace against togglePanel (itself) should NOT report conflict
        let selfConflict = store.conflictingAction(for: optSpace, excluding: .togglePanel)
        XCTAssertNil(selfConflict)
    }

    func testResetAll() {
        let store = ShortcutStore(defaults: defaults)
        store.setMasterEnabled(false)
        store.setActionSwitchedOn(.clipboard, false)
        store.setCombo(KeyCombo(keyCode: UInt16(kVK_ANSI_Z), modifiers: [.command, .option]), for: .calendar)

        store.resetAll()
        XCTAssertTrue(store.masterEnabled)
        XCTAssertTrue(store.disabledActions.isEmpty)
        XCTAssertFalse(store.isCustomized(.calendar))
    }

    // MARK: - HotKey Registration & Unregistration Lifecycle

    func testHotKeyUnregisterAllowsImmediateReRegistration() {
        let cmdShift = cmdKey | shiftKey
        let hk1 = HotKey(keyCode: kVK_ANSI_Y, modifiers: cmdShift, action: {})
        XCTAssertNotNil(hk1, "First registration should succeed")

        let hkDuplicate = HotKey(keyCode: kVK_ANSI_Y, modifiers: cmdShift, action: {})
        XCTAssertNil(hkDuplicate, "Duplicate registration while still active should fail")

        hk1?.unregister()

        let hk2 = HotKey(keyCode: kVK_ANSI_Y, modifiers: cmdShift, action: {})
        XCTAssertNotNil(hk2, "Registration after unregister must succeed without 'in use' error")
        hk2?.unregister()
    }

    // MARK: - SettingsScreen Page

    func testShortcutsPageIsPresent() {
        XCTAssertTrue(SettingsScreen.Page.allCases.contains(.shortcuts))
        XCTAssertEqual(SettingsScreen.Page.shortcuts.label, "Shortcuts")
        XCTAssertEqual(SettingsScreen.Page.shortcuts.glyph, .keyboard)
    }
}
