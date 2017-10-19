//
//  AppDelegate.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-8-28.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

// NEXT: no need to save commit if a) you're already aware of the site so far, b) you're connecting to the last item
// NEXT: completeWeft() vs. siteLocalWeft()? (i.e. what does my site know so that I can strategically place my commits?)
// NEXT: overlapping site id bug in hard concurrency demo weave?
// NEXT: is associatedtype enum w/new data types still decodable in part by older client?

import Cocoa
//import CRDTFramework_OSX

@NSApplicationMain class AppDelegate: NSObject, NSApplicationDelegate
{
    // AB: test trees, simply uncomment one or the other to try different data types!
    //var swarm: Driver<CausalTreeTextT.SiteUUIDT, CausalTreeTextT.ValueT, CausalTreeTextInterface>!
    var swarm: Driver<CausalTreeBezierT.SiteUUIDT, CausalTreeBezierT.ValueT, CausalTreeDrawInterface>!
    
    let syncTime: TimeInterval = 2
    
    func applicationDidFinishLaunching(_ aNotification: Notification)
    {
        setupTestRecorder: do
        {
            for e in TestCommand.allCases
            {
                TestingRecorder.shared?.createAction(withName: "\(e)", id: e.rawValue)
            }
        }
        
        setupSwarm: do
        {
            swarm = PeerToPeerDriver(syncTime)
            let _ = swarm.appendPeer(fromPeer: nil)
        }
    }
}

// test recorder commands
// NEXT:  parameters for these cases!
// TODO: move these elsewhere
enum TestCommand: TestingRecorderActionId, CustomStringConvertible
{
    case createSite //ownerUUID
    case forkSite //ownerUUID, fromUUID, completeWeft
    case mergeSite //ownerUUID, remoteUUID, ownerWeft, remoteWeft
    case addAtom //ownerUUID, causeId, type
    case deleteAtom //ownerUUID, atomId
    
    var description: String
    {
        switch self
        {
        case .createSite:
            return "CreateSite"
        case .forkSite:
            return "ForkSite"
        case .mergeSite:
            return "MergeSite"
        case .addAtom:
            return "AddAtom"
        case .deleteAtom:
            return "DeleteAtom"
        }
    }
    
    static var allCases: [TestCommand]
    {
        return [.createSite, .forkSite, .mergeSite, .addAtom, .deleteAtom]
    }
}

let characters: [UTF8Char] = ["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z"].map
{
    $0.utf8.first!
}
