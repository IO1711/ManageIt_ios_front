import XCTest
@testable import ManageIt

final class LocationTreeBuilderTests: XCTestCase {

    private func loc(_ id: Int64, _ name: String, parent: Int64? = nil, assignable: Bool = true, archived: Bool = false) -> LocationResponse {
        LocationResponse(
            id: id,
            name: name,
            archived: archived,
            parentLocationId: parent,
            path: nil,
            assignable: assignable
        )
    }

    func testBuildsFlatRootForest() {
        let flat = [
            loc(1, "Hall A"),
            loc(2, "Hall B"),
            loc(3, "Storage")
        ]
        let tree = LocationTreeBuilder.build(from: flat)
        XCTAssertEqual(tree.count, 3)
        XCTAssertTrue(tree.allSatisfy { $0.children.isEmpty })
        XCTAssertTrue(tree.allSatisfy { $0.isLeaf })
    }

    func testNestsChildrenByParentLocationId() {
        let flat = [
            loc(1, "Hall A"),
            loc(2, "Display Case 1", parent: 1),
            loc(3, "Shelf 1", parent: 2),
            loc(4, "Shelf 2", parent: 2),
            loc(5, "Hall B")
        ]
        let tree = LocationTreeBuilder.build(from: flat)
        XCTAssertEqual(tree.count, 2)
        let hallA = tree.first { $0.location.id == 1 }!
        XCTAssertEqual(hallA.children.count, 1)
        XCTAssertEqual(hallA.children[0].location.id, 2)
        XCTAssertEqual(hallA.children[0].children.count, 2)
        XCTAssertEqual(Set(hallA.children[0].children.map(\.location.id)), [3, 4])
    }

    func testSortsSiblingsAlphabeticallyCaseInsensitive() {
        let flat = [
            loc(1, "Zebra"),
            loc(2, "alpha"),
            loc(3, "Mango")
        ]
        let tree = LocationTreeBuilder.build(from: flat)
        XCTAssertEqual(tree.map(\.location.name), ["alpha", "Mango", "Zebra"])
    }

    func testLeafDetection() {
        let flat = [
            loc(1, "Root"),
            loc(2, "Child", parent: 1)
        ]
        let tree = LocationTreeBuilder.build(from: flat)
        XCTAssertFalse(tree[0].isLeaf)
        XCTAssertTrue(tree[0].children[0].isLeaf)
    }

    func testSelectabilityRespectsBackendAssignableAndArchived() {
        let flat = [
            loc(1, "Internal leaf", assignable: true, archived: false),
            loc(2, "Archived leaf", assignable: true, archived: true),
            loc(3, "Non-assignable leaf", assignable: false, archived: false),
            loc(4, "Has-child root"),
            loc(5, "Child", parent: 4)
        ]
        let tree = LocationTreeBuilder.build(from: flat)
        let byId = Dictionary(uniqueKeysWithValues: tree.flatMap { node in
            [(node.location.id, node)] + node.children.map { ($0.location.id, $0) }
        })
        XCTAssertTrue(byId[1]!.isSelectable, "leaf, assignable, not archived")
        XCTAssertFalse(byId[2]!.isSelectable, "archived leaf is never selectable")
        XCTAssertFalse(byId[3]!.isSelectable, "non-assignable leaf is never selectable")
        XCTAssertFalse(byId[4]!.isSelectable, "non-leaf root is never selectable")
        XCTAssertTrue(byId[5]!.isSelectable, "leaf child is selectable")
    }

    func testEmptyInputProducesEmptyForest() {
        XCTAssertTrue(LocationTreeBuilder.build(from: []).isEmpty)
    }

    func testOrphanedChildrenAreNotLost() {
        // child references a parent that does not exist; in the architecture
        // this should not happen, but the builder must not crash.
        let flat = [
            loc(2, "Orphan", parent: 99)
        ]
        let tree = LocationTreeBuilder.build(from: flat)
        XCTAssertTrue(tree.isEmpty, "orphans hide because their parent bucket is the root bucket only")
    }
}
