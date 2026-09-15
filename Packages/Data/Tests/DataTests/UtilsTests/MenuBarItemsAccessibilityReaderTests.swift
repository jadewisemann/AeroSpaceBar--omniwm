// Copyright (c) 2026 AeroSpaceBar by Ronen Druker.

import CoreGraphics
@testable import Data
import Domain
import Nimble
import XCTest

/// Tests for the filtering and normalization logic of `MenuBarItemsAccessibilityReader`.
final class MenuBarItemsAccessibilityReaderTests: XCTestCase {
    /// Bounds of a main display used by the tests.
    private let displayBounds = CGRect(x: 0, y: 0, width: 1_800, height: 1_169)

    /// Menu bar height used by the tests.
    private let menuBarHeight = 39.0

    func testDropsItemsOutsideMenuBar() {
        // Given a visible item, an item hidden at the bottom-left, and an item past the right edge
        let rawItems = [
            MenuBarItemsAccessibilityReader.RawItem(
                ownerIdentifier: "visible",
                index: 0,
                frame: CGRect(x: 1_283, y: 7.5, width: 38, height: 24)
            ),
            MenuBarItemsAccessibilityReader.RawItem(
                ownerIdentifier: "hidden",
                index: 0,
                frame: CGRect(x: -1, y: 1_157, width: 38, height: 24)
            ),
            MenuBarItemsAccessibilityReader.RawItem(
                ownerIdentifier: "offscreen",
                index: 0,
                frame: CGRect(x: 1_790, y: 0, width: 38, height: 24)
            )
        ]

        // When normalizing
        let items = MenuBarItemsAccessibilityReader.normalizedItems(
            rawItems: rawItems,
            menuBarHeight: menuBarHeight,
            displayBounds: displayBounds
        )

        // Then only the visible item remains
        expect(items.map(\.id)) == ["visible#0"]
    }

    func testDropsZeroWidthItems() {
        // Given an item without width
        let rawItems = [
            MenuBarItemsAccessibilityReader.RawItem(
                ownerIdentifier: "empty",
                index: 0,
                frame: CGRect(x: 1_000, y: 0, width: 0, height: 39)
            )
        ]

        // When normalizing
        let items = MenuBarItemsAccessibilityReader.normalizedItems(
            rawItems: rawItems,
            menuBarHeight: menuBarHeight,
            displayBounds: displayBounds
        )

        // Then the item is dropped
        expect(items).to(beEmpty())
    }

    func testNormalizesFramesToMenuBarHeight() {
        // Given a vertically centered third-party item
        let rawItems = [
            MenuBarItemsAccessibilityReader.RawItem(
                ownerIdentifier: "third-party",
                index: 0,
                frame: CGRect(x: 1_327, y: 7.5, width: 24, height: 24)
            )
        ]

        // When normalizing
        let items = MenuBarItemsAccessibilityReader.normalizedItems(
            rawItems: rawItems,
            menuBarHeight: menuBarHeight,
            displayBounds: displayBounds
        )

        // Then the frame spans the full menu bar height and keeps its horizontal extent
        expect(items.first?.frame) == CGRect(x: 1_327, y: 0, width: 24, height: menuBarHeight)
    }

    func testSortsItemsFromRightToLeft() {
        // Given items in arbitrary order
        let rawItems = [
            MenuBarItemsAccessibilityReader.RawItem(
                ownerIdentifier: "middle",
                index: 0,
                frame: CGRect(x: 1_400, y: 0, width: 20, height: 39)
            ),
            MenuBarItemsAccessibilityReader.RawItem(
                ownerIdentifier: "left",
                index: 0,
                frame: CGRect(x: 1_100, y: 0, width: 20, height: 39)
            ),
            MenuBarItemsAccessibilityReader.RawItem(
                ownerIdentifier: "right",
                index: 0,
                frame: CGRect(x: 1_667, y: 0, width: 113, height: 39)
            )
        ]

        // When normalizing
        let items = MenuBarItemsAccessibilityReader.normalizedItems(
            rawItems: rawItems,
            menuBarHeight: menuBarHeight,
            displayBounds: displayBounds
        )

        // Then items are ordered from right to left
        expect(items.map(\.id)) == ["right#0", "middle#0", "left#0"]
    }

    func testReturnsNoItemsWhenMenuBarHeightIsZero() {
        // Given a visible item but a hidden menu bar
        let rawItems = [
            MenuBarItemsAccessibilityReader.RawItem(
                ownerIdentifier: "visible",
                index: 0,
                frame: CGRect(x: 1_283, y: 0, width: 38, height: 24)
            )
        ]

        // When normalizing with a zero menu bar height
        let items = MenuBarItemsAccessibilityReader.normalizedItems(
            rawItems: rawItems,
            menuBarHeight: 0,
            displayBounds: displayBounds
        )

        // Then no items are returned
        expect(items).to(beEmpty())
    }
}
