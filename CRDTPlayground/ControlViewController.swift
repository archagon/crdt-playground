//
//  ControlViewController.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-8.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

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
    func printWeave(forControlViewController: ControlViewController)
    func generateWeave(forControlViewController: ControlViewController) -> String
    func addAtom(forControlViewController: ControlViewController)
    func addSite(forControlViewController: ControlViewController)
    func siteUUID(forControlViewController: ControlViewController) -> UUID
    func siteId(forControlViewController: ControlViewController) -> SiteId
    func selectedAtom(forControlViewController: ControlViewController) -> CausalTreeT.WeaveT.Atom
    func atomWeft(_ atom: CausalTreeT.WeaveT.AtomId, forControlViewController: ControlViewController) -> CausalTreeT.WeaveT.Weft
}

class ControlViewController: NSViewController
{
    @IBOutlet var siteUUIDLabel: NSTextField!
    @IBOutlet var siteIdLabel: NSTextField!
    @IBOutlet var selectedAtomLabel: NSTextField!
    @IBOutlet var selectedAtomWeftLabel: NSTextField!
    @IBOutlet var lastOperationDurationLabel: NSTextField!
    @IBOutlet var showWeaveButton: NSButton!
    @IBOutlet var addAtomButton: NSButton!
    @IBOutlet var addSiteButton: NSButton!
    @IBOutlet var printWeaveButton: NSButton!
    @IBOutlet var generateWeaveButton: NSButton!
    @IBOutlet var onlineButton: NSButton!
    @IBOutlet var connectionStack: NSStackView!
    
    weak var delegate: ControlViewControllerDelegate?
    {
        didSet
        {
            reloadData()
        }
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        showWeaveButton.target = self
        showWeaveButton.action = #selector(showWeave)
        addAtomButton.target = self
        addAtomButton.action = #selector(addAtom)
        addSiteButton.target = self
        addSiteButton.action = #selector(addSite)
        printWeaveButton.target = self
        printWeaveButton.action = #selector(printWeave)
        onlineButton.target = self
        onlineButton.action = #selector(toggleOnline)
        generateWeaveButton.target = self
        generateWeaveButton.action = #selector(generateWeave)
        
        reloadData()
    }
    
    @objc func showWeave(sender: NSButton)
    {
        self.delegate?.showWeave(forControlViewController: self)
    }
    
    @objc func addAtom(sender: NSButton)
    {
        self.delegate?.addAtom(forControlViewController: self)
        reloadData()
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
    
    func reloadData()
    {
        guard let delegate = self.delegate else { return }
        
        self.siteUUIDLabel.stringValue = "Site: \(delegate.siteUUID(forControlViewController: self))"
        self.siteIdLabel.stringValue = "Site ID: \(delegate.siteId(forControlViewController: self))"
        let atom = delegate.selectedAtom(forControlViewController: self)
        self.selectedAtomLabel.stringValue = "Selected Atom: \(atom.id.site):\(atom.id.index)"
        self.selectedAtomWeftLabel.stringValue = "Selected Atom Weft: \(delegate.atomWeft(atom.id, forControlViewController: self))"
        
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
