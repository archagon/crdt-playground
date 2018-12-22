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
//import CRDTFramework_OSX

protocol CausalTreeControlViewControllerDelegate: class
{
    // TODO: SiteId, LocalWeft, AtomId, etc. should perhaps use UUIDs, or somehow guarantee that the values won't be cached
    func isOnline(forControlViewController: CausalTreeControlViewController) -> Bool
    func isConnected(toSite: SiteId, forControlViewController: CausalTreeControlViewController) -> Bool
    func goOnline(_ online: Bool, forControlViewController: CausalTreeControlViewController)
    func allOnline(_ online: Bool, forControlViewController: CausalTreeControlViewController)
    func connect(_ connect: Bool, toSite: SiteId, forControlViewController: CausalTreeControlViewController)
    func allSites(forControlViewController: CausalTreeControlViewController) -> [SiteId]
    func showWeave(forControlViewController: CausalTreeControlViewController)
    func showAwareness(forAtom: AbsoluteAtomId<CausalTreeStandardUUIDT>?, inControlViewController: CausalTreeControlViewController)
    func printWeave(forControlViewController: CausalTreeControlViewController) -> String
    func generateWeave(forControlViewController: CausalTreeControlViewController) -> String
    func atomDescription(_ a: AbsoluteAtomId<CausalTreeStandardUUIDT>, forControlViewController: CausalTreeControlViewController) -> String
    func generateCausalBlock(forAtom atom: AbsoluteAtomId<CausalTreeStandardUUIDT>, inControlViewController vc: CausalTreeControlViewController) -> CountableClosedRange<WeaveIndex>?
    func addSite(forControlViewController: CausalTreeControlViewController)
    func siteUUID(forControlViewController: CausalTreeControlViewController) -> CausalTreeStandardUUIDT
    func siteId(forControlViewController: CausalTreeControlViewController) -> SiteId
    func selectedAtom(forControlViewController: CausalTreeControlViewController) -> AbsoluteAtomId<CausalTreeStandardUUIDT>?
    func atomIdForWeaveIndex(_ weaveIndex: WeaveIndex, forControlViewController: CausalTreeControlViewController) -> AtomId?
    func dataView(forControlViewController: CausalTreeControlViewController) -> NSView
    func crdtSize(forControlViewController: CausalTreeControlViewController) -> Int //in bytes
    func atomCount(forControlViewController: CausalTreeControlViewController) -> Int
    func localRevisions(forControlViewController: CausalTreeControlViewController) -> [LocalWeft] //for display purposes only
    func selectedRevision(forControlViewController: CausalTreeControlViewController) -> Int?
    func setRevision(_ r: Int?, forControlViewController: CausalTreeControlViewController)
    func getData(forControlViewController: CausalTreeControlViewController) -> Data
}

