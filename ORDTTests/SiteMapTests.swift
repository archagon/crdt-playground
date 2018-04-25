//
//  SiteMapTests.swift
//  ORDTTests
//
//  Created by Alexei Baboulevitch on 2018-4-20.
//  Copyright © 2018 Alexei Baboulevitch. All rights reserved.
//

import Foundation

import XCTest
import CRDTFramework_OSX

class SiteMapTests: ABTestCase
{
    var uuids: [UInt64] = []
    
    override func setUp()
    {
        super.setUp()
        
        for _ in 0..<20
        {
            var rnd: UInt64 = 0
            arc4random_buf(&rnd, MemoryLayout.size(ofValue: rnd))
            uuids.append(rnd)
        }
    }
    
    override func tearDown()
    {
        uuids.removeAll()
        
        super.tearDown()
    }
    
    func testBasics()
    {
        var map = SiteMap<UInt64>.init()
        
        let id0 = map.addUuid(uuids[0])
        let id1 = map.addUuid(uuids[1])
        let id2 = map.addUuid(uuids[2])
        
        XCTAssert(TestUtils.validate(&map))
        
        XCTAssertEqual(map.luid(forUuid: uuids[0]), 1)
        XCTAssertEqual(map.luid(forUuid: uuids[1]), 2)
        XCTAssertEqual(map.luid(forUuid: uuids[2]), 3)
        XCTAssertEqual(id0, 1)
        XCTAssertEqual(id1, 2)
        XCTAssertEqual(id2, 3)
        XCTAssertEqual(map.uuid(forLuid: 0), nil)
        XCTAssertEqual(map.uuid(forLuid: id0), uuids[0])
        XCTAssertEqual(map.uuid(forLuid: id1), uuids[1])
        XCTAssertEqual(map.uuid(forLuid: id2), uuids[2])
        
        let id0a = map.addUuid(uuids[0])
        let id1a = map.addUuid(uuids[1])
        
        XCTAssertEqual(id0a, id0)
        XCTAssertEqual(id1a, id1)
        
        XCTAssertEqual(map.lamportClock, 3)
        XCTAssertEqual(map.timestampWeft, SiteMap<UInt64>.AbsoluteTimestampWeft.init(withMapping:
            [uuids[0]:1, uuids[1]:2, uuids[2]:3]))
        XCTAssertEqual(map.indexWeft, SiteMap<UInt64>.AbsoluteIndexWeft.init(withMapping:
            [uuids[0]:0, uuids[1]:0, uuids[2]:0]))
    }
    
