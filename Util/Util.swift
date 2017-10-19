//
//  Util.swift
//  Util
//
//  Created by Alexei Baboulevitch on 2017-10-19.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

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

public func debug(_ closure: (()->()))
{
    #if DEBUG
        closure()
    #endif
}
