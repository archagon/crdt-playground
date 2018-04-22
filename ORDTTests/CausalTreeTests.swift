//
//  CausalTreeTests.swift
//  ORDTTests
//
//  Created by Alexei Baboulevitch on 2018-4-21.
//  Copyright © 2018 Alexei Baboulevitch. All rights reserved.
//

import Foundation

import XCTest
import CRDTFramework_OSX

class CausalTreeTests: ABTestCase
{
    enum StringValue: DefaultInitializable, CRDTValueRelationQueries, CausalTreePriority, CustomStringConvertible
    {
        case null
        case insert(char: UInt16)
        case delete
        
        public init()
        {
            self = .null
        }
        
        public init(insert c: UInt16)
        {
            self = .insert(char: c)
        }
        
        public init(withDelete: Bool)
        {
            self = .delete
        }
        
        public var description: String
        {
            switch self
            {
            case .null:
                return "ø"
            case .insert(let char):
                return "\(Character(UnicodeScalar(char) ?? UnicodeScalar(0)))"
            case .delete:
                return "X"
            }
        }
        
        public var childless: Bool
        {
            switch self
            {
            case .null:
                return false
            case .insert(_):
                return false
            case .delete:
                return true
            }
        }
        
        public var priority: UInt8
        {
            switch self
            {
            case .null:
                return 0
            case .insert(_):
                return 0
            case .delete:
                return 1
            }
        }
    }
    
    typealias TreeT = ORDTCausalTree<StringValue>
    
    var baseTree: TreeT!
    
    override func setUp()
    {
        super.setUp()
        
        self.baseTree = TreeT.init(owner: 1)
    }
    
    override func tearDown()
    {
        self.baseTree = nil
        
        super.tearDown()
    }
    
    func testBasics()
    {
        var tree: TreeT = baseTree
        let zeroAtom = tree.weave().first!
        
        let a1 = tree.addAtom(withValue: StringValue.init(insert: 97), causedBy: zeroAtom.id)!
        let a2 = tree.addAtom(withValue: StringValue.init(insert: 98), causedBy: a1.0)!
        let a3 = tree.addAtom(withValue: StringValue.init(insert: 99), causedBy: a2.0)!
        let a4 = tree.addAtom(withValue: StringValue.init(insert: 100), causedBy: a3.0)!
        
        //tree.owner = 2
        
        let b1 = tree.addAtom(withValue: StringValue.init(insert: 101), causedBy: a2.0)!
        let b2 = tree.addAtom(withValue: StringValue.init(insert: 102), causedBy: b1.0)!
        let b3 = tree.addAtom(withValue: StringValue.init(insert: 103), causedBy: b2.0)!
        let b4 = tree.addAtom(withValue: StringValue.init(withDelete: true), causedBy: b2.0)!
        
        do
        {
            let _ = try tree.validate()
        }
        catch
        {
            XCTAssert(false, "\(error)")
        }
        
        var values: [unichar] = []
        for op in tree.weave()
        {
            switch op.value
            {
            case .null:
                break
            case .insert(let c):
                values.append(c)
            case .delete:
                values.popLast()
            }
        }
        
        let string = NSString.init(characters: &values, length: values.count)
        
        XCTAssertEqual(string as String, "abegcd")
    }
}
