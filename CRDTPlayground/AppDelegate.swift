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
// NEXT: crash -- under what circumstances would 'yarns' have more atoms than 'atoms', but weave would be updated?

import Cocoa

typealias CausalTreeT = CausalTree<UUID,UTF8Char>
typealias CausalTreeBezier = CausalTree<UUID,BezierCommand>

enum BezierCommand: Int8
{
    init() {
        self = .null
    }
    
    var description: String
    {
        return "c\(self.rawValue)"
    }
    
    case null
    case addPoint
    case movePoint
    case deletePoint
    case stroke
    case fill
    case setStrokeColor
    case setFillColor
}

extension UTF8Char: CausalTreeValueT {}
extension UTF8Char: CausalTreeAtomPrintable
{
    var atomDescription: String
    {
        get
        {
            return String(self)
        }
    }
}
extension BezierCommand: CausalTreeValueT {}
extension BezierCommand: CausalTreeAtomPrintable
{
    var atomDescription: String
    {
        get
        {
            return description
        }
    }
}

// test recorder commands
// NEXT: parameters for these cases!
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

@NSApplicationMain class AppDelegate: NSObject, NSApplicationDelegate
{
    // testing objects
    var swarm: Driver!
    
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
            swarm = PeerToPeerDriver()
            swarm.addSite()
        }
    }
}

