//
//  CausalTreeSetup.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-19.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation
import CoreGraphics
//import CRDTFramework_iOS

typealias CausalTreeString = CausalTree<UUID, UInt16>

extension UInt16: CausalTreeValueT {}
extension UInt16: CausalTreeAtomPrintable
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

extension UUID: BinaryCodable {}
extension CGPoint: BinaryCodable {}
extension CGFloat: BinaryCodable {}
extension CRDTTextEditing: BinaryCodable {}
extension CRDTCounter: BinaryCodable {}
extension CRDTMap: BinaryCodable {}
extension CRDTMap.ClockValuePair: BinaryCodable {}
extension CRDTMap.IDPair: BinaryCodable {}
extension CausalTree: BinaryCodable {}
extension SiteIndex: BinaryCodable {}
extension SiteIndex.SiteIndexKey: BinaryCodable {}
extension Weave: BinaryCodable {}
extension Weave.Atom: BinaryCodable {}
extension AtomId: BinaryCodable {}
extension AtomType: BinaryCodable {}
extension StringCharacterAtom: BinaryCodable {}
extension StringCharacterValueType: BinaryCodable {}
