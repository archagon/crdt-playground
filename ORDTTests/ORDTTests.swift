//
//  ORDTTests.swift
//  ORDTTests
//
//  Created by Alexei Baboulevitch on 2018-4-12.
//  Copyright © 2018 Alexei Baboulevitch. All rights reserved.
//

import XCTest
import CRDTFramework_OSX

struct TestStruct: Zeroable, Codable
{
    let a: Int
    let b: UInt64
    let c: Float64
    let d: Bool
    
    static var zero: TestStruct { return TestStruct(a: 0, b: 0, c: 0, d: false) }
}
extension Int: Zeroable
{
    public static var zero: Int { return 0 }
}
extension String: Zeroable
{
    public static var zero: String { return "" }
}

// AB: reduces need to cast all the time
extension InstancedID: ExpressibleByIntegerLiteral
{
    public init(integerLiteral value: LUID)
    {
        self.init(id: value as! IDT)
    }
}

class ORDTTests: ABTestCase
{
    typealias ORDTMapT = ORDTMap<Int, TestStruct>
    typealias ORDTTestT = ORDTMap<InstancedLUID, String>
    
    var baseMap: ORDTTestT!
    
    override func setUp()
    {
        super.setUp()
        
        createMap: do
        {
            baseMap = ORDTTestT.init(withOwner: 1)
        }
    }
    
    override func tearDown()
    {
        baseMap = nil
        
        super.tearDown()
    }
    
    func testID()
    {
        var basicClock: ORDTClock = 1234
        var basicIndex: ORDTSiteIndex = 2345
        var basicSiteId: LUID = 4567
        var basicSession: UInt8 = 4
        
        var id = OperationID.init(logicalTimestamp: basicClock, index: basicIndex, siteID: basicSiteId, instanceID: 0)
        
        XCTAssertEqual(id.logicalTimestamp, basicClock)
        XCTAssertEqual(id.index, basicIndex)
        XCTAssertEqual(id.siteID, basicSiteId)
        XCTAssertEqual(id.instanceID, 0)
        
        id = OperationID.init(logicalTimestamp: basicClock, index: basicIndex, siteID: basicSiteId, instanceID: basicSession)
        
        XCTAssertEqual(id.logicalTimestamp, basicClock)
        XCTAssertEqual(id.index, basicIndex)
        XCTAssertEqual(id.siteID, basicSiteId)
        XCTAssertEqual(id.instanceID, basicSession)
        
        basicClock = ORDTClock(pow(2.0, 40) - 1)
        basicIndex = ORDTSiteIndex.max
        basicSiteId = LUID.max
        basicSession = UInt8.max
        
        id = OperationID.init(logicalTimestamp: basicClock, index: basicIndex, siteID: basicSiteId, instanceID: basicSession)
        
        XCTAssertEqual(id.logicalTimestamp, basicClock)
        XCTAssertEqual(id.index, basicIndex)
        XCTAssertEqual(id.siteID, basicSiteId)
        XCTAssertEqual(id.instanceID, basicSession)
    }
    
    func testBasicSetValue()
    {
        var weft = ORDTLocalTimestampWeft()
        
        var map: ORDTTestT = baseMap
        
        map.setValue("a")
        
        XCTAssert(TestUtils.validate(&map))
        XCTAssertEqual(map.value(forKey: 1), "a")
        
        map.setValue("b")
        map.setValue("c")
        
        XCTAssert(TestUtils.validate(&map))
        XCTAssertEqual(map.value(forKey: 1), "c")
        
        weft.update(site: 1, value: 3)
        XCTAssertEqual(map.timestampWeft, weft)
        
        map.setValue("d", forKey: 2)
        map.setValue("e", forKey: 2)
        
        XCTAssertEqual(map.value(forKey: 2), "e")
        
        weft.update(site: 1, value: 5)
        XCTAssertEqual(map.timestampWeft, weft)
        
        map.changeOwner(2)
        
        map.setValue("f", forKey: 1)
        map.setValue("g", forKey: 2)
        
        XCTAssertEqual(map.value(forKey: 1), "f")
        XCTAssertEqual(map.value(forKey: 2), "g")
        
        weft.update(site: 2, value: 7)
        XCTAssertEqual(map.timestampWeft, weft)
    }
    
