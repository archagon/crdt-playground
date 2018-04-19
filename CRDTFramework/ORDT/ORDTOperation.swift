//
//  ORDTOperation.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2018-4-17.
//  Copyright © 2018 Alexei Baboulevitch. All rights reserved.
//

import Foundation

//////////////////////
// MARK: - Protocols -
//////////////////////

public protocol OperationIDType: Comparable, Hashable
{
}

public protocol OperationType
{
    associatedtype IDT
    associatedtype ValueT
    
    var id: IDT { get }
    var value: ValueT { get }
    
    init(id: IDT, value: ValueT)
}

public protocol CausalOperationType: OperationType
{
    var cause: IDT { get }
    
    init(id: IDT, cause: IDT, value: ValueT)
}

////////////////////////
// MARK: - Standard ID -
////////////////////////

public struct OperationID
{
    /// 5 bytes for the clock, 2 bytes for the site ID, 1 byte for the instance ID.
    private var data: UInt64
    
    public let index: ORDTSiteIndex
    
    // TODO: handle endianness, etc.
    public init(logicalTimestamp: ORDTClock, index: ORDTSiteIndex, siteID: LUID, instanceID: InstanceID? = nil)
    {
        precondition(logicalTimestamp <= ORDTClock(pow(2.0, 8 * 5)) - 1, "the logical timestamp needs to fit into 5 bytes")
        
        var data: UInt64 = 0
        
        data |= UInt64(logicalTimestamp) & 0xffffffffff
        data <<= (2 * 8)
        data |= UInt64(siteID) & 0xffff
        data <<= (1 * 8)
        data |= UInt64(instanceID ?? 0) & 0xff
        
        self.data = data
        
        self.index = index
    }
    
    /// The logical clock value, preferably a HLC or Lamport timestamp. Treated as a UInt40, which should be more than
    /// enough for practical use.
    public var logicalTimestamp: ORDTClock
    {
        return ORDTClock((self.data >> (3 * 8)) & 0xffffffffff)
    }
    
    /// The local site ID. Mappable to a UUID with the help of a Site Map.
    public var siteID: LUID
    {
        return LUID((self.data >> (1 * 8)) & 0xffff)
    }
    
    /// An additional byte of ordering data. This is useful if, for instance, you make several copies of the ORDT
    /// for use with multiple threads. Instead of wastefully giving each copy its own UUID, this is a far more
    /// space-efficient solution.
    public var instanceID: InstanceID
    {
        return InstanceID((self.data >> (0 * 8)) & 0xff)
    }
    
    public var instancedSiteID: InstancedLUID
    {
        return InstancedLUID.init(id: self.siteID, instanceID: self.instanceID)
    }
}
extension OperationID: OperationIDType
{
    public static func ==(lhs: OperationID, rhs: OperationID) -> Bool
    {
        return lhs.data == rhs.data && lhs.index == rhs.index
    }
    
    public static func <(lhs: OperationID, rhs: OperationID) -> Bool
    {
        return lhs.data < rhs.data
    }
    
    public var hashValue: Int
    {
        return self.data.hashValue ^ self.index.hashValue
    }
}
extension OperationID: CustomStringConvertible, CustomDebugStringConvertible
{
    public var description: String
    {
        get
        {
            return "[\(self.logicalTimestamp):\(self.siteID)\(self.instanceID == 0 ? "" : ".\(self.instanceID)")]"
        }
    }
    
    public var debugDescription: String
    {
        get
        {
            return "[\(self.logicalTimestamp):\(self.siteID)(\(self.index))\(self.instanceID == 0 ? "" : ".\(self.instanceID)")]"
        }
    }
}

///////////////////////////////
// MARK: - Standard Operation -
///////////////////////////////

public struct Operation <ValueT: IndexRemappable> : OperationType, IndexRemappable
{
    public private(set) var id: OperationID
    public private(set) var value: ValueT
    
    public init(id: OperationID, value: ValueT)
    {
        self.id = id
        self.value = value
    }
    
    public mutating func remapIndices(_ map: [SiteId:SiteId])
    {
        if let newOwner = map[SiteId(self.id.siteID)]
        {
            self.id = OperationID.init(logicalTimestamp: self.id.logicalTimestamp, index: self.id.index, siteID: LUID(newOwner), instanceID: self.id.instanceID)
        }
        
        value.remapIndices(map)
    }
}
extension Operation: CustomStringConvertible, CustomDebugStringConvertible
{
    public var description: String
    {
        get
        {
            return "\(id)"
        }
    }
    
    public var debugDescription: String
    {
        get
        {
            return "\(id.debugDescription): \(value)"
        }
    }
}
