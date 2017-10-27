//
//  DetailViewController.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-19.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import UIKit

class DetailViewController: UIViewController, UITextViewDelegate
{
    class Model
    {
        var crdt: CRDTTextEditing
        var textStorage: CausalTreeCloudKitTextStorage
        
        init(crdt: CRDTTextEditing)
        {
            self.crdt = crdt
            self.textStorage = CausalTreeCloudKitTextStorage(withCRDT: crdt.ct)
        }
    }
    
    @IBOutlet weak var detailDescriptionLabel: UILabel!
    @IBOutlet weak var textViewContainer: UIView!
    var textView: UITextView!

    var crdt: CRDTTextEditing?
    {
        get
        {
            return model?.crdt
        }
        set
        {
            if newValue == nil
            {
                model = nil
            }
            else if newValue != model?.crdt
            {
                model = Model(crdt: newValue!)
                configureView()
            }
        }
    }
    private var model: Model?
    
    private func configureView()
    {
        guard let view = self.viewIfLoaded, let model = self.model else
        {
            return
        }
        
        self.textView?.removeFromSuperview()
        self.textView?.delegate = nil
        self.textView = nil
        for man in model.textStorage.layoutManagers { model.textStorage.removeLayoutManager(man) }
        
        configureTextView: do
        {
            let contentSize = view.bounds.size
            
            let textContainer = NSTextContainer()
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
            textContainer.lineBreakMode = .byCharWrapping
            textContainer.size = CGSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            let layoutManager = NSLayoutManager()
            layoutManager.addTextContainer(textContainer)
            model.textStorage.addLayoutManager(layoutManager)
            
            let textView = UITextView(frame: CGRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height), textContainer: textContainer)
            
            self.textView = textView
            self.textView.delegate = self
            self.textViewContainer.addSubview(textView)
            
            textView.translatesAutoresizingMaskIntoConstraints = false
            let hConstraints = NSLayoutConstraint.constraints(withVisualFormat: "H:|[view]|", options: [], metrics: nil, views: ["view":textView])
            let vConstraints = NSLayoutConstraint.constraints(withVisualFormat: "V:|[view]|", options: [], metrics: nil, views: ["view":textView])
            NSLayoutConstraint.activate(hConstraints)
            NSLayoutConstraint.activate(vConstraints)
        }
    }
    
    func reloadData()
    {
        if let model = self.model
        {
            model.textStorage.reloadData()
        }
    }

    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.view.backgroundColor = UIColor(hue: 0, saturation: 0, brightness: 0.95, alpha: 1)
        
        NotificationCenter.default.addObserver(forName: Memory.InstanceChangedInternallyNotification, object: nil, queue: nil)
        { n in
            self.reloadData()
        }
        
        configureView()
    }
    
    func textViewDidChangeSelection(_ textView: UITextView)
    {
        guard let model = self.model else
        {
            return
        }
        
        let cursorIndex = textView.selectedRange.location
        let cursorAtomId = model.textStorage.backedString.atomForCharacterAtIndex(cursorIndex)
        
        self.crdt?.cursorMap.setValue(cursorAtomId)
        
        //let cursorAtom = model.crdt.ct.weave.atomForId(cursorAtomId)!
        //print("Cursor at atom: \(Character(UnicodeScalar.init(cursorAtom.value)!))")
    }
}
