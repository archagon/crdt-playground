//
//  ORDTConstants.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2018-4-17.
//  Copyright © 2018 Alexei Baboulevitch. All rights reserved.
//

import Foundation

public typealias LUID = UInt16
public typealias InstanceID = UInt8
public typealias ORDTClock = UInt64
public typealias ORDTSiteIndex = UInt32

public let NullSiteID: LUID = 0
public let NullOperationID: OperationID = OperationID.init(logicalTimestamp: NullORDTClock, index: 0, siteID: NullSiteID, instanceID: nil)
public let NullORDTClock: ORDTClock = 0

public typealias ORDTLocalIndexWeft = ORDTWeft<LUID,ORDTSiteIndex>
public typealias ORDTLocalTimestampWeft = ORDTWeft<LUID,ORDTClock>

// TODO: remove these
extension LUID: DefaultInitializable { public init() { self = 0 } }
extension LUID: Zeroable { public static var zero: LUID { return 0 } }
extension ORDTClock: DefaultInitializable { public init() { self = 0 } }
extension ORDTClock: Zeroable { public static var zero: ORDTClock { return 0 } }
extension ORDTSiteIndex: DefaultInitializable { public init() { self = 0 } }
extension ORDTSiteIndex: Zeroable { public static var zero: ORDTSiteIndex { return 0 } }
