//
//  CausalTreeControlViewController.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-8.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

/* Control window that lets us query and manipulate our causal tree directly, go online and connect
 to different peers, view a visualization of the tree, and manipulate the model view (currently text). */

import Foundation
import AppKit
import CoreGraphics
import CRDTFramework

protocol CausalTreeControlViewControllerDelegate: class
{
    func isOnline(forControlViewController: CausalTreeControlViewController) -> Bool
    func isConnected(toSite: SiteId, forControlViewController: CausalTreeControlViewController) -> Bool
    func goOnline(_ online: Bool, forControlViewController: CausalTreeControlViewController)
    func allOnline(_ online: Bool, forControlViewController: CausalTreeControlViewController)
    func connect(_ connect: Bool, toSite: SiteId, forControlViewController: CausalTreeControlViewController)
    func allSites(forControlViewController: CausalTreeControlViewController) -> [SiteId]
    func showWeave(forControlViewController: CausalTreeControlViewController)
    func showAwareness(forAtom: AtomId?, inControlViewController: CausalTreeControlViewController)
    func printWeave(forControlViewController: CausalTreeControlViewController) -> String
    func generateWeave(forControlViewController: CausalTreeControlViewController) -> String
    func atomDescription(_ a: AtomId, forControlViewController: CausalTreeControlViewController) -> String
    func generateCausalBlock(forAtom atom: AtomId, inControlViewController vc: CausalTreeControlViewController) -> CountableClosedRange<WeaveIndex>?
    func appendAtom(toAtom: AtomId?, forControlViewController: CausalTreeControlViewController)
    func deleteAtom(_ atom: AtomId, forControlViewController: CausalTreeControlViewController)
    func addSite(forControlViewController: CausalTreeControlViewController)
    func siteUUID(forControlViewController: CausalTreeControlViewController) -> UUID
    func siteId(forControlViewController: CausalTreeControlViewController) -> SiteId
    func selectedAtom(forControlViewController: CausalTreeControlViewController) -> AtomId?
    func atomIdForWeaveIndex(_ weaveIndex: WeaveIndex, forControlViewController: CausalTreeControlViewController) -> AtomId?
    func atomWeft(_ atom: AtomId, forControlViewController: CausalTreeControlViewController) -> Weft
    func dataView(forControlViewController: CausalTreeControlViewController) -> NSView
    func crdtSize(forControlViewController: CausalTreeControlViewController) -> Int //in bytes
    func atomCount(forControlViewController: CausalTreeControlViewController) -> Int
    func revisions(forControlViewController: CausalTreeControlViewController) -> [Weft]
    func selectedRevision(forControlViewController: CausalTreeControlViewController) -> Int?
    func setRevision(_ r: Int?, forControlViewController: CausalTreeControlViewController)
    func getData(forControlViewController: CausalTreeControlViewController) -> Data
}

class CausalTreeControlViewController: NSViewController
{
    @IBOutlet var siteUUIDLabel: NSTextField!
    @IBOutlet var siteIdLabel: NSTextField!
    @IBOutlet var selectedAtomLabel: NSTextField!
    @IBOutlet var selectedAtomWeftLabel: NSTextField!
    @IBOutlet var lastOperationDurationLabel: NSTextField!
    @IBOutlet var totalAtomsLabel: NSTextField!
    @IBOutlet var sizeLabel: NSTextField!
    @IBOutlet var showWeaveButton: NSButton!
    @IBOutlet var addSiteButton: NSButton!
    @IBOutlet var printWeaveButton: NSButton!
    @IBOutlet var generateWeaveButton: NSButton!
    @IBOutlet var onlineButton: NSButton!
    @IBOutlet var allOnlineButton: NSButton!
    @IBOutlet var allOfflineButton: NSButton!
    @IBOutlet var allSitesButton: NSButton!
    @IBOutlet var noSitesButton: NSButton!
    @IBOutlet var generateAwarenessButton: NSButton!
    @IBOutlet var appendAtomButton: NSButton!
    @IBOutlet var deleteAtomButton: NSButton!
    @IBOutlet var generateCausalBlockButton: NSButton!
    @IBOutlet var connectionStack: NSStackView!
    @IBOutlet var dataView: NSView!
    @IBOutlet var revisionsPulldown: NSPopUpButton!
    @IBOutlet var revisionsClearButton: NSButton!
    @IBOutlet var saveButton: NSButton!
    
