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
extension SiteIndex.Key: BinaryCodable {}
extension Weave: BinaryCodable {}
extension Atom: BinaryCodable {}
extension AtomId: BinaryCodable {}
extension StringCharacterAtom: BinaryCodable {}
extension Pair: BinaryCodable {}
