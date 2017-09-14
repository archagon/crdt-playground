//
//  ControlViewController.swift
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

protocol ControlViewControllerDelegate: class
{
    func isOnline(forControlViewController: ControlViewController) -> Bool
    func isConnected(toSite: SiteId, forControlViewController: ControlViewController) -> Bool
    func goOnline(_ online: Bool, forControlViewController: ControlViewController)
    func connect(_ connect: Bool, toSite: SiteId, forControlViewController: ControlViewController)
    func allSites(forControlViewController: ControlViewController) -> [SiteId]
    func showWeave(forControlViewController: ControlViewController)
    func showAwareness(forAtom: CausalTreeT.WeaveT.AtomId?, inControlViewController: ControlViewController)
    func printWeave(forControlViewController: ControlViewController)
    func generateWeave(forControlViewController: ControlViewController) -> String
    func generateCausalBlock(forAtom atom: CausalTreeT.WeaveT.AtomId, inControlViewController vc: ControlViewController) -> CountableClosedRange<CausalTreeT.WeaveT.WeaveIndex>?
    func appendAtom(toAtom: CausalTreeT.WeaveT.AtomId?, forControlViewController: ControlViewController)
    func addSite(forControlViewController: ControlViewController)
    func siteUUID(forControlViewController: ControlViewController) -> UUID
    func siteId(forControlViewController: ControlViewController) -> SiteId
    func selectedAtom(forControlViewController: ControlViewController) -> CausalTreeT.WeaveT.AtomId?
    func atomIdForWeaveIndex(_ weaveIndex: CausalTreeT.WeaveT.WeaveIndex, forControlViewController: ControlViewController) -> CausalTreeT.WeaveT.AtomId?
    func atomWeft(_ atom: CausalTreeT.WeaveT.AtomId, forControlViewController: ControlViewController) -> CausalTreeT.WeaveT.Weft
    func dataView(forControlViewController: ControlViewController) -> NSView
}

class ControlViewController: NSViewController
{
    @IBOutlet var siteUUIDLabel: NSTextField!
    @IBOutlet var siteIdLabel: NSTextField!
    @IBOutlet var selectedAtomLabel: NSTextField!
    @IBOutlet var selectedAtomWeftLabel: NSTextField!
    @IBOutlet var lastOperationDurationLabel: NSTextField!
    @IBOutlet var showWeaveButton: NSButton!
    @IBOutlet var addSiteButton: NSButton!
    @IBOutlet var printWeaveButton: NSButton!
    @IBOutlet var generateWeaveButton: NSButton!
    @IBOutlet var onlineButton: NSButton!
    @IBOutlet var generateAwarenessButton: NSButton!
    @IBOutlet var appendAtomButton: NSButton!
    @IBOutlet var generateCausalBlockButton: NSButton!
    @IBOutlet var connectionStack: NSStackView!
    @IBOutlet var dataView: NSView!
    
    weak var delegate: ControlViewControllerDelegate?
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
        printWeaveButton.target = self
        printWeaveButton.action = #selector(printWeave)
        onlineButton.target = self
        onlineButton.action = #selector(toggleOnline)
        generateWeaveButton.target = self
        generateWeaveButton.action = #selector(generateWeave)
        generateAwarenessButton.target = self
        generateAwarenessButton.action = #selector(generateAwareness)
        appendAtomButton.target = self
        appendAtomButton.action = #selector(appendAtom)
        generateCausalBlockButton.target = self
        generateCausalBlockButton.action = #selector(generateCausalBlock)
        
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
        let start = CACurrentMediaTime()
        self.delegate?.printWeave(forControlViewController: self)
        let end = CACurrentMediaTime()
        updateLastOperationDuration(type: "Print", ms: end - start)
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
    
    @objc func generateCausalBlock(sender: NSButton)
    {
        guard let delegate = self.delegate else { return }
        if let atom = delegate.selectedAtom(forControlViewController: self)
        {
            let start = CACurrentMediaTime()
            let causalBlock = delegate.generateCausalBlock(forAtom: atom, inControlViewController: self)!
            let end = CACurrentMediaTime()
            updateLastOperationDuration(type: "Causal Block", ms: (end - start))
            
            var printVal = ""
            for i in 0..<causalBlock.count
            {
                let index = causalBlock.lowerBound + CausalTreeT.WeaveT.WeaveIndex(i)
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
    
    func reloadData()
    {
        guard let delegate = self.delegate else { return }
        
        let hasSelectedAtom = delegate.selectedAtom(forControlViewController: self) != nil
        self.generateAwarenessButton.isEnabled = hasSelectedAtom
        self.generateCausalBlockButton.isEnabled = hasSelectedAtom
        
        self.siteUUIDLabel.stringValue = "Site: \(delegate.siteUUID(forControlViewController: self))"
        self.siteIdLabel.stringValue = "Site ID: \(delegate.siteId(forControlViewController: self))"
        
        if let atom = delegate.selectedAtom(forControlViewController: self)
        {
            self.selectedAtomLabel.stringValue = "Selected Atom: \(atom.site):\(atom.index)"
            self.selectedAtomWeftLabel.stringValue = "Selected Atom Weft: \(delegate.atomWeft(atom, forControlViewController: self))"
        }
        else
        {
            self.selectedAtomLabel.stringValue = "Selected Atom: (none)"
            self.selectedAtomWeftLabel.stringValue = "Selected Atom Weft: (none)"
        }
        
        updateConnections: do
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