    func testQueries()
    {
        var map1 = SiteMap<UInt64>.init()
        
        uuids[2] = 100
        uuids[3] = 200
        uuids[4] = 10
        uuids[5] = 50
        uuids[6] = 250
        
        let _ = map1.addUuid(uuids[0])
        let _ = map1.addUuid(uuids[1])
        
        var map2 = map1
        
        let _ = map1.addUuid(uuids[2])
        let _ = map1.addUuid(uuids[3])
        let _ = map1.addUuid(uuids[4])
        
        let _ = map2.addUuid(uuids[5])
        let _ = map2.addUuid(uuids[6])
        
        map1.integrate(&map2)
        
        // operations
        let mapOps = map1.operations()
        let testOps = { () -> [SiteMap<UInt64>.OperationT] in
            var ops: [SiteMap<UInt64>.OperationT] = []
            ops.append(SiteMap<UInt64>.OperationT.init(id: SiteMap<UInt64>.OperationT.ID.init(uuid: uuids[0], logicalTimestamp: 1)))
            ops.append(SiteMap<UInt64>.OperationT.init(id: SiteMap<UInt64>.OperationT.ID.init(uuid: uuids[1], logicalTimestamp: 2)))
            ops.append(SiteMap<UInt64>.OperationT.init(id: SiteMap<UInt64>.OperationT.ID.init(uuid: uuids[5], logicalTimestamp: 3)))
            ops.append(SiteMap<UInt64>.OperationT.init(id: SiteMap<UInt64>.OperationT.ID.init(uuid: uuids[2], logicalTimestamp: 3)))
            ops.append(SiteMap<UInt64>.OperationT.init(id: SiteMap<UInt64>.OperationT.ID.init(uuid: uuids[3], logicalTimestamp: 4)))
            ops.append(SiteMap<UInt64>.OperationT.init(id: SiteMap<UInt64>.OperationT.ID.init(uuid: uuids[6], logicalTimestamp: 4)))
            ops.append(SiteMap<UInt64>.OperationT.init(id: SiteMap<UInt64>.OperationT.ID.init(uuid: uuids[4], logicalTimestamp: 5)))
            return ops
        }()
        XCTAssertEqual(mapOps.lazy.map { $0.id }, testOps.lazy.map { $0.id })
        
        // yarns
        let y1 = map1.yarn(forSite: uuids[0])
        let y2 = map1.yarn(forSite: uuids[2])
        let y3 = map1.yarn(forSite: uuids[5])
        let testY1 = [SiteMap<UInt64>.OperationT.init(id: SiteMap<UInt64>.OperationT.ID.init(uuid: uuids[0], logicalTimestamp: 1))]
        let testY2 = [SiteMap<UInt64>.OperationT.init(id: SiteMap<UInt64>.OperationT.ID.init(uuid: uuids[2], logicalTimestamp: 3))]
        let testY3 = [SiteMap<UInt64>.OperationT.init(id: SiteMap<UInt64>.OperationT.ID.init(uuid: uuids[5], logicalTimestamp: 3))]
        XCTAssertEqual(y1.lazy.map { $0.id }, testY1.lazy.map { $0.id })
        XCTAssertEqual(y2.lazy.map { $0.id }, testY2.lazy.map { $0.id })
        XCTAssertEqual(y3.lazy.map { $0.id }, testY3.lazy.map { $0.id })
        
        // maps
        let lToUMap = map1.luidToUuidMap()
        let uToLMap = map1.uuidToLuidMap()
        let testLToUMap: [LUID:UInt64] = [ 1:uuids[0], 2:uuids[1], 3:uuids[5], 4:uuids[2], 5:uuids[3], 6:uuids[6], 7:uuids[4] ]
        let testUToLMap: [UInt64:LUID] = [ uuids[0]:1, uuids[1]:2, uuids[5]:3, uuids[2]:4, uuids[3]:5, uuids[6]:6, uuids[4]:7 ]
        XCTAssertEqual(lToUMap, testLToUMap)
        XCTAssertEqual(uToLMap, testUToLMap)
    }
    
    func testMerge()
    {
        var map1 = SiteMap<UInt64>.init()
        
        uuids[2] = 100
        uuids[3] = 200
        uuids[4] = 10
        uuids[5] = 50
        uuids[6] = 250
        
        let _ = map1.addUuid(uuids[0])
        let _ = map1.addUuid(uuids[1])
        
        var map2 = map1
        
        let _ = map1.addUuid(uuids[2])
        let _ = map1.addUuid(uuids[3])
        let _ = map1.addUuid(uuids[4])
        
        let _ = map2.addUuid(uuids[5])
        let _ = map2.addUuid(uuids[6])
        
        XCTAssert(TestUtils.validate(&map1))
        XCTAssert(TestUtils.validate(&map2))
        XCTAssertEqual(map1.lamportClock, 5)
        XCTAssertEqual(map2.lamportClock, 4)
        
        XCTAssert(!map1.superset(&map2))
        XCTAssert(!map2.superset(&map1))
        
        map1.integrate(&map2)
        
        XCTAssert(TestUtils.validate(&map1))
        XCTAssertEqual(map1.siteCount(), 7)
        XCTAssertEqual(map1.uuid(forLuid: 0), nil)
        XCTAssertEqual(map1.uuid(forLuid: 1), uuids[0])
        XCTAssertEqual(map1.uuid(forLuid: 2), uuids[1])
        XCTAssertEqual(map1.uuid(forLuid: 3), uuids[5])
        XCTAssertEqual(map1.uuid(forLuid: 4), uuids[2])
        XCTAssertEqual(map1.uuid(forLuid: 5), uuids[3])
        XCTAssertEqual(map1.uuid(forLuid: 6), uuids[6])
        XCTAssertEqual(map1.uuid(forLuid: 7), uuids[4])
        XCTAssertEqual(map1.luid(forUuid: uuids[0]), 1)
        XCTAssertEqual(map1.luid(forUuid: uuids[1]), 2)
        XCTAssertEqual(map1.luid(forUuid: uuids[5]), 3)
        XCTAssertEqual(map1.luid(forUuid: uuids[2]), 4)
        XCTAssertEqual(map1.luid(forUuid: uuids[3]), 5)
        XCTAssertEqual(map1.luid(forUuid: uuids[6]), 6)
        XCTAssertEqual(map1.luid(forUuid: uuids[4]), 7)
        
        XCTAssert(map1.superset(&map2))
        XCTAssert(!map2.superset(&map1))
        
        let oldMap1 = map1
        map1.integrate(&map2)
        
        XCTAssert(TestUtils.validate(&map1))
        XCTAssertEqual(map1.siteCount(), oldMap1.siteCount())
        XCTAssertEqual(map1, oldMap1)
        
        map2.integrate(&map1)
        
        XCTAssertEqual(map1, map2)
    }
    
