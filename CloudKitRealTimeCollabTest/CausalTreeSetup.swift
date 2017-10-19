//
//  CausalTreeSetup.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-19.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation
//import CRDTFramework_iOS

typealias CausalTreeString = CausalTree<UUID, UTF8Char>

extension UTF8Char: CausalTreeValueT {}
extension UTF8Char: CausalTreeAtomPrintable
{
    public var atomDescription: String
    {
        get
        {
            // TODO: print character
            return String(self)
        }
    }
}

//extension UUID: BinaryCodable {}
//extension NSPoint: BinaryCodable {}
//extension CGFloat: BinaryCodable {}
//extension CRDTCounter: BinaryCodable {}
//extension CausalTree: BinaryCodable {}
//extension SiteIndex: BinaryCodable {}
//extension SiteIndex.SiteIndexKey: BinaryCodable {}
//extension Weave: BinaryCodable {}
//extension Weave.Atom: BinaryCodable {}
//extension AtomId: BinaryCodable {}
//extension AtomType: BinaryCodable {}