    weak var delegate: CausalTreeControlViewControllerDelegate?
    {
        didSet
        {
            for c in dataView.subviews { c.removeFromSuperview() }
            
            if let view = delegate?.dataView(forControlViewController: self)
            {
                dataView.addSubview(view)
                view.autoresizingMask = [.width, .height]
                view.frame = dataView.bounds
            }
            
            reloadData()
        }
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        showWeaveButton.target = self
        showWeaveButton.action = #selector(showWeave)
        addSiteButton.target = self
        addSiteButton.action = #selector(addSite)
        //printWeaveButton.target = self
        //printWeaveButton.action = #selector(printWeave)
        onlineButton.target = self
        onlineButton.action = #selector(toggleOnline)
        allOnlineButton.target = self
        allOnlineButton.action = #selector(allOnline)
        allOfflineButton.target = self
        allOfflineButton.action = #selector(allOffline)
        allSitesButton.target = self
        allSitesButton.action = #selector(allSites)
        noSitesButton.target = self
        noSitesButton.action = #selector(noSites)
        generateWeaveButton.target = self
        generateWeaveButton.action = #selector(generateWeave)
        generateAwarenessButton.target = self
        generateAwarenessButton.action = #selector(generateAwareness)
        //appendAtomButton.target = self
        //appendAtomButton.action = #selector(appendAtom)
        generateCausalBlockButton.target = self
        generateCausalBlockButton.action = #selector(generateCausalBlock)
        //deleteAtomButton.target = self
        //deleteAtomButton.action = #selector(deleteAtom)
        revisionsPulldown.target = self
        revisionsPulldown.action = #selector(selectRevision)
        revisionsClearButton.target = self
        revisionsClearButton.action = #selector(revisionsClear)
        saveButton.target = self
        saveButton.action = #selector(save)
        
        reloadData()
    }
    
    @objc func selectRevision(sender: NSPopUpButton)
    {
        self.delegate?.setRevision(sender.selectedTag() == sender.numberOfItems - 1 ? nil : sender.selectedTag(), forControlViewController: self)
        
        reloadData()
    }
    
    @objc func revisionsClear(sender: NSButton)
    {
        self.delegate?.setRevision(nil, forControlViewController: self)
        
        reloadData()
    }
    
    @objc func showWeave(sender: NSButton)
    {
        self.delegate?.showWeave(forControlViewController: self)
    }
    
    @objc func addSite(sender: NSButton)
    {
        self.delegate?.addSite(forControlViewController: self)
        
        reloadData()
    }
    
    @objc func printWeave(sender: NSButton)
    {
        guard let delegate = self.delegate else { return }
        let start = CACurrentMediaTime()
        let str = delegate.printWeave(forControlViewController: self)
        let end = CACurrentMediaTime()
        updateLastOperationDuration(type: "Print", ms: end - start)
        print("String: \"\(str)\"")
    }
    
    @objc func generateWeave(sender: NSButton)
    {
        guard let delegate = self.delegate else { return }
        let start = CACurrentMediaTime()
        let weave = delegate.generateWeave(forControlViewController: self)
        let end = CACurrentMediaTime()
        updateLastOperationDuration(type: "Generate Weave", ms: end - start)
        print("Weave: \(weave)")
    }
    
    @objc func toggleOnline(sender: NSButton)
    {
        guard let delegate = self.delegate else { return }
        
        let connected = delegate.isOnline(forControlViewController: self)
        delegate.goOnline(!connected, forControlViewController: self)
        
        reloadData()
    }
    
    @objc func allOnline(sender: NSButton)
    {
        guard let delegate = self.delegate else { return }
        
        delegate.allOnline(true, forControlViewController: self)
        
        //reload handled driver-side
    }
    
    @objc func allOffline(sender: NSButton)
    {
        guard let delegate = self.delegate else { return }
        
        delegate.allOnline(false, forControlViewController: self)
        
        //reload handled driver-side
    }
    
