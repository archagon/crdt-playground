//
//  TestingRecorder.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-14.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

/* Just a quick & dirty singleton action log. Actions should be recorded when a CRDT is mutated in
 any significant way, so that when a gnarly bug is found and fixed, the exact sequence of actions
 could be played back and then (manually) turned into a unit test case. Designing test cases from
 scratch is no fun. */

import AppKit

typealias TestingRecorderActionId = Int

private protocol TestingRecorderActionProtocol: CustomDebugStringConvertible
{
    var id: TestingRecorderActionId { get }
}

private struct TestingRecorderAction<T1, T2, T3, T4>: TestingRecorderActionProtocol where
    T1: CustomStringConvertible,
    T2: CustomStringConvertible,
    T3: CustomStringConvertible,
    T4: CustomStringConvertible
{
    let id: TestingRecorderActionId
    let v1: T1
    let v2: T2?
    let v3: T3?
    let v4: T4?
    
    init(id: TestingRecorderActionId, _ v1: T1) {
        self.id = id
        self.v1 = v1
        self.v2 = nil
        self.v3 = nil
        self.v4 = nil
    }
    
    init(id: TestingRecorderActionId, _ v1: T1, _ v2: T2)
    {
        self.id = id
        self.v1 = v1
        self.v2 = v2
        self.v3 = nil
        self.v4 = nil
    }
    
    init(id: TestingRecorderActionId, _ v1: T1, _ v2: T2, _ v3: T3)
    {
        self.id = id
        self.v1 = v1
        self.v2 = v2
        self.v3 = v3
        self.v4 = nil
    }
    
    init(id: TestingRecorderActionId, _ v1: T1, _ v2: T2, _ v3: T3, _ v4: T4)
    {
        self.id = id
        self.v1 = v1
        self.v2 = v2
        self.v3 = v3
        self.v4 = v4
    }
    
    var debugDescription: String
    {
        return "\(v1) \(v2 != nil ? v2!.description : "") \(v3 != nil ? v3!.description : "") \(v4 != nil ? v4!.description : "")"
    }
}

class TestingRecorder: CustomDebugStringConvertible
{
    // this (hopefully) ensures that parameters to recordAction won't even be copied in release mode
    static var shared: TestingRecorder? = {
        #if DEBUG
            return TestingRecorder()
        #else
            return nil
        #endif
    }()
    
    private var names = [TestingRecorderActionId:String]()
    private var log = [TestingRecorderActionProtocol]()
    
    func createAction(withName name: String, id: TestingRecorderActionId)
    {
        assert(names[id] == nil, "action already exists")
        names[id] = name
    }
    
    func recordAction<T1>(_ v1: T1, withId id: TestingRecorderActionId) where
        T1:CustomStringConvertible
    {
        assert(names[id] != nil, "action does not exist")
        let a = TestingRecorderAction<T1,Int8,Int8,Int8>(id: id, v1)
        processAction(a)
    }
    
    func recordAction<T1,T2>(_ v1: T1, _ v2: T2, withId id: TestingRecorderActionId) where
        T1:CustomStringConvertible, T2:CustomStringConvertible
    {
        assert(names[id] != nil, "action does not exist")
        let a = TestingRecorderAction<T1,T2,Int8,Int8>(id: id, v1,v2)
        processAction(a)
    }
    
    func recordAction<T1,T2,T3>(_ v1: T1, _ v2: T2, _ v3: T3, withId id: TestingRecorderActionId) where
        T1:CustomStringConvertible, T2:CustomStringConvertible, T3:CustomStringConvertible
    {
        assert(names[id] != nil, "action does not exist")
        let a = TestingRecorderAction<T1,T2,T3,Int8>(id: id, v1,v2,v3)
        processAction(a)
    }
    
    func recordAction<T1,T2,T3,T4>(_ v1: T1, _ v2: T2, _ v3: T3, _ v4: T4, withId id: TestingRecorderActionId) where
        T1:CustomStringConvertible, T2:CustomStringConvertible, T3:CustomStringConvertible, T4:CustomStringConvertible
    {
        assert(names[id] != nil, "action does not exist")
        let a = TestingRecorderAction<T1,T2,T3,T4>(id: id, v1,v2,v3,v4)
        processAction(a)
    }
    
    private func processAction(_ a: TestingRecorderActionProtocol)
    {
        log.append(a)
        
        #if DEBUG
            let name = names[a.id]!
            print("ACTION: \(name): \(a)")
        #endif
    }
    
    func reset()
    {
        names.removeAll()
        log.removeAll()
    }
    
    private init()
    {
    }
    
    var debugDescription: String
    {
        print("--- RECORDER LOG START ---")
        for (i,item) in log.enumerated()
        {
            let name = names[item.id]!
            print("\(i). \(name): \(item)")
        }
        print("---- RECORDER LOG END ----")
        return ""
    }
}

func debugPrintLog()
{
    print(TestingRecorder.shared ?? "No log in release mode!")
}
