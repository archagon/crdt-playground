//
//  CRDTCausalTreesBasicTypes.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-18.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

public protocol DefaultInitializable { init() }
public protocol Zeroable { static var zero: Self { get } }

public protocol CRDTSiteUUIDT: DefaultInitializable, CustomStringConvertible, Hashable, Zeroable, Comparable, Codable {}
public protocol CRDTValueT: DefaultInitializable, IndexRemappable, Codable {}

public protocol CRDTValueAtomPrintable { var atomDescription: String { get } }
public protocol CRDTValueReference { var reference: AtomId { get } } //returns NullAtomId if no reference
public protocol CRDTValueRelationQueries { var childless: Bool { get } }

// TODO: rename these to be less generic
public typealias SiteId = Int16
public typealias Clock = Int64
public typealias ArrayType = Array //AB: ContiguousArray makes me feel safer, but is not Codable by default :(

public typealias YarnIndex = Int32
public typealias WeaveIndex = Int32
public typealias AllYarnsIndex = Int32 //TODO: this is underused -- mistakenly use YarnsIndex

// no other atoms can have these clock numbers
public let ControlSite: SiteId = SiteId(0)
public let StartClock: Clock = Clock(1)
public let NullSite: SiteId = SiteId(SiteId.max)
public let NullClock: Clock = Clock(0)
public let NullIndex: YarnIndex = -1 //max (NullIndex, index) needs to always return index
public let NullAtomId: AtomId = AtomId(site: NullSite, index: NullIndex)

public protocol AtomIdType: Comparable, Hashable, CustomStringConvertible, Codable
{
    associatedtype SiteT: CRDTSiteUUIDT
    
    var site: SiteT { get }
    var index: YarnIndex { get }
    
    init(site: SiteT, index: YarnIndex)
}
extension AtomIdType
{
    public static func ==(lhs: Self, rhs: Self) -> Bool
    {
        return lhs.site == rhs.site && lhs.index == rhs.index
    }
    
    // WARNING: this does not mean anything structurally, and is just used for ordering non-causal atoms
    public static func <(lhs: Self, rhs: Self) -> Bool
    {
        return (lhs.site == rhs.site ? lhs.index < rhs.index : lhs.site < rhs.site)
    }

    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(site)
        hasher.combine(index)
    }
}

public struct AtomId: AtomIdType
{
    public let site: SiteId
    public let index: YarnIndex
    
    public init(site: SiteId, index: YarnIndex)
    {
        self.site = site
        self.index = index
    }
    
    public var description: String
    {
        get
        {
            if site == NullSite
            {
                return "x:x"
            }
            else
            {
                return "\(site):\(index)"
            }
        }
    }
}

// TODO: consistent naming
public struct AbsoluteAtomId<S: CRDTSiteUUIDT>: AtomIdType
{
    public let site: S
    public let index: YarnIndex
    
    public init(site: S, index: YarnIndex)
    {
        self.site = site
        self.index = index
    }
    
    public var description: String
    {
        get
        {
            return "\(site):\(index)"
        }
    }
}

public struct Atom<ValueT: CRDTValueT>: CustomStringConvertible, IndexRemappable, Codable
{
    public var site: SiteId
    public var causingSite: SiteId
    public let index: YarnIndex
    public let causingIndex: YarnIndex
    public let timestamp: YarnIndex
    public var value: ValueT
    