    @objc func toggleConnection(sender: NSButton)
    {
        guard let delegate = self.delegate else { return }
        
        let site = SiteId(sender.tag)
        let connected = delegate.isConnected(toSite: site, forControlViewController: self)
        delegate.connect(!connected, toSite: site, forControlViewController: self)
        
        reloadData()
    }
    
    @objc func generateAwareness(sender: NSButton)
    {
        guard let delegate = self.delegate else { return }
        if let atom = delegate.selectedAtom(forControlViewController: self)
        {
            delegate.showAwareness(forAtom: atom, inControlViewController: self)
        }
    }
    
    @objc func appendAtom(sender: NSButton)
    {
        guard let delegate = self.delegate else { return }
        if let atom = delegate.selectedAtom(forControlViewController: self)
        {
            let start = CACurrentMediaTime()
            delegate.appendAtom(toAtom: atom, forControlViewController: self)
            let end = CACurrentMediaTime()
            updateLastOperationDuration(type: "Append", ms: (end - start))
        }
        else
        {
            let start = CACurrentMediaTime()
            delegate.appendAtom(toAtom: nil, forControlViewController: self)
            let end = CACurrentMediaTime()
            updateLastOperationDuration(type: "Append", ms: (end - start))
        }
    }
    
    @objc func deleteAtom(sender: NSButton)
    {
        guard let delegate = self.delegate else { return }
        if let atom = delegate.selectedAtom(forControlViewController: self)
        {
            let start = CACurrentMediaTime()
            delegate.deleteAtom(atom, forControlViewController: self)
            let end = CACurrentMediaTime()
            updateLastOperationDuration(type: "Delete", ms: (end - start))
        }
    }
    
    @objc func generateCausalBlock(sender: NSButton)
    {
        guard let delegate = self.delegate else { return }
        if let atom = delegate.selectedAtom(forControlViewController: self)
        {
            let start = CACurrentMediaTime()
            guard let causalBlock = delegate.generateCausalBlock(forAtom: atom, inControlViewController: self) else
            {
                return //probably unparented atom
            }
            let end = CACurrentMediaTime()
            updateLastOperationDuration(type: "Causal Block", ms: (end - start))
            
            var printVal = ""
            for i in 0..<causalBlock.count
            {
                let index = causalBlock.lowerBound + WeaveIndex(i)
                let a = delegate.atomIdForWeaveIndex(index, forControlViewController: self)!
                if i != 0
                {
                    printVal += ","
                }
                printVal += "\(a.site):\(a.index)"
            }
            print("Causal Block: \(printVal)")
        }
    }
    
    @objc func allSites(sender: NSButton)
    {
        guard let delegate = self.delegate else { return }
        
        for b in self.connectionStack.subviews
        {
            if b.tag != delegate.siteId(forControlViewController: self) && !delegate.isConnected(toSite: SiteId(b.tag), forControlViewController: self)
            {
                guard let button = b as? NSButton else
                {
                    assert(false)
                    return
                }
                let _ = button.target?.perform(button.action, with: button)
            }
        }
    }
    
    @objc func noSites(sender: NSButton)
    {
        guard let delegate = self.delegate else { return }
        
        for b in self.connectionStack.subviews
        {
            if b.tag != delegate.siteId(forControlViewController: self) && delegate.isConnected(toSite: SiteId(b.tag), forControlViewController: self)
            {
                guard let button = b as? NSButton else
                {
                    assert(false)
                    return
                }
                let _ = button.target?.perform(button.action, with: button)
            }
        }
    }
    
    @objc func save(sender: NSButton)
    {
        guard let delegate = self.delegate else { return }
    
        let data = delegate.getData(forControlViewController: self)
        
        let name = "CausalTreeTestFile.crdt"
        
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = name
        savePanel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        savePanel.begin { r in
            if r == NSApplication.ModalResponse.OK, let url = savePanel.url
            {
                print("Saving file to: \(url)")
                try! data.write(to: url)
            }
        }
    }
    
