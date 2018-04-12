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

class ORDTTests: XCTestCase
{
    override func setUp()
    {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown()
    {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testExample()
    {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        
        func validate( _ ordt: inout ORDTMap<Int, TestStruct>)
        {
            do { let _ = try ordt.validate() } catch { print("Error: \(error)") }
        }
        
        let count = 100000
        
        var sm: Int64 = 0
        var em: Int64 = 0
        
        sm = systemMemory()
        var map = ORDTMap<Int, TestStruct>.init(withOwner: 0)
        var middleWeft: Weft<SiteId>!
        for i in 0..<count
        {
            map.setValue(TestStruct.zero, forKey: i)
            if i == count / 2
            {
                middleWeft = map.indexWeft
            }
        }
        em = systemMemory()
        print("Used memory: \(em-sm) bytes")
        
        sm = systemMemory()
        validate(&map)
        em = systemMemory()
        print("Used memory: \(em-sm) bytes")
        
        let structSize = MemoryLayout<TestStruct>.size
        let atomSize = MemoryLayout<ORDTMap<Int, TestStruct>.OperationT>.size
        print("Test struct size: \(structSize) bytes")
        print("Test atom size: \(atomSize) bytes")
        print("Predicted memory: \(atomSize * count) bytes")
        print("Used memory: \(em-sm) bytes")
        
        sm = systemMemory()
        var slice = map.operations(withWeft: nil)
        em = systemMemory()
        print("Used memory: \(em-sm) bytes")
        
        sm = systemMemory()
        map.setValue(TestStruct.zero, forKey: 0)
        em = systemMemory()
        print("Used memory: \(em-sm) bytes")
        
        sm = systemMemory()
        var slice2 = map.operations(withWeft: middleWeft)
        em = systemMemory()
        print("Used memory: \(em-sm) bytes")
        
        sm = systemMemory()
        map.setValue(TestStruct.zero, forKey: 0)
        em = systemMemory()
        print("Used memory: \(em-sm) bytes")
        
        sm = systemMemory()
        var rev = map.revision(middleWeft)
        em = systemMemory()
        print("Used memory: \(em-sm) bytes")
        
        validate(&rev)
    }
    
    func testPerformanceExample()
    {
        // This is an example of a performance test case.
        self.measure
        {
            // Put the code you want to measure the time of here.
        }
    }
}
