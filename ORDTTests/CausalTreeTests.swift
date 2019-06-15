//
//  CausalTreeTests.swift
//  ORDTTests
//
//  Created by Alexei Baboulevitch on 2018-4-21.
//  Copyright © 2018 Alexei Baboulevitch. All rights reserved.
//

import Foundation

import XCTest
import CRDTFramework_OSX

enum StringValue: DefaultInitializable, CRDTValueRelationQueries, CausalTreePriority, CustomStringConvertible
{
    case null
    case insert(char: UInt16)
    case delete
    
    public init()
    {
        self = .null
    }
    
    public var description: String
    {
        switch self
        {
        case .null:
            return "ø"
        case .insert(let char):
            return "\(Character(UnicodeScalar(char) ?? UnicodeScalar(0)))"
        case .delete:
            return "X"
        }
    }
    
    public var childless: Bool
    {
        switch self
        {
        case .null:
            return false
        case .insert(_):
            return false
        case .delete:
            return true
        }
    }
    
    public var priority: UInt8
    {
        switch self
        {
        case .null:
            return 0
        case .insert(_):
            return 0
        case .delete:
            return 1
        }
    }
}

extension ORDTCausalTree where ValueT == StringValue
{
    func toString() -> String
    {
        var values: [unichar] = []
        
        for op in self.operations()
        {
            switch op.value
            {
            case .null:
                break
            case .insert(let c):
                values.append(c)
            case .delete:
                let _ = values.popLast()
            }
        }
        
        return NSString.init(characters: &values, length: values.count) as String
    }
    
    // TODO: temp until mappedordt
    static func integrate(c1: inout ORDTCausalTree, c2: inout ORDTCausalTree, s1: inout SiteMap<UInt64>, s2: inout SiteMap<UInt64>, em1: [LUID:LUID], em2: [LUID:LUID])
    {
        let map12 = SiteMap<UInt64>.indexMap(localSiteIndex: s1, remoteSiteIndex: s2)
        let map21 = SiteMap<UInt64>.indexMap(localSiteIndex: s2, remoteSiteIndex: s1)
        
        XCTAssertEqual(map12, em1)
        XCTAssertEqual(map21, em2)
        
        var c2Copy = c2
        c1.remapIndices(map12)
        c2Copy.remapIndices(map21)
        
        XCTAssert(TestUtils.validate(&c1))
        XCTAssert(TestUtils.validate(&c2Copy))
        
        c1.integrate(&c2Copy)
        s1.integrate(&s2)
        
        XCTAssert(TestUtils.validate(&c1))
        XCTAssert(TestUtils.validate(&s1))
    }
}

class CausalTreeTests: ABTestCase
{
    typealias TreeT = ORDTCausalTree<StringValue>
    
    var baseTree: TreeT!
    
    override func setUp()
    {
        super.setUp()
        
        self.baseTree = TreeT.init(owner: 1)
    }
    
    override func tearDown()
    {
        self.baseTree = nil
        
        super.tearDown()
    }
    
    // NEXT: structify
    // NEXT: array slice
    
    func testBasics()
    {
        var tree: TreeT = baseTree
        
        let zeroAtom = tree.operations().first!
        let a1 = tree.addAtom(withValue: StringValue.insert(char: 97), causedBy: zeroAtom.id)!
        let a2 = tree.addAtom(withValue: StringValue.insert(char: 98), causedBy: a1.0)!
        let a3 = tree.addAtom(withValue: StringValue.insert(char: 99), causedBy: a2.0)!
        _ = tree.addAtom(withValue: StringValue.insert(char: 100), causedBy: a3.0)! // a4
        
        tree.changeOwner(2)
        
        let b1 = tree.addAtom(withValue: StringValue.insert(char: 101), causedBy: a2.0)!
        let b2 = tree.addAtom(withValue: StringValue.insert(char: 102), causedBy: b1.0)!
        _ = tree.addAtom(withValue: StringValue.insert(char: 103), causedBy: b2.0)! // b3
        _ = tree.addAtom(withValue: StringValue.delete, causedBy: b2.0)! // b4
        
        XCTAssert(TestUtils.validate(&tree))
        
        XCTAssertEqual(tree.toString(), "abegcd")
    }
    
