//
//  ExternUtils.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2018-4-12.
//  Copyright © 2018 Alexei Baboulevitch. All rights reserved.
//

import Foundation

// https://stackoverflow.com/a/26679191/89812
extension Array {
    func insertionIndexOf(elem: Element, isOrderedBefore: (Element, Element) -> Bool) -> Int {
        var lo = 0
        var hi = self.count - 1
        while lo <= hi {
            let mid = (lo + hi)/2
            if isOrderedBefore(self[mid], elem) {
                lo = mid + 1
            } else if isOrderedBefore(elem, self[mid]) {
                hi = mid - 1
            } else {
                return mid // found at position mid
            }
        }
        return lo // not found, would be inserted at position lo
    }
}