    func testBasicMerge()
    {
        var weft1 = ORDTLocalTimestampWeft()
        var weft2 = ORDTLocalTimestampWeft()
        
        var map1: ORDTTestT = baseMap
        var map2: ORDTTestT = map1
        
        map2.changeOwner(2)
        
        map1.setValue("a", forKey: 1)
        map1.setValue("b", forKey: 1)
        map2.setValue("c", forKey: 1)
        map1.integrate(&map2)
        
        XCTAssertEqual(map1.lamportClock, 2)
        XCTAssertEqual(map2.lamportClock, 1)
        XCTAssertEqual(map1.value(forKey: 1), "b")
        
        weft1.update(site: 1, value: 2)
        weft1.update(site: 2, value: 1)
        XCTAssertEqual(map1.timestampWeft, weft1)
        
        weft2.update(site: 2, value: 1)
        XCTAssertEqual(map2.timestampWeft, weft2)
        
        map2.setValue("d", forKey: 1)
        map1.integrate(&map2)
        
        XCTAssertEqual(map1.value(forKey: 1), "d")
        
        weft1.update(site: 1, value: 2)
        weft1.update(site: 2, value: 2)
        XCTAssertEqual(map1.timestampWeft, weft1)
        
        weft2.update(site: 2, value: 2)
        XCTAssertEqual(map2.timestampWeft, weft2)
        
        map2.integrate(&map1)
        XCTAssertEqual(map1.timestampWeft, map2.timestampWeft)
        XCTAssertEqual(map1, map2)
    }
    
    func generateGnarlyTestCase(_ map1: inout ORDTTestT, _ map2: inout ORDTTestT, _ map3: inout ORDTTestT, _ map4: inout ORDTTestT)
    {
        map1.setValue("a", forKey: 1)
        map1.setValue("b", forKey: 1)
        map2.setValue("c", forKey: 2)
        map2.setValue("d", forKey: 2)
        map2.setValue("e", forKey: 1)
        map3.setValue("f", forKey: 1)
        map3.setValue("g", forKey: 2)
        map3.setValue("h", forKey: 3)
        map3.setValue("i", forKey: 3)
        map4.setValue("j", forKey: 1)
        map4.setValue("k", forKey: 2)
        map4.setValue("l", forKey: 3)
        map4.setValue("m", forKey: 3)
        map4.setValue("n", forKey: 4)
    }
    
    func testMergeValues()
    {
        var map1: ORDTTestT = baseMap
        var map2: ORDTTestT = map1
        var map3: ORDTTestT = map2
        var map4: ORDTTestT = map3
        
        map2.changeOwner(2)
        map3.changeOwner(3)
        map4.changeOwner(4)
        
        generateGnarlyTestCase(&map1, &map2, &map3, &map4)
        
        map1.integrate(&map2)
        map1.integrate(&map3)
        map1.integrate(&map4)
        
        XCTAssert(TestUtils.validate(&map1))
        XCTAssert(TestUtils.validate(&map2))
        XCTAssert(TestUtils.validate(&map3))
        XCTAssert(TestUtils.validate(&map4))
        
        XCTAssertEqual(map1.value(forKey: 1), "e")
        XCTAssertEqual(map1.value(forKey: 2), "k")
        XCTAssertEqual(map1.value(forKey: 3), "m")
        XCTAssertEqual(map1.value(forKey: 4), "n")
        
        XCTAssertEqual(map2.value(forKey: 1), "e")
        XCTAssertEqual(map2.value(forKey: 2), "d")
        
        XCTAssertEqual(map3.value(forKey: 1), "f")
        XCTAssertEqual(map3.value(forKey: 2), "g")
        XCTAssertEqual(map3.value(forKey: 3), "i")
        
        XCTAssertEqual(map4.value(forKey: 1), "j")
        XCTAssertEqual(map4.value(forKey: 2), "k")
        XCTAssertEqual(map4.value(forKey: 3), "m")
        XCTAssertEqual(map4.value(forKey: 4), "n")
    }
    