    public init(id: AtomId, cause: AtomId, timestamp: YarnIndex, value: ValueT)
    {
        self.site = id.site
        self.causingSite = cause.site
        self.index = id.index
        self.causingIndex = cause.index
        self.timestamp = timestamp
        self.value = value
    }

    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(site)
        hasher.combine(causingSite)
        hasher.combine(index)
        hasher.combine(causingIndex)
        hasher.combine(timestamp)
    }
    
    public var id: AtomId
    {
        get
        {
            return AtomId(site: site, index: index)
        }
    }
    
    public var cause: AtomId
    {
        get
        {
            return AtomId(site: causingSite, index: causingIndex)
        }
    }
    
    public var description: String
    {
        get
        {
            return "\(id)-\(cause)"
        }
    }
    
    public var debugDescription: String
    {
        get
        {
            return "\(id): c[\(cause)], \(value)"
        }
    }
    
    public var metadata: AtomMetadata
    {
        return AtomMetadata(id: id, cause: cause, timestamp: timestamp)
    }
    
    public mutating func remapIndices(_ map: [SiteId:SiteId])
    {
        if let newOwner = map[site]
        {
            site = newOwner
        }
        
        if let newOwner = map[causingSite]
        {
            causingSite = newOwner
        }
        
        value.remapIndices(map)
    }
}

// avoids having to generify every freakin' view controller
public struct AtomMetadata
{
    public let id: AtomId
    public let cause: AtomId
    public let timestamp: YarnIndex
}

public protocol WeftType: Equatable, CustomStringConvertible
{
    associatedtype SiteT: CRDTSiteUUIDT
    
    init()
    
    // TODO: I don't like that this tiny structure has to be malloc'd
    var mapping: [SiteT:YarnIndex] { get set }
    
    mutating func update(weft: Self)
    mutating func update(site: SiteT, index: YarnIndex)
}
extension WeftType
{
    public static func ==(lhs: Self, rhs: Self) -> Bool
    {
        if lhs.mapping.count != rhs.mapping.count
        {
            return false
        }
        
        for (k,_) in lhs.mapping
        {
            if lhs.mapping[k] != rhs.mapping[k]
            {
                return false
            }
        }
        
        return true
    }
    
    public var hashValue: Int
    {
        var hash = 0
        
        // TODO: is this hashvalue correct?
        for (i,pair) in mapping.enumerated()
        {
            if i == 0
            {
                hash = pair.key.hashValue
                hash ^= pair.value.hashValue
            }
            else
            {
                hash ^= pair.key.hashValue
                hash ^= pair.value.hashValue
            }
        }
        
        return hash
    }
    
    public var description: String
    {
        get
        {
            var string = "["
            let sites = Array<SiteT>(mapping.keys).sorted()
            for (i,site) in sites.enumerated()
            {
                if i != 0
                {
                    string += ", "
                }
                string += "\(site):\(mapping[site]!)"
            }
            string += "]"
            return string
        }
    }

    public mutating func update(weft: Self)
    {
        for (site, index) in weft.mapping
        {
            update(site: site, index: index)
        }
    }
    
    public mutating func update(site: SiteT, index: YarnIndex)
    {
        mapping[site] = max(mapping[site] ?? NullIndex, index)
    }
}
// TODO: why don't these belong in the struct definition?
extension WeftType where SiteT == SiteId
{
    public func included(_ atom: AtomId) -> Bool {
        if atom == NullAtomId
        {
            return true //useful default when generating causal blocks for non-causal atoms
        }
        if let index = mapping[atom.site] {
            if atom.index <= index {
                return true
            }
        }
        return false
    }

    public mutating func update(site: SiteT, index: YarnIndex)
    {
        if site == NullAtomId.site { return }
        mapping[site] = max(mapping[site] ?? NullIndex, index)
    }
    
    public mutating func update(atom: AtomId) {
        if atom == NullAtomId { return }
        update(site: atom.site, index: atom.index)
    }
}

// absolute units -- for external use
public struct Weft<T: CRDTSiteUUIDT>: WeftType
{
    public var mapping: [T:YarnIndex] = [:]
    
    public init() {}
    
    public func isSuperset(of other: Weft<T>) -> Bool
    {
        for (uuid,index) in other.mapping
        {
            guard let myIndex = self.mapping[uuid] else
            {
                return false
            }
            
            if !(myIndex >= index)
            {
                return false
            }
        }
        
        return true
    }
}

// for internal and implementation use -- gets invalidated when new sites are merged into the site map
public struct LocalWeft: WeftType
{
    public var mapping: [SiteId:YarnIndex] = [:]
    
    public init() {}
}