    // TODO: this map will change once the CT is structified
    func testBasicMerge()
    {
        var tree1: TreeT = baseTree
        
        let zeroAtom = tree1.operations().first!
        let a1 = tree1.addAtom(withValue: StringValue.insert(char: UInt16(UnicodeScalar("c").value)), causedBy: zeroAtom.id)!
        let a2 = tree1.addAtom(withValue: StringValue.insert(char: UInt16(UnicodeScalar("m").value)), causedBy: a1.0)!
        let a3 = tree1.addAtom(withValue: StringValue.insert(char: UInt16(UnicodeScalar("d").value)), causedBy: a2.0)!
        
        let clock = tree1.lamportClock
        
        var tree2: TreeT = tree1
        tree2.changeOwner(2)
        tree2.timeFunction = { return clock + 1 + 1 }
        
        let b1 = tree2.addAtom(withValue: StringValue.insert(char: UInt16(UnicodeScalar("d").value)), causedBy: a3.0)!
        let b2 = tree2.addAtom(withValue: StringValue.insert(char: UInt16(UnicodeScalar("e").value)), causedBy: b1.0)!
        _ = tree2.addAtom(withValue: StringValue.insert(char: UInt16(UnicodeScalar("l").value)), causedBy: b2.0)! // b3
        
        var tree3: TreeT = tree1
        tree3.changeOwner(3)
        tree3.timeFunction = { return clock + 2 + 1 }
        
        let c1 = tree3.addAtom(withValue: StringValue.insert(char: UInt16(UnicodeScalar("a").value)), causedBy: a3.0)!
        let c2 = tree3.addAtom(withValue: StringValue.insert(char: UInt16(UnicodeScalar("l").value)), causedBy: c1.0)!
        _ = tree3.addAtom(withValue: StringValue.insert(char: UInt16(UnicodeScalar("t").value)), causedBy: c2.0)! // c3
        
        tree1.timeFunction = { return clock + 2 }
        
        _ = tree1.addAtom(withValue: StringValue.delete, causedBy: a2.0)! // a4
        _ = tree1.addAtom(withValue: StringValue.delete, causedBy: a3.0)! // a5
        let a6 = tree1.addAtom(withValue: StringValue.insert(char: UInt16(UnicodeScalar("t").value)), causedBy: a1.0)!
        let a7 = tree1.addAtom(withValue: StringValue.insert(char: UInt16(UnicodeScalar("r").value)), causedBy: a6.0)!
        let _ = tree1.addAtom(withValue: StringValue.insert(char: UInt16(UnicodeScalar("l").value)), causedBy: a7.0)! // a8
        
        XCTAssert(TestUtils.validate(&tree1))
        XCTAssert(TestUtils.validate(&tree2))
        XCTAssert(TestUtils.validate(&tree3))
        
        XCTAssertEqual(tree1.toString(), "ctrl")
        XCTAssertEqual(tree2.toString(), "cmddel")
        XCTAssertEqual(tree3.toString(), "cmdalt")
        
        tree1.integrate(&tree2)

        XCTAssertEqual(tree1.toString(), "ctrldel")
        
        tree1.integrate(&tree3)
        
        XCTAssertEqual(tree1.toString(), "ctrlaltdel")
        
        tree2.integrate(&tree3)
        
        XCTAssertEqual(tree2.toString(), "cmdaltdel")
        
        tree3.integrate(&tree1)
        
        XCTAssertEqual(tree3.toString(), "ctrlaltdel")
    }
    
