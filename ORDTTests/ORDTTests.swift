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

class ORDTTests: ABTestCase
{
    typealias ORDTMapT = ORDTMap<Int,TestStruct>
    typealias ORDTTestT = ORDTMap<SiteId,String>
    
    var baseMap: ORDTTestT!
    
    override func setUp()
    {
        super.setUp()
        
        createMap: do
        {
            baseMap = ORDTTestT.init(withOwner: 0)
        }
    }
    
    override func tearDown()
    {
        baseMap = nil
        
        super.tearDown()
    }
    
    func validate<K,V>(_ ordt: inout ORDTMap<K,V>) -> Bool
    {
        do
        {
            let v = try ordt.validate()
            return v
        }
        catch
        {
            print("Error: \(error)")
            return false
        }
    }
    func validate<K,V>(_ ordt: inout ORDTMap<K,V>!) -> Bool
    {
        do
        {
            let v = try ordt.validate()
            return v
        }
        catch
        {
            print("Error: \(error)")
            return false
        }
    }
    
    func testBasicSetValue()
    {
        var weft = Weft<SiteId>()
        
        var map: ORDTTestT = baseMap
        
        map.setValue("a")
        
        XCTAssert(validate(&map))
        XCTAssertEqual(map.value(forKey: 0), "a")
        
        map.setValue("b")
        map.setValue("c")
        
        XCTAssert(validate(&map))
        XCTAssertEqual(map.value(forKey: 0), "c")
        
        weft.update(site: 0, index: 2)
        XCTAssertEqual(map.indexWeft, weft)
        
        map.setValue("d", forKey: 1)
        map.setValue("e", forKey: 1)
        
        XCTAssertEqual(map.value(forKey: 1), "e")
        
        weft.update(site: 0, index: 4)
        XCTAssertEqual(map.indexWeft, weft)
        
        map.changeOwner(1)
        
        map.setValue("f", forKey: 0)
        map.setValue("g", forKey: 1)
        
        XCTAssertEqual(map.value(forKey: 0), "f")
        XCTAssertEqual(map.value(forKey: 1), "g")
        
        weft.update(site: 1, index: 1)
        XCTAssertEqual(map.indexWeft, weft)
    }
    
    func testBasicMerge()
    {
        var weft1 = Weft<SiteId>()
        var weft2 = Weft<SiteId>()
        
        var map1: ORDTTestT = baseMap
        var map2: ORDTTestT = map1
        
        map2.changeOwner(1)
        
        map1.setValue("a", forKey: 0)
        map1.setValue("b", forKey: 0)
        map2.setValue("c", forKey: 0)
        map1.integrate(&map2)
        
        XCTAssertEqual(map1.lamportClock, 2)
        XCTAssertEqual(map2.lamportClock, 1)
        XCTAssertEqual(map1.value(forKey: 0), "b")
        
        weft1.update(site: 0, index: 1)
        weft1.update(site: 1, index: 0)
        XCTAssertEqual(map1.indexWeft, weft1)
        
        weft2.update(site: 1, index: 0)
        XCTAssertEqual(map2.indexWeft, weft2)
        
        map2.setValue("d", forKey: 0)
        map1.integrate(&map2)
        
        XCTAssertEqual(map1.value(forKey: 0), "d")
        
        weft1.update(site: 0, index: 1)
        weft1.update(site: 1, index: 1)
        XCTAssertEqual(map1.indexWeft, weft1)
        
        weft2.update(site: 1, index: 1)
        XCTAssertEqual(map2.indexWeft, weft2)
        
        map2.integrate(&map1)
        XCTAssertEqual(map1.indexWeft, map2.indexWeft)
        XCTAssertEqual(map1, map2)
    }
    
    func generateGnarlyTestCase(_ map1: inout ORDTTestT, _ map2: inout ORDTTestT, _ map3: inout ORDTTestT, _ map4: inout ORDTTestT)
    {
        map1.setValue("a", forKey: 0)
        map1.setValue("b", forKey: 0)
        map2.setValue("c", forKey: 1)
        map2.setValue("d", forKey: 1)
        map2.setValue("e", forKey: 0)
        map3.setValue("f", forKey: 0)
        map3.setValue("g", forKey: 1)
        map3.setValue("h", forKey: 2)
        map3.setValue("i", forKey: 2)
        map4.setValue("j", forKey: 0)
        map4.setValue("k", forKey: 1)
        map4.setValue("l", forKey: 2)
        map4.setValue("m", forKey: 2)
        map4.setValue("n", forKey: 3)
    }
    