    func testMergeOperations()
    {
        var map1: ORDTTestT = baseMap
        var map2: ORDTTestT = map1
        var map3: ORDTTestT = map2
        var map4: ORDTTestT = map3
        
        map2.changeOwner(2)
        map3.changeOwner(3)
        map4.changeOwner(4)
        
        generateGnarlyTestCase(&map1, &map2, &map3, &map4)
        
        map1.integrate(&map2)
        map1.integrate(&map3)
        map1.integrate(&map4)
        
        let ops = map1.operations()
        
        let expectedResults = ["a", "f", "j", "b", "e",
                               "c", "d", "g", "k",
                               "h", "l", "i", "m",
                               "n"]
        
        for pair in ops.enumerated()
        {
            XCTAssertEqual(pair.element.value.value, expectedResults[pair.offset])
        }
    }
    
    func testMergeYarns()
    {
        var map1: ORDTTestT = baseMap
        var map2: ORDTTestT = map1
        var map3: ORDTTestT = map2
        var map4: ORDTTestT = map3
        
        map2.changeOwner(2)
        map3.changeOwner(3)
        map4.changeOwner(4)
        
        generateGnarlyTestCase(&map1, &map2, &map3, &map4)
        
        map1.integrate(&map2)
        map1.integrate(&map3)
        map1.integrate(&map4)
        
        let expectedResults = [["a", "b"],
                               ["c", "d", "e"],
                               ["f", "g", "h", "i"],
                               ["j", "k", "l", "m", "n"]]
        
        for i: LUID in 0...3
        {
            let yarn = map1.yarn(forSite: InstancedLUID(id: i + 1))
            
            for pair in yarn.enumerated()
            {
                XCTAssertEqual(pair.element.value.value, expectedResults[Int(i)][pair.offset])
            }
            
            let localYarn = (i == 0 ? map1 : (i == 1 ? map2 : (i == 2 ? map3 : map3))).yarn(forSite: InstancedLUID(id: i + 1))
            
            for pair in localYarn.enumerated()
            {
                XCTAssertEqual(pair.element.value.value, expectedResults[Int(i)][pair.offset])
            }
        }
    }
    