class CausalTreeControlViewController: NSViewController
{
    @IBOutlet weak var selectedAtomLabel: NSTextField!
    @IBOutlet weak var totalAtomsLabel: NSTextField!
    @IBOutlet weak var sizeLabel: NSTextField!
    @IBOutlet weak var showWeaveButton: NSButton!
    @IBOutlet weak var addSiteButton: NSButton!
    @IBOutlet weak var printWeaveButton: NSButton!
    @IBOutlet weak var generateWeaveButton: NSButton!
    @IBOutlet weak var onlineButton: NSButton!
    @IBOutlet weak var allOnlineButton: NSButton!
    @IBOutlet weak var allOfflineButton: NSButton!
    @IBOutlet weak var allSitesButton: NSButton!
    @IBOutlet weak var noSitesButton: NSButton!
    @IBOutlet weak var generateAwarenessButton: NSButton!
    @IBOutlet weak var appendAtomButton: NSButton!
    @IBOutlet weak var deleteAtomButton: NSButton!
    @IBOutlet weak var generateCausalBlockButton: NSButton!
    @IBOutlet weak var connectionStack: NSStackView!
    @IBOutlet weak var dataView: NSView!
    @IBOutlet weak var revisionsPulldown: NSPopUpButton!
    @IBOutlet weak var revisionsClearButton: NSButton!
    @IBOutlet weak var saveButton: NSButton!
    
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
        self.delegate?.setRevision(sender.selectedTag() >= sender.numberOfItems - 1 ? nil : sender.selectedTag(), forControlViewController: self)
        
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
        let _ = CACurrentMediaTime()
        let str = delegate.printWeave(forControlViewController: self)
        let _ = CACurrentMediaTime()
        print("String: \"\(str)\"")
    }
    
    @objc func generateWeave(sender: NSButton)
    {
        guard let delegate = self.delegate else { return }
        let _ = CACurrentMediaTime()
        let weave = delegate.generateWeave(forControlViewController: self)
        let _ = CACurrentMediaTime()
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
    
    @objc func generateCausalBlock(sender: NSButton)
    {
        guard let delegate = self.delegate else { return }
        if let atom = delegate.selectedAtom(forControlViewController: self)
        {
            let _ = CACurrentMediaTime()
            guard let causalBlock = delegate.generateCausalBlock(forAtom: atom, inControlViewController: self) else
            {
                return //probably unparented atom
            }
            let _ = CACurrentMediaTime()
            
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
            //self.generateAwarenessButton.isEnabled = hasSelectedAtom
            self.generateAwarenessButton.isEnabled = false //AB: might need this later, used as spacer for now
            self.generateAwarenessButton.alphaValue = 0
            self.generateCausalBlockButton.isEnabled = hasSelectedAtom
            //self.deleteAtomButton.isEnabled = hasSelectedAtom
            self.generateCausalBlockButton.isEnabled = false
            self.generateCausalBlockButton.alphaValue = 0
        }
        
        updateMenu: do
        {
            self.revisionsPulldown.removeAllItems()
            
            let revisions = delegate.localRevisions(forControlViewController: self)
            let selectedItem = delegate.selectedRevision(forControlViewController: self)
            
            for (i,r) in revisions.enumerated()
            {
                let description = r.description
                
                if i == 0
                {
                    self.revisionsPulldown.insertItem(withTitle: "\(description) (starting)", at: 0)
                }
                else if i == revisions.count - 1
                {
                    self.revisionsPulldown.insertItem(withTitle: "\(description) (current)", at: 0)
                }
                else
                {
                    self.revisionsPulldown.insertItem(withTitle: description, at: 0)
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
            self.totalAtomsLabel.stringValue = "Total Atoms: \(delegate.atomCount(forControlViewController: self))"
            self.sizeLabel.stringValue = "CRDT Size: \(delegate.crdtSize(forControlViewController: self)/1024) kb"
            
            if let atom = delegate.selectedAtom(forControlViewController: self)
            {
                self.selectedAtomLabel.stringValue = "Selected Atom: \(delegate.atomDescription(atom, forControlViewController: self))"
            }
            else
            {
                self.selectedAtomLabel.stringValue = "Selected Atom: (none)"
            }
        }
        
        updateSiteConnections: do
        {
            // TODO: move this somewhere sensible
            SiteButton.cellClass = SiteButtonCell.self
            
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
                let button = (subviewPool.popLast() ?? SiteButton(title: "", target: self, action: #selector(toggleConnection))) as! NSButton
                button.bezelStyle = bezel
                button.setButtonType(type)
                button.showsBorderOnlyWhileMouseInside = onlineButton.showsBorderOnlyWhileMouseInside
                button.font = onlineButton.font
                button.title = "\(site)"
                button.tag = Int(site)
                if site == delegate.siteId(forControlViewController: self)
                {
                    button.isEnabled = false
                    button.state = .off
                    (button.cell as? SiteButtonCell)?.textColor = NSColor.init(hue: 0.33, saturation: 0.88, brightness: 0.78, alpha: 1)
                }
                else
                {
                    let connected = delegate.isConnected(toSite: site, forControlViewController: self)
                    button.isEnabled = true
                    button.state = (connected ? .on : .off)
                    (button.cell as? SiteButtonCell)?.textColor = (delegate.isOnline(forControlViewController: self) ? nil : (connected ? NSColor.darkGray : NSColor.lightGray))
                }
                button.isEnabled = (delegate.isOnline(forControlViewController: self) ? button.isEnabled : false)
                connectionStack.addArrangedSubview(button)
            }
        }
    }
}

class SiteButton: NSButton {}
class SiteButtonCell: NSButtonCell
{
    var textColor: NSColor?
    
    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect
    {
        guard let color = self.textColor else
        {
            return super.drawTitle(title, withFrame: frame, in: controlView)
        }
        
        // PERF: quite slow, but it's a demo app, silly
        if !self.isEnabled
        {
            let disabledColor = color.withAlphaComponent(0.6)
            
            let title = NSMutableAttributedString(attributedString: self.attributedTitle)
            title.removeAttribute(NSAttributedString.Key.foregroundColor, range: NSMakeRange(0, title.length))
            title.addAttribute(NSAttributedString.Key.foregroundColor, value: disabledColor, range: NSMakeRange(0, title.length))
            
            return super.drawTitle(title, withFrame: frame, in: controlView)
        }
        else
        {
            let title = NSMutableAttributedString(attributedString: self.attributedTitle)
            title.removeAttribute(NSAttributedString.Key.foregroundColor, range: NSMakeRange(0, title.length))
            title.addAttribute(NSAttributedString.Key.foregroundColor, value: color, range: NSMakeRange(0, title.length))
            
            return super.drawTitle(title, withFrame: frame, in: controlView)
        }
    }
}