    func testMergeValues()
    {
        var map1: ORDTTestT = baseMap
        var map2: ORDTTestT = map1
        var map3: ORDTTestT = map2
        var map4: ORDTTestT = map3
        
        map2.changeOwner(1)
        map3.changeOwner(2)
        map4.changeOwner(3)
        
        generateGnarlyTestCase(&map1, &map2, &map3, &map4)
        
        map1.integrate(&map2)
        map1.integrate(&map3)
        map1.integrate(&map4)
        
        XCTAssert(validate(&map1))
        XCTAssert(validate(&map2))
        XCTAssert(validate(&map3))
        XCTAssert(validate(&map4))
        
        XCTAssertEqual(map1.value(forKey: 0), "e")
        XCTAssertEqual(map1.value(forKey: 1), "k")
        XCTAssertEqual(map1.value(forKey: 2), "m")
        XCTAssertEqual(map1.value(forKey: 3), "n")
        
        XCTAssertEqual(map2.value(forKey: 0), "e")
        XCTAssertEqual(map2.value(forKey: 1), "d")
        
        XCTAssertEqual(map3.value(forKey: 0), "f")
        XCTAssertEqual(map3.value(forKey: 1), "g")
        XCTAssertEqual(map3.value(forKey: 2), "i")
        
        XCTAssertEqual(map4.value(forKey: 0), "j")
        XCTAssertEqual(map4.value(forKey: 1), "k")
        XCTAssertEqual(map4.value(forKey: 2), "m")
        XCTAssertEqual(map4.value(forKey: 3), "n")
    }
    
    func testMergeOperations()
    {
        var map1: ORDTTestT = baseMap
        var map2: ORDTTestT = map1
        var map3: ORDTTestT = map2
        var map4: ORDTTestT = map3
        
        map2.changeOwner(1)
        map3.changeOwner(2)
        map4.changeOwner(3)
        
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
        
        map2.changeOwner(1)
        map3.changeOwner(2)
        map4.changeOwner(3)
        
        generateGnarlyTestCase(&map1, &map2, &map3, &map4)
        
        map1.integrate(&map2)
        map1.integrate(&map3)
        map1.integrate(&map4)
        
        let expectedResults = [["a", "b"],
                               ["c", "d", "e"],
                               ["f", "g", "h", "i"],
                               ["j", "k", "l", "m", "n"]]
        
        for i in 0...3
        {
            let yarn = map1.yarn(forSite: SiteId(i))
            
            for pair in yarn.enumerated()
            {
                XCTAssertEqual(pair.element.value.value, expectedResults[i][pair.offset])
            }
            
            let localYarn = (i == 0 ? map1 : (i == 1 ? map2 : (i == 2 ? map3 : map3))).yarn(forSite: SiteId(i))
            
            for pair in localYarn.enumerated()
            {
                XCTAssertEqual(pair.element.value.value, expectedResults[i][pair.offset])
            }
        }
    }
    