    func reloadData()
    {
        guard let delegate = self.delegate else { return }
        
        updateButtons: do
        {
            let hasSelectedAtom = delegate.selectedAtom(forControlViewController: self) != nil
            self.generateAwarenessButton.isEnabled = hasSelectedAtom
            self.generateCausalBlockButton.isEnabled = hasSelectedAtom
            //self.deleteAtomButton.isEnabled = hasSelectedAtom
        }
        
        updateMenu: do
        {
            self.revisionsPulldown.removeAllItems()
            
            let revisions = delegate.revisions(forControlViewController: self)
            let selectedItem = delegate.selectedRevision(forControlViewController: self)
            
            for (i,r) in revisions.enumerated()
            {
                if i == 0
                {
                    self.revisionsPulldown.insertItem(withTitle: "\(r.description) (starting)", at: 0)
                }
                else if i == revisions.count - 1
                {
                    self.revisionsPulldown.insertItem(withTitle: "\(r.description) (current)", at: 0)
                }
                else
                {
                    self.revisionsPulldown.insertItem(withTitle: r.description, at: 0)
                }
                
                self.revisionsPulldown.item(at: 0)?.tag = i
            }
            
            self.revisionsPulldown.isEnabled = (revisions.count > 1)
            
            if let i = selectedItem, i != revisions.count - 1
            {
                self.revisionsPulldown.selectItem(withTag: i)
                self.revisionsClearButton.alphaValue = 1
                self.revisionsClearButton.isEnabled = true
            }
            else
            {
                self.revisionsPulldown.selectItem(withTag: revisions.count - 1)
                self.revisionsClearButton.alphaValue = 0
                self.revisionsClearButton.isEnabled = false
            }
        }
        
        updateText: do
        {
            self.siteUUIDLabel.stringValue = "Site: \(delegate.siteUUID(forControlViewController: self))"
            self.siteIdLabel.stringValue = "Site ID: \(delegate.siteId(forControlViewController: self))"
            
            self.totalAtomsLabel.stringValue = "Total Atoms: \(delegate.atomCount(forControlViewController: self))"
            self.sizeLabel.stringValue = "CRDT Size: \(delegate.crdtSize(forControlViewController: self)/1024) kb"
            
            if let atom = delegate.selectedAtom(forControlViewController: self)
            {
                self.selectedAtomLabel.stringValue = "Selected Atom: \(delegate.atomDescription(atom, forControlViewController: self))"
                self.selectedAtomWeftLabel.stringValue = "Selected Atom Weft: \(delegate.atomWeft(atom, forControlViewController: self))"
            }
            else
            {
                self.selectedAtomLabel.stringValue = "Selected Atom: (none)"
                self.selectedAtomWeftLabel.stringValue = "Selected Atom Weft: (none)"
            }
        }
        
        updateSiteConnections: do
        {
            let type = NSButton.ButtonType.toggle
            let bezel = NSButton.BezelStyle.recessed
            
            onlineButton.state = (delegate.isOnline(forControlViewController: self) ? .on : .off)
            onlineButton.bezelStyle = bezel
            onlineButton.setButtonType(type)
            
            var subviewPool = connectionStack.subviews
            //subviewPool.forEach { connectionStack.removeArrangedSubview($0) }
            let sites = delegate.allSites(forControlViewController: self)
            
            for site in sites
            {
                let button = (subviewPool.popLast() ?? NSButton(title: "", target: self, action: #selector(toggleConnection))) as! NSButton
                button.bezelStyle = bezel
                button.setButtonType(type)
                button.showsBorderOnlyWhileMouseInside = onlineButton.showsBorderOnlyWhileMouseInside
                button.font = onlineButton.font
                button.title = "\(site)"
                button.tag = Int(site)
                if site == delegate.siteId(forControlViewController: self)
                {
                    button.isEnabled = false
                    button.state = .on
                }
                else
                {
                    let connected = delegate.isConnected(toSite: site, forControlViewController: self)
                    button.isEnabled = true
                    button.state = (connected ? .on : .off)
                }
                button.isEnabled = (delegate.isOnline(forControlViewController: self) ? button.isEnabled : false)
                connectionStack.addArrangedSubview(button)
            }
        }
    }
    
    func updateLastOperationDuration(type: String, ms: CFTimeInterval)
    {
        self.lastOperationDurationLabel.stringValue = "Last \(type) Duration: \(String(format: "%.2f", ms * 1000)) ms"
    }
}
