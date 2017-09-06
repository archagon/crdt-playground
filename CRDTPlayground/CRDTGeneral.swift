//
//  CRDTGeneral.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-6.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

protocol CvRDT
{
    // must obey CRDT convergence properties
    mutating func integrate(_ v: inout Self)
}
