//
//  Util.swift
//  Util
//
//  Created by Alexei Baboulevitch on 2017-10-19.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

// TODO: make this its own framework: https://stackoverflow.com/questions/26811170/how-to-create-a-single-shared-framework-between-ios-and-os-x

import Foundation
import CoreGraphics
import QuartzCore

var _timeMe = { ()->((()->(),String,Int)->()) in
    var values: [String:(count:Int,sum:CFTimeInterval)] = [:]

    func _innerTimeMe(_ closure: (()->()), _ name: String, every: Int) {
        let startTime = CACurrentMediaTime()
        closure()
        let endTime = CACurrentMediaTime()

        let shouldPrint: Bool
        let printValue: CFTimeInterval
        if every == 0 {
            shouldPrint = true
            printValue = (endTime - startTime)
        }
        else {
            if let pair = values[name] {
                if pair.count % every == 0 {
                    shouldPrint = true
                    printValue = pair.sum / CFTimeInterval(pair.count)
                    values[name] = (1, (endTime - startTime))
                }
                else {
                    shouldPrint = false
                    printValue = 0
                    values[name] = (pair.count + 1, pair.sum + (endTime - startTime))
                }
            }
            else {
                shouldPrint = false
                printValue = 0
                values[name] = (1, (endTime - startTime))
            }
        }
        if shouldPrint {
            print("\(name) time: \(String(format: "%.2f", printValue * 1000)) ms")
        }
    }

    return _innerTimeMe
}()
public func timeMe(_ closure: (()->()), _ name: String, every: Int = 0) {
    return _timeMe(closure, name, every)
}


public func debug(_ closure: (()->())) {
    #if DEBUG
        closure()
    #endif
}


public func warning(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String/* = default, file: StaticString = #file, line: UInt = #line*/) {
    #if DEBUG
        if !condition() {
            print("WARNING: \(message())")
        }
    #endif
}


func onMain(_ async: Bool, _ block: @escaping ()->()) {
    if Thread.current.isMainThread {
        block()
    }
    else {
        if async {
            DispatchQueue.main.async { block() }
        }
        else {
            DispatchQueue.main.sync { block() }
        }
    }
}

func onMain(_ block: @escaping ()->()) {
    onMain(false, block)
}


public func rand<T: FixedWidthInteger>(_ max: T = T.max) -> T {
    return T(arc4random_uniform(UInt32(max)))
}
public func rand() -> Float {
    return Float(Double(arc4random())/Double(UInt32.max))
}
public func rand() -> Double {
    return Double(arc4random())/Double(UInt32.max)
}


public struct Pair<T1: Codable, T2: Codable>: Codable {
    public let o1: T1
    public let o2: T2
}