    func testMergeRevisions()
    {
        var map1: ORDTTestT = baseMap
        var map2: ORDTTestT = map1
        var map3: ORDTTestT = map2
        var map4: ORDTTestT = map3
        
        map2.changeOwner(2)
        map3.changeOwner(3)
        map4.changeOwner(4)
        
        generateGnarlyTestCase(&map1, &map2, &map3, &map4)
        
        map1.integrate(&map2)
        map1.integrate(&map3)
        map1.integrate(&map4)
        
        var revWeft1 = ORDTLocalTimestampWeft()
        revWeft1.update(site: 2, value: 2)
        revWeft1.update(site: 3, value: 3)
        revWeft1.update(site: 4, value: 1)
        var revWeft2 = ORDTLocalTimestampWeft()
        revWeft2.update(site: 1, value: 2)
        revWeft2.update(site: 2, value: 1)
        revWeft2.update(site: 3, value: 2)
        revWeft2.update(site: 4, value: 4)
        var revWeft3 = ORDTLocalTimestampWeft()
        revWeft3.update(site: 1, value: 1)
        revWeft3.update(site: 2, value: 3)
        revWeft3.update(site: 3, value: 4)
        
        var rev1 = map1.revision(revWeft1)
        var rev2 = map1.revision(revWeft2)
        var rev3 = map1.revision(revWeft3)
        
        let expectedRev1Ops = ["f", "j",
                               "c", "d", "g",
                               "h"]
        let expectedRev2Ops = ["a", "f", "j", "b",
                               "c", "g", "k",
                               "l", "m"]
        let expectedRev3Ops = ["a", "f", "e",
                               "c", "d", "g",
                               "h", "i"]
        
        let expectedRev1Yarns = [[],
                                 ["c", "d"],
                                 ["f", "g", "h"],
                                 ["j"]]
        let expectedRev2Yarns = [["a", "b"],
                                 ["c"],
                                 ["f", "g"],
                                 ["j", "k", "l", "m"]]
        let expectedRev3Yarns = [["a"],
                                 ["c", "d", "e"],
                                 ["f", "g", "h", "i"]]
        
        XCTAssert(TestUtils.validate(&rev1))
        XCTAssert(TestUtils.validate(&rev2))
        XCTAssert(TestUtils.validate(&rev3))
        
        rev1: do
        {
            XCTAssertEqual(rev1.value(forKey: 1), "j")
            XCTAssertEqual(rev1.value(forKey: 2), "g")
            XCTAssertEqual(rev1.value(forKey: 3), "h")
            
            let ops = rev1.operations()
            for p in ops.enumerated()
            {
                XCTAssertEqual(p.element.value.value, expectedRev1Ops[p.offset])
            }
            
            let revOps = map1.operations(withWeft: revWeft1)
            XCTAssert(revOps.elementsEqual(ops, by: { (a1, a2) -> Bool in a1.id == a2.id }))
            
            for i: LUID in 0...3
            {
                let yarn = rev1.yarn(forSite: InstancedLUID(id: i + 1))
                for pair in yarn.enumerated()
                {
                    XCTAssertEqual(pair.element.value.value, expectedRev1Yarns[Int(i)][pair.offset])
                }
                
                let revYarn = map1.yarn(forSite: InstancedLUID(id: i + 1), withWeft: revWeft1)
                XCTAssert(revYarn.elementsEqual(yarn, by: { (a1, a2) -> Bool in a1.id == a2.id }))
            }
        }
        
        rev2: do
        {
            XCTAssertEqual(rev2.value(forKey: 1), "b")
            XCTAssertEqual(rev2.value(forKey: 2), "k")
            XCTAssertEqual(rev2.value(forKey: 3), "m")
            
            let ops = rev2.operations()
            for p in ops.enumerated()
            {
                XCTAssertEqual(p.element.value.value, expectedRev2Ops[p.offset])
            }
            
            let revOps = map1.operations(withWeft: revWeft2)
            XCTAssert(revOps.elementsEqual(ops, by: { (a1, a2) -> Bool in a1.id == a2.id }))
            
            for i: LUID in 0...3
            {
                let yarn = rev2.yarn(forSite: InstancedLUID(id: i + 1))
                for pair in yarn.enumerated()
                {
                    XCTAssertEqual(pair.element.value.value, expectedRev2Yarns[Int(i)][pair.offset])
                }
                
                let revYarn = map1.yarn(forSite: InstancedLUID(id: i + 1), withWeft: revWeft2)
                XCTAssert(revYarn.elementsEqual(yarn, by: { (a1, a2) -> Bool in a1.id == a2.id }))
            }
        }
        
        rev3: do
        {
            XCTAssertEqual(rev3.value(forKey: 1), "e")
            XCTAssertEqual(rev3.value(forKey: 2), "g")
            XCTAssertEqual(rev3.value(forKey: 3), "i")
            
            let ops = rev3.operations()
            for p in ops.enumerated()
            {
                XCTAssertEqual(p.element.value.value, expectedRev3Ops[p.offset])
            }
            
            let revOps = map1.operations(withWeft: revWeft3)
            XCTAssert(revOps.elementsEqual(ops, by: { (a1, a2) -> Bool in a1.id == a2.id }))
            
            for i: LUID in 0...3
            {
                let yarn = rev3.yarn(forSite: InstancedLUID(id: i + 1))
                for pair in yarn.enumerated()
                {
                    XCTAssertEqual(pair.element.value.value, expectedRev3Yarns[Int(i)][pair.offset])
                }
                
                let revYarn = map1.yarn(forSite: InstancedLUID(id: i + 1), withWeft: revWeft3)
                XCTAssert(revYarn.elementsEqual(yarn, by: { (a1, a2) -> Bool in a1.id == a2.id }))
            }
        }
    }
    
