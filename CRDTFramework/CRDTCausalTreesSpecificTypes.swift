//
//  CRDTCausalTreesSpecificTypes.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-11-1.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

public protocol CausalTreePriority { var priority: UInt8 { get } }

public typealias CausalTreeSiteUUIDT = CRDTSiteUUIDT
public protocol CausalTreeValueT: CRDTValueT, CRDTValueAtomPrintable, CRDTValueRelationQueries, CausalTreePriority {}
