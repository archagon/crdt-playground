//
//  ORDTConstants.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2018-4-17.
//  Copyright © 2018 Alexei Baboulevitch. All rights reserved.
//

import Foundation

/// A local ID, mapped to a UUID using a `SiteMap`.
public typealias LUID = UInt16

/// An instance of a local ORDT. Task-specific; should remain fixed between invocations of the program.
public typealias InstanceID = UInt8

/// A "full" LUID.
public typealias InstancedLUID = InstancedID<LUID>

/// A logical clock value, usually a Lamport timestamp or a HLC. 5 bytes. Should be able to contain Unix time for the forseeable future.
public typealias ORDTClock = UInt64

/// A monotonic, site-specific operation counter.
public typealias ORDTSiteIndex = UInt32

public let NullSiteID: LUID = 0
public let NullInstancedLUID = InstancedLUID.init(uncheckedId: NullSiteID, instanceID: 0)
public let NullOperationID: OperationID = OperationID.init(logicalTimestamp: NullORDTClock, index: 0, siteID: NullSiteID, instanceID: 0)
public let NullORDTClock: ORDTClock = 0

public typealias ORDTLocalIndexWeft = ORDTWeft<InstancedLUID, ORDTSiteIndex>
public typealias ORDTLocalTimestampWeft = ORDTWeft<InstancedLUID, ORDTClock>
