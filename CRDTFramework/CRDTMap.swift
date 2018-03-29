//
//  CRDTMap.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-27.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

// a simple LWW map
final class CRDTMap
    <K: Hashable & Codable, V: Hashable & Codable, S: Hashable & Codable & Comparable> :
    CvRDT, ApproxSizeable, NSCopying, Codable {
    public typealias KeyT = K
    public typealias ValueT = V
    public typealias SiteT = S

    // requirement: IDs can be placed in a total order, i.e. ordered and no duplicates
    struct IDPair: Codable, Hashable, Comparable {
        let clock: Clock
        let site: SiteT

        init(_ clock: Clock, _ site: SiteT) {
            self.clock = clock
            self.site = site
        }

        public static func ==(lhs: IDPair, rhs: IDPair) -> Bool {
            return lhs.clock == rhs.clock && lhs.site == rhs.site
        }

        public var hashValue: Int {
            return clock.hashValue ^ site.hashValue
        }

        static func <(lhs: IDPair, rhs: IDPair) -> Bool {
            return (lhs.clock == rhs.clock ? lhs.site < rhs.site : lhs.clock < rhs.clock)
        }
    }

    struct ClockValuePair: Codable, Hashable {
        let id: IDPair
        let value: ValueT

        init(_ id: IDPair, _ value: ValueT) {
            self.id = id
            self.value = value
        }

        public static func ==(lhs: ClockValuePair, rhs: ClockValuePair) -> Bool {
            return lhs.id == rhs.id && lhs.value == rhs.value
        }

        public var hashValue: Int {
            return id.hashValue ^ value.hashValue
        }
    }

    // this is the main state
    public private(set) var map: [KeyT:ClockValuePair]

    // these are merely convenience variables and do not affect hashes, etc. (they are still transferred, though)
    public var owner: SiteT
    public private(set) var lamportTimestamp: CRDTCounter<Clock>

    public init(withOwner owner: SiteT) {
        self.map = [:]
        self.owner = owner
        self.lamportTimestamp = CRDTCounter<Clock>.init(withValue: 0)
    }

    func copy(with zone: NSZone? = nil) -> Any {
        let returnValue = CRDTMap(withOwner: self.owner)

        returnValue.map = self.map
        returnValue.owner = self.owner
        returnValue.lamportTimestamp = self.lamportTimestamp.copy() as! CRDTCounter<Clock>

        return returnValue
    }

    // AB: updatingId is for users who want to build new CRDTs on top of this basic one, e.g. CRDTs that remap
    // ids in certain situations; use with extreme caution since it can break CRDT invariants if used incorrectly
    public func setValue(_ value: ValueT, forKey key: KeyT, updatingId: Bool = true) {
        if let existingValue = map[key] {
            map[key] = ClockValuePair(updatingId ? IDPair(lamportTimestamp.increment(), owner) : existingValue.id, value)
        }
        else if updatingId {
            map[key] = ClockValuePair(IDPair(lamportTimestamp.increment(), owner), value)
        }
        else {
            precondition(false, "cannot set value without updating id for missing key")
        }
    }

    public func value(forKey key: KeyT) -> ValueT? {
        return map[key]?.value
    }

    public func integrate(_ v: inout CRDTMap) {
        lamportTimestamp.integrate(&v.lamportTimestamp)

        for pair in v.map {
            if let existingValue = map[pair.key] {
                if pair.value.id > existingValue.id {
                    map[pair.key] = pair.value
                }
            }
            else {
                map[pair.key] = pair.value
            }
        }
    }

    public func superset(_ v: inout CRDTMap) -> Bool {
        if self.map.count < v.map.count {
            return false
        }

        for remotePair in v.map {
            guard let localPair = self.map[remotePair.key] else {
                return false
            }

            if remotePair.value.id > localPair.id {
                return false
            }
        }

        return true
    }

    public func validate() throws -> Bool {
        for pair in map {
            if pair.value.id.clock > lamportTimestamp.counter {
                return false
            }
        }

        return try lamportTimestamp.validate()
    }

    public func sizeInBytes() -> Int {
        return lamportTimestamp.sizeInBytes() + MemoryLayout<SiteT>.size + map.count * (MemoryLayout<KeyT>.size + MemoryLayout<ClockValuePair>.size)
    }

    public static func ==(lhs: CRDTMap, rhs: CRDTMap) -> Bool {
        return lhs.map == rhs.map
    }

    public var hashValue: Int {
        return map.reduce(0) { ($0 ^ $1.key.hashValue) ^ $1.value.hashValue }
    }
}

// for "degenerate" maps that simply act as, e.g., site registers
extension CRDTMap where K == S {
    func setValue(_ value: ValueT) {
        setValue(value, forKey: owner)
    }
}
