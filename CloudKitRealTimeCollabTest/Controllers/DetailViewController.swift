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
    @IBOutlet weak var cursorDrawingView: CursorDrawingView!
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
            self.textView.backgroundColor = nil
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
            reloadCursors(remoteOnly: false)
        }
    }
    
    func reloadCursors(remoteOnly: Bool = true)
    {
        guard let model = self.model else
        {
            return
        }
        
        if let cursorDrawingView = self.cursorDrawingView
        {
            cursorDrawingView.cursors = [:]
            
            for pair in model.crdt.cursorMap.map
            {
                if pair.key == model.crdt.cursorMap.owner
                {
                    continue
                }
                
                if let rect = cursorRectForAtom(pair.value.value)
                {
                    cursorDrawingView.cursors[pair.key] = rect
                }
            }
        }
        
        if !remoteOnly
        {
            if let textView = self.textView
            {
                if
                    let val = model.crdt.cursorMap.value(forKey: model.crdt.cursorMap.owner),
                    let range = textView.selectedTextRange,
                    let location = model.textStorage.backedString.characterIndexForAtom(val)
                {
                    let length = textView.offset(from: range.start, to: range.end)
                    let start = textView.position(from: textView.beginningOfDocument, offset: location)!
                    let end = textView.position(from: start, offset: length)!
                    textView.selectedTextRange = textView.textRange(from: start, to: end)
                }
            }
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
        reloadData()
    }
    
    func textViewDidChangeSelection(_ textView: UITextView)
    {
        guard let model = self.model else
        {
            return
        }
        
        let cursorIndex = textView.selectedRange.location
        if let cursorAtomId = model.textStorage.backedString.atomForCharacterAtIndex(cursorIndex)
        {
            model.crdt.cursorMap.setValue(cursorAtomId)
        }
        
        //let cursorAtom = model.crdt.ct.weave.atomForId(cursorAtomId)!
        //print("Cursor at atom: \(Character(UnicodeScalar.init(cursorAtom.value)!))")
    }
    
    func textViewDidChange(_ textView: UITextView)
    {
        reloadCursors()
    }
    
    func cursorRectForAtom(_ a: AtomId) -> CGRect?
    {
        guard let model = self.model else
        {
            return nil
        }
        
        guard let cursorIndex = model.textStorage.backedString.characterIndexForAtom(a) else
        {
            return nil
        }
        
        let pos = textView.position(from: textView.beginningOfDocument, offset: cursorIndex)!
        let rect = textView.caretRect(for: pos)
        
        return rect
    }
}

class CursorDrawingView: UIView
{
    var cursors: [UUID:CGRect] = [:]
    {
        didSet
        {
            self.setNeedsDisplay()
        }
    }
    
    override func draw(_ rect: CGRect)
    {
        for cursor in cursors
        {
            let randomHue = CGFloat(cursor.key.hashValue % 1000)/999
            let randomColor = UIColor(hue: randomHue, saturation: 0.7, brightness: 0.9, alpha: 1)
            
            let path = UIBezierPath(rect: cursor.value)
            randomColor.setFill()
            path.fill()
        }
    }
}