    func testRemapIndices()
    {
        var siteMap1 = SiteMap<UInt64>.init()
        
        let u1 = siteMap1.addUuid(1234)
        var tree1 = TreeT.init(owner: TreeT.SiteIDT.init(id: u1))
        
        let zeroAtom = tree1.operations().first!
        let a1 = tree1.addAtom(withValue: StringValue.insert(char: UInt16(UnicodeScalar("a").value)), causedBy: zeroAtom.id)!
        let _ = tree1.addAtom(withValue: StringValue.insert(char: UInt16(UnicodeScalar("b").value)), causedBy: a1.0)! // a2
        
        XCTAssert(TestUtils.validate(&tree1))
        XCTAssert(TestUtils.validate(&siteMap1))
        
        let clock = tree1.lamportClock
        
        var siteMap2 = siteMap1
        siteMap2.timeFunction = { return clock + 1 }
        let u2 = siteMap2.addUuid(2345)
        XCTAssertEqual(u2, 2)
        var tree2 = tree1
        tree2.changeOwner(TreeT.SiteIDT.init(id: u2))
        
        var siteMap3 = siteMap1
        siteMap3.timeFunction = { return clock + 2 }
        let u3 = siteMap3.addUuid(4567)
        XCTAssertEqual(u3, 2)
        var tree3 = tree1
        tree3.changeOwner(TreeT.SiteIDT.init(id: u3))
        
        var siteMap4 = siteMap1
        siteMap4.timeFunction = { return clock + 3 }
        let u4 = siteMap4.addUuid(7890)
        XCTAssertEqual(u4, 2)
        var tree4 = tree1
        tree4.changeOwner(TreeT.SiteIDT.init(id: u4))
        
        let d1 = tree4.addAtom(withValue: StringValue.insert(char: UInt16(UnicodeScalar("g").value)), causedBy: zeroAtom.id)!
        let _ = tree4.addAtom(withValue: StringValue.insert(char: UInt16(UnicodeScalar("h").value)), causedBy: d1.0)! // d2
        
        XCTAssert(TestUtils.validate(&tree4))
        XCTAssert(TestUtils.validate(&siteMap4))
        
        let b1 = tree2.addAtom(withValue: StringValue.insert(char: UInt16(UnicodeScalar("c").value)), causedBy: zeroAtom.id)!
        let _ = tree2.addAtom(withValue: StringValue.insert(char: UInt16(UnicodeScalar("d").value)), causedBy: b1.0)! // b2

        XCTAssert(TestUtils.validate(&tree2))
        XCTAssert(TestUtils.validate(&siteMap2))
        
        let c1 = tree3.addAtom(withValue: StringValue.insert(char: UInt16(UnicodeScalar("e").value)), causedBy: zeroAtom.id)!
        let _ = tree3.addAtom(withValue: StringValue.insert(char: UInt16(UnicodeScalar("f").value)), causedBy: c1.0)! // c2

        XCTAssert(TestUtils.validate(&tree3))
        XCTAssert(TestUtils.validate(&siteMap3))
        
        XCTAssertEqual(tree1.toString(), "ab")
        XCTAssertEqual(tree2.toString(), "cdab")
        XCTAssertEqual(tree3.toString(), "efab")
        XCTAssertEqual(tree4.toString(), "ghab")
        
        TreeT.integrate(c1: &tree3, c2: &tree4, s1: &siteMap3, s2: &siteMap4, em1: [:], em2: [2:3])
        
        let site3Uuids = siteMap3.luidToUuidMap().sorted { (k1, k2) -> Bool in return k1.key < k2.key }.map { $0.value }
        XCTAssertEqual(site3Uuids, [1234, 4567, 7890])
        XCTAssertEqual(tree3.toString(), "ghefab")
        
        TreeT.integrate(c1: &tree2, c2: &tree4, s1: &siteMap2, s2: &siteMap4, em1: [:], em2: [2:3])
        var site2Uuids = siteMap2.luidToUuidMap().sorted { (k1, k2) -> Bool in return k1.key < k2.key }.map { $0.value }
        XCTAssertEqual(site2Uuids, [1234, 2345, 7890])
        XCTAssertEqual(tree2.toString(), "ghcdab")
        
        TreeT.integrate(c1: &tree2, c2: &tree3, s1: &siteMap2, s2: &siteMap3, em1: [3:4], em2: [2:3, 3:4])
        site2Uuids = siteMap2.luidToUuidMap().sorted { (k1, k2) -> Bool in return k1.key < k2.key }.map { $0.value }
        XCTAssertEqual(site2Uuids, [1234, 2345, 4567, 7890])
        XCTAssertEqual(tree2.toString(), "ghefcdab")
        
        TreeT.integrate(c1: &tree4, c2: &tree2, s1: &siteMap4, s2: &siteMap2, em1: [2:4], em2: [:])
        let site4Uuids = siteMap2.luidToUuidMap().sorted { (k1, k2) -> Bool in return k1.key < k2.key }.map { $0.value }
        XCTAssertEqual(site4Uuids, [1234, 2345, 4567, 7890])
        XCTAssertEqual(tree4.toString(), "ghefcdab")
    }
}