    func testExample()
    {        
        return
        
        let count = 100000
        
        let structSize = MemoryLayout<TestStruct>.size
        let atomSize = MemoryLayout<ORDTMapT.OperationT>.size
        print("Test struct size: \(structSize) bytes")
        print("Test atom size: \(atomSize) bytes")
        print("Predicted memory: \(atomSize * count) bytes")
        
        var map: ORDTMapT!
        var middleWeft: ORDTLocalTimestampWeft!
        var quarterWeft: ORDTLocalTimestampWeft!
        
        measure("Init")
        {
            map = ORDTMapT.init(withOwner: 1, reservingCapacity: count)
            
            for i in 0..<count
            {
                map.setValue(TestStruct.zero, forKey: i + 1)
                
                if i == count * 3 / 4
                {
                    map.changeOwner(100)
                }
                
                if i == count / 2
                {
                    middleWeft = map.timestampWeft
                }
                if i == count / 4
                {
                    quarterWeft = map.timestampWeft
                }
            }
        }
        
        var copy: ORDTMapT!
        
        measure("Create Copy")
        {
            copy = map
        }
        
        measure("Set Copy")
        {
            copy.setValue(TestStruct.zero, forKey: 1)
        }
        
        measure("Validate")
        {
            let _ = TestUtils.validate(&map)
        }
        
        var slice: ORDTMapT.CollectionT!
        
        measure("Create Slice")
        {
            slice = map.operations(withWeft: nil)
        }
        
        measure("Modify Original")
        {
            map.setValue(TestStruct.zero, forKey: 1)
        }
        
        var slice2: ORDTMapT.CollectionT!
        
        measure("Create Revision Slice")
        {
            slice2 = map.operations(withWeft: middleWeft)
        }
        
        measure("Modify Original")
        {
            map.setValue(TestStruct.zero, forKey: 1)
            map.setValue(TestStruct.zero, forKey: 5000)
            map.setValue(TestStruct.zero, forKey: 5000)
            map.setValue(TestStruct.zero, forKey: 5000)
        }
        
        var rev: ORDTMapT!
        
        measure("Create Revision")
        {
            rev = map.revision(middleWeft)
            _ = TestUtils.validate(&rev)
        }
        
        var revSlice: ORDTMapT.CollectionT!
        
        measure("Create Revision Revision Slice")
        {
            revSlice = rev.operations(withWeft: quarterWeft)
        }
        
        var revRev: ORDTMapT!
        
        measure("Create Revision Revision")
        {
            revRev = rev.revision(quarterWeft)
            _ = TestUtils.validate(&revRev)
        }
        
        var yarn1: ORDTMapT.CollectionT!
        var yarn2: ORDTMapT.CollectionT!
        
        measure("Create Original Yarn")
        {
            yarn1 = map.yarn(forSite: 1)
        }
        
        measure("Create Revision Yarn")
        {
            yarn2 = rev.yarn(forSite: 1)
        }
    
        print("Yarn 1: \(yarn1.count), Yarn 2: \(yarn2.count)")
        
        measure("Modify Original")
        {
            map.setValue(TestStruct.zero, forKey: 1)
        }
        
        TestUtils.validate(&rev)
    }
}