    func testIndexAndMap()
    {
        var map1 = SiteMap<UInt64>.init()
        
        uuids[2] = 50
        uuids[3] = 60
        uuids[4] = 100
        uuids[5] = 150
        uuids[6] = 200
        uuids[7] = 500
        uuids[8] = 600
        uuids[9] = 70
        uuids[10] = 80
        
        let _ = map1.addUuid(uuids[0]) //1
        let _ = map1.addUuid(uuids[1]) //2
        
        var map2 = map1
        
        let _ = map1.addUuid(uuids[2]) //3
        let _ = map1.addUuid(uuids[3]) //4
        
        let clock = map1.lamportClock
        map2.timeFunction = { return clock }
            
        let _ = map2.addUuid(uuids[4]) //3
        let _ = map2.addUuid(uuids[5]) //4
        let _ = map2.addUuid(uuids[6]) //5
        
        var map3 = map2
        
        let _ = map2.addUuid(uuids[7]) //6
        let _ = map2.addUuid(uuids[8]) //7
        
        let _ = map3.addUuid(uuids[9]) //6
        let _ = map3.addUuid(uuids[10]) //7
        let _ = map3.addUuid(uuids[11]) //8
        
        XCTAssert(!map1.superset(&map2))
        XCTAssert(!map1.superset(&map3))
        XCTAssert(!map2.superset(&map1))
        XCTAssert(!map2.superset(&map3))
        XCTAssert(!map3.superset(&map1))
        XCTAssert(!map3.superset(&map2))
        
        var map1Integ = map1
        var index = map1Integ.integrateReturningFirstDiffIndex(&map2)
        
        XCTAssertEqual(index, 4)
        
        var map2Integ = map2
        let siteMap2 = SiteMap<UInt64>.indexMap(localSiteIndex: map2, remoteSiteIndex: map3)
        index = map2Integ.integrateReturningFirstDiffIndex(&map3)
        
        XCTAssertEqual(index, 5)
        XCTAssertEqual(siteMap2, [6:7, 7:9])
        
        var oldMap1 = map1
        map1.integrate(&map2)
        map1.integrate(&map3)
        let m1 = map1.integrateReturningFirstDiffIndex(&oldMap1)
        let m2 = map1.integrateReturningFirstDiffIndex(&map2)
        let m3 = map1.integrateReturningFirstDiffIndex(&map3)
        
        XCTAssert(TestUtils.validate(&map1))
        XCTAssertEqual(m1, nil)
        XCTAssertEqual(m2, nil)
        XCTAssertEqual(m3, nil)
        
        var map4 = SiteMap<UInt64>.init()
        map4.timeFunction = { return 7 }
        let _ = map4.addUuid(0)
        
        let siteMap1 = SiteMap<UInt64>.indexMap(localSiteIndex: map1, remoteSiteIndex: map4)
        let i = map1.integrateReturningFirstDiffIndex(&map4)
        
        XCTAssert(TestUtils.validate(&map1))
        XCTAssertEqual(i, 7)
        XCTAssertEqual(siteMap1, [8:9, 9:10, 10:11, 11:12, 12:13])
        
        map2.integrate(&map1)
        map3.integrate(&map2)
        
        XCTAssertEqual(map1, map2)
        XCTAssertEqual(map2, map3)
    }
}