    func testMergeRevisions()
    {
        var map1: ORDTTestT = baseMap
        var map2: ORDTTestT = map1
        var map3: ORDTTestT = map2
        var map4: ORDTTestT = map3
        
        map2.changeOwner(1)
        map3.changeOwner(2)
        map4.changeOwner(3)
        
        generateGnarlyTestCase(&map1, &map2, &map3, &map4)
        
        map1.integrate(&map2)
        map1.integrate(&map3)
        map1.integrate(&map4)
        
        var revWeft1 = Weft<SiteId>()
        revWeft1.update(site: 1, index: 1)
        revWeft1.update(site: 2, index: 2)
        revWeft1.update(site: 3, index: 0)
        var revWeft2 = Weft<SiteId>()
        revWeft2.update(site: 0, index: 1)
        revWeft2.update(site: 1, index: 0)
        revWeft2.update(site: 2, index: 1)
        revWeft2.update(site: 3, index: 3)
        var revWeft3 = Weft<SiteId>()
        revWeft3.update(site: 0, index: 0)
        revWeft3.update(site: 1, index: 2)
        revWeft3.update(site: 2, index: 3)
        
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
        
        XCTAssert(validate(&rev1))
        XCTAssert(validate(&rev2))
        XCTAssert(validate(&rev3))
        
        rev1: do
        {
            XCTAssertEqual(rev1.value(forKey: 0), "j")
            XCTAssertEqual(rev1.value(forKey: 1), "g")
            XCTAssertEqual(rev1.value(forKey: 2), "h")
            
            let ops = rev1.operations()
            for p in ops.enumerated()
            {
                XCTAssertEqual(p.element.value.value, expectedRev1Ops[p.offset])
            }
            
            let revOps = map1.operations(withWeft: revWeft1)
            XCTAssert(revOps.elementsEqual(ops, by: { (a1, a2) -> Bool in a1.id == a2.id }))
            
            for i in 0...3
            {
                let yarn = rev1.yarn(forSite: SiteId(i))
                for pair in yarn.enumerated()
                {
                    XCTAssertEqual(pair.element.value.value, expectedRev1Yarns[i][pair.offset])
                }
                
                let revYarn = map1.yarn(forSite: SiteId(i), withWeft: revWeft1)
                XCTAssert(revYarn.elementsEqual(yarn, by: { (a1, a2) -> Bool in a1.id == a2.id }))
            }
        }
        
        rev2: do
        {
            XCTAssertEqual(rev2.value(forKey: 0), "b")
            XCTAssertEqual(rev2.value(forKey: 1), "k")
            XCTAssertEqual(rev2.value(forKey: 2), "m")
            
            let ops = rev2.operations()
            for p in ops.enumerated()
            {
                XCTAssertEqual(p.element.value.value, expectedRev2Ops[p.offset])
            }
            
            let revOps = map1.operations(withWeft: revWeft2)
            XCTAssert(revOps.elementsEqual(ops, by: { (a1, a2) -> Bool in a1.id == a2.id }))
            
            for i in 0...3
            {
                let yarn = rev2.yarn(forSite: SiteId(i))
                for pair in yarn.enumerated()
                {
                    XCTAssertEqual(pair.element.value.value, expectedRev2Yarns[i][pair.offset])
                }
                
                let revYarn = map1.yarn(forSite: SiteId(i), withWeft: revWeft2)
                XCTAssert(revYarn.elementsEqual(yarn, by: { (a1, a2) -> Bool in a1.id == a2.id }))
            }
        }
        
        rev3: do
        {
            XCTAssertEqual(rev3.value(forKey: 0), "e")
            XCTAssertEqual(rev3.value(forKey: 1), "g")
            XCTAssertEqual(rev3.value(forKey: 2), "i")
            
            let ops = rev3.operations()
            for p in ops.enumerated()
            {
                XCTAssertEqual(p.element.value.value, expectedRev3Ops[p.offset])
            }
            
            let revOps = map1.operations(withWeft: revWeft3)
            XCTAssert(revOps.elementsEqual(ops, by: { (a1, a2) -> Bool in a1.id == a2.id }))
            
            for i in 0...3
            {
                let yarn = rev3.yarn(forSite: SiteId(i))
                for pair in yarn.enumerated()
                {
                    XCTAssertEqual(pair.element.value.value, expectedRev3Yarns[i][pair.offset])
                }
                
                let revYarn = map1.yarn(forSite: SiteId(i), withWeft: revWeft3)
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
        var middleWeft: Weft<SiteId>!
        var quarterWeft: Weft<SiteId>!
        
        measure("Init")
        {
            map = ORDTMapT.init(withOwner: 0, reservingCapacity: count)
            
            for i in 0..<count
            {
                map.setValue(TestStruct.zero, forKey: i)
                
                if i == count * 3 / 4
                {
                    map.changeOwner(100)
                }
                
                if i == count / 2
                {
                    middleWeft = map.indexWeft
                }
                if i == count / 4
                {
                    quarterWeft = map.indexWeft
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
            copy.setValue(TestStruct.zero, forKey: 0)
        }
        
        measure("Validate")
        {
            validate(&map)
        }
        
        var slice: ORDTMapT.CollectionT!
        
        measure("Create Slice")
        {
            slice = map.operations(withWeft: nil)
        }
        
        measure("Modify Original")
        {
            map.setValue(TestStruct.zero, forKey: 0)
        }
        
        var slice2: ORDTMapT.CollectionT!
        
        measure("Create Revision Slice")
        {
            slice2 = map.operations(withWeft: middleWeft)
        }
        
        measure("Modify Original")
        {
            map.setValue(TestStruct.zero, forKey: 0)
            map.setValue(TestStruct.zero, forKey: 5000)
            map.setValue(TestStruct.zero, forKey: 5000)
            map.setValue(TestStruct.zero, forKey: 5000)
        }
        
        var rev: ORDTMapT!
        
        measure("Create Revision")
        {
            rev = map.revision(middleWeft)
            validate(&rev)
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
            validate(&revRev)
        }
        
        var yarn1: ORDTMapT.CollectionT!
        var yarn2: ORDTMapT.CollectionT!
        
        measure("Create Original Yarn")
        {
            yarn1 = map.yarn(forSite: 0)
        }
        
        measure("Create Revision Yarn")
        {
            yarn2 = rev.yarn(forSite: 0)
        }
    
        print("Yarn 1: \(yarn1.count), Yarn 2: \(yarn2.count)")
        
        measure("Modify Original")
        {
            map.setValue(TestStruct.zero, forKey: 0)
        }
        
        validate(&rev)
    }
}
