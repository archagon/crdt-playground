//
//  ORDTConstants.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2018-4-17.
//  Copyright © 2018 Alexei Baboulevitch. All rights reserved.
//

import Foundation

public typealias LUID = SiteId

//public let NullClock: Clock = 0
public let NullSiteID: SiteId = 0
public let NullOperationID: OperationID = OperationID.init(logicalTimestamp: NullClock, siteID: NullSiteID, instanceID: nil)

public typealias ORDTLocalWeft = ORDTWeft<LUID>
