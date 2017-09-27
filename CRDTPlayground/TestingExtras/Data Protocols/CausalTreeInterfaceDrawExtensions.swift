//
//  CausalTreeInterfaceDrawExtensions.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-19.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import AppKit

extension CausalTreeInterfaceProtocol where SiteUUIDT == CausalTreeBezierT.SiteUUIDT, ValueT == CausalTreeBezierT.ValueT
{
    func createContentView() -> NSView & CausalTreeListener {
        return CausalTreeDrawEditingView(frame: NSMakeRect(0, 0, 100, 100), crdt: self.crdt)
    }
    
    func appendAtom(toAtom: AtomId?, forControlViewController vc: CausalTreeControlViewController)
    {
        if let atom = toAtom
        {
            TestingRecorder.shared?.recordAction(uuid, atom, AtomType.value, withId: TestCommand.addAtom.rawValue)
            
            //let id = crdt.weave.addAtom(withValue: characters[Int(arc4random_uniform(UInt32(characters.count)))], causedBy: atom, atTime: Clock(CACurrentMediaTime() * 1000))
            //delegate.didSelectAtom(id, self.id)
            delegate.reloadData(self.id)
            reloadData()
        }
        else
        {
            let index = crdt.weave.completeWeft().mapping[crdt.weave.owner] ?? -1
            let cause = (index == -1 ? AtomId(site: ControlSite, index: 0) : AtomId(site: crdt.weave.owner, index: index))
            
            TestingRecorder.shared?.recordAction(uuid, cause, AtomType.value, withId: TestCommand.addAtom.rawValue)
            
            //let id = crdt.weave.addAtom(withValue: characters[Int(arc4random_uniform(UInt32(characters.count)))], causedBy: cause, atTime: Clock(CACurrentMediaTime() * 1000))
            //delegate.didSelectAtom(id, self.id)
            delegate.reloadData(self.id)
            reloadData()
        }
    }
    
    func printWeave(forControlViewController vc: CausalTreeControlViewController) -> String
    {
        return ""
    }
}

class CausalTreeDrawInterface : NSObject, CausalTreeInterfaceProtocol
{
    typealias SiteUUIDT = CausalTreeBezierT.SiteUUIDT
    typealias ValueT = CausalTreeBezierT.ValueT
    
    var id: Int
    var uuid: SiteUUIDT
    let storyboard: NSStoryboard
    lazy var contentView: NSView & CausalTreeListener = createContentView()
    
    unowned var crdt: CausalTree<SiteUUIDT, ValueT>
    var crdtCopy: CausalTree<SiteUUIDT, ValueT>?
    unowned var delegate: CausalTreeInterfaceDelegate
    
    required init(id: Int, uuid: SiteUUIDT, storyboard: NSStoryboard, crdt: CausalTree<SiteUUIDT, ValueT>, delegate: CausalTreeInterfaceDelegate)
    {
        self.id = id
        self.uuid = uuid
        self.storyboard = storyboard
        self.crdt = crdt
        self.delegate = delegate
    }
}
