//
//  CausalTreeInterfaceDrawExtensions.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-19.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import AppKit
import CRDTFramework_OSX

extension CausalTreeInterfaceProtocol where SiteUUIDT == CausalTreeBezierT.SiteUUIDT, ValueT == CausalTreeBezierT.ValueT
{
    func createContentView() -> NSView & CausalTreeContentView
    {
        let view = CausalTreeDrawEditingView(frame: NSMakeRect(0, 0, 100, 100), crdt: self.crdt)
        
        view.listener = self
        return view
    }
    
    func appendAtom(toAtom: AtomId?, forControlViewController vc: CausalTreeControlViewController)
    {
        // doesn't really make sense
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
    lazy var contentView: NSView & CausalTreeContentView = createContentView()
    
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
    
    // stupid boilerplate b/c can't include @objc in protocol extensions
    @objc func causalTreeDidUpdate(sender: NSObject?)
    {
        // change from content view, so update interface
        delegate.reloadData(self.id)
    }
}
