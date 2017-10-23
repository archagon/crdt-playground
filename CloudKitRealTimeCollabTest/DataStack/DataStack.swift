//
//  DataStack.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-21.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation
import UIKit

// deals with files on a universal level, no matter where they're stored
// TODO: add async where necessary
class DataStack
{
    public static let sharedInstance = DataStack()
    
    public var memory: Memory = Memory()
    public var memoryNetworkLayer: MemoryNetworkLayer = MemoryNetworkLayer()
    public var network: Network = Network()
    
    public var id: UUID = UIDevice.current.identifierForVendor!
    
    private init()
    {
    }
}
