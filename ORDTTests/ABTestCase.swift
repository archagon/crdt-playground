//
//  ABTestCase.swift
//  ORDTTests
//
//  Created by Alexei Baboulevitch on 2018-4-13.
//  Copyright © 2018 Alexei Baboulevitch. All rights reserved.
//

import XCTest

class ABTestCase: XCTestCase
{
    override class var defaultPerformanceMetrics: [XCTPerformanceMetric]
    {
        return [
            XCTPerformanceMetric.wallClockTime,
            //XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_TransientVMAllocationsKilobytes"),
            XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_TemporaryHeapAllocationsKilobytes"),
            //XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_HighWaterMarkForVMAllocations"),
            XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_TotalHeapAllocationsKilobytes"),
            //XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_PersistentVMAllocations"),
            //XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_PersistentHeapAllocations"),
            //XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_TransientHeapAllocationsKilobytes"),
            //XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_PersistentHeapAllocationsNodes"),
            XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_HighWaterMarkForHeapAllocations"),
            //XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_TransientHeapAllocationsNodes")
        ]
    }
    
    /// Calls `measure` and prints some relevant stats.
    func measure(_ name: String?, _ block: () -> Void)
    {
        var sm: Int64 = 0
        var em: Int64 = 0
        func pm(_ name: String? = nil)
        {
            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = NumberFormatter.Style.decimal
            let formattedNumber = numberFormatter.string(from: NSNumber(value: (em - sm)))!
            print("Used \(name != nil ? name! + " " : "")memory: \(formattedNumber) bytes")
        }

        sm = systemMemory()
        //measure(block)
        block()
        em = systemMemory()
        pm(name)
    }
}
