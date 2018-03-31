//
//  DetailViewController.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-19.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import UIKit
import CloudKit

class DetailViewController: UIViewController, UITextViewDelegate, UICloudSharingControllerDelegate {
    class Model {
        var crdt: CRDTTextEditing
        var textStorage: CausalTreeCloudKitTextStorage

        init(crdt: CRDTTextEditing) {
            self.crdt = crdt
            self.textStorage = CausalTreeCloudKitTextStorage(withCRDT: crdt.ct)
        }
    }

    @IBOutlet weak var textViewContainer: UIView!
    @IBOutlet weak var cursorDrawingView: CursorDrawingView!
    var textView: UITextView!

    var crdt: CRDTTextEditing? {
        get {
            return model?.crdt
        }
        set {
            if newValue == nil {
                model = nil
            }
            else if newValue != model?.crdt {
                model = Model(crdt: newValue!)
                configureView()
            }
        }
    }
    var id: Network.FileID?

    private var model: Model?

    private func configureView() {
        guard let view = self.viewIfLoaded, let model = self.model else {
            return
        }

        self.textView?.removeFromSuperview()
        self.textView?.delegate = nil
        self.textView = nil
        for man in model.textStorage.layoutManagers { model.textStorage.removeLayoutManager(man) }

        configureTextView: do {
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

    func reloadData() {
        if let model = self.model {
            model.textStorage.reloadData()
            reloadCursors(remoteOnly: false)
        }
    }

    func reloadCursors(remoteOnly: Bool = true) {
        guard let model = self.model else {
            return
        }

        if let cursorDrawingView = self.cursorDrawingView {
            cursorDrawingView.cursors = [:]

            for pair in model.crdt.cursorMap.map {
                if pair.key == model.crdt.cursorMap.owner {
                    continue
                }

                if let rect = cursorRect(for: pair.value.value) {
                    cursorDrawingView.cursors[pair.key] = rect
                }
            }
        }

        if !remoteOnly {
            if let textView = self.textView {
                if
                    let val = model.crdt.cursorMap.value(forKey: model.crdt.cursorMap.owner),
                    let range = textView.selectedTextRange,
                    let location = model.textStorage.backedString.characterIndex(for: val) {
                    let length = textView.offset(from: range.start, to: range.end)
                    let start = textView.position(from: textView.beginningOfDocument, offset: location)!
                    let end = textView.position(from: start, offset: length)!
                    textView.selectedTextRange = textView.textRange(from: start, to: end)
                }
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = UIColor(hue: 0, saturation: 0, brightness: 0.95, alpha: 1)

        NotificationCenter.default.addObserver(forName: .InstanceChangedInternally, object: nil, queue: nil) { n in
            self.reloadData()
        }

        configureView()
        reloadData()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard let model = self.model else {
            return
        }

        let cursorIndex = textView.selectedRange.location
        if let cursorAtomId = model.textStorage.backedString.atomForCharacterAtIndex(cursorIndex) {
            model.crdt.cursorMap.setValue(cursorAtomId)
        }

        //let cursorAtom = model.crdt.ct.weave.atomForId(cursorAtomId)!
        //print("Cursor at atom: \(Character(UnicodeScalar.init(cursorAtom.value)!))")
    }

    func textViewDidChange(_ textView: UITextView) {
        reloadCursors()
    }

    func cursorRect(for a: AtomId) -> CGRect? {
        guard let model = self.model else {
            return nil
        }

        guard let cursorIndex = model.textStorage.backedString.characterIndex(for: a) else {
            return nil
        }

        let pos = textView.position(from: textView.beginningOfDocument, offset: cursorIndex)!
        let rect = textView.caretRect(for: pos)

        return rect
    }

    var _networkIdForShare: [String:Network.FileID] = [:] //TODO: this needs to be cleaned up
    @IBAction func shareButtonTapped(_ button: UIBarButtonItem) {
        guard let model = self.model else {
            return
        }

        guard
            let memoryId = DataStack.sharedInstance.memory.id(for: model.crdt),
            let networkId = DataStack.sharedInstance.memoryNetworkLayer.network(forMemory: memoryId),
            let metadata = DataStack.sharedInstance.network.metadata(networkId)
        else {
            return
        }

        let shareController: UICloudSharingController

        if let share = metadata.associatedShare {
            shareController = UICloudSharingController(share: share, container: CKContainer.default())
            self._networkIdForShare[metadata.associatedShare!.recordID.recordName] = networkId
        }
        else {
            shareController = UICloudSharingController { controller, completionBlock in
                DataStack.sharedInstance.network.share(networkId) { error in
                    if let error = error {
                        completionBlock(nil, nil, error)
                    }
                    else {
                        let metadata = DataStack.sharedInstance.network.metadata(networkId)! //metadata has been updated
                        self._networkIdForShare[metadata.associatedShare!.recordID.recordName] = networkId
                        completionBlock(metadata.associatedShare, CKContainer.default(), nil)
                    }
                }
            }
        }

        shareController.delegate = self

        if let popover = shareController.popoverPresentationController {
            popover.barButtonItem = button
        }

        self.present(shareController, animated: true) {}
    }
    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        // TODO: fails when fiddling with options
        DataStack.sharedInstance.network.associateShare(csc.share!, withId: _networkIdForShare[csc.share!.recordID.recordName]!)
        //_networkIdForShare[csc.share!.recordID.recordName] = nil
        print("Did save share!")
    }
    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        DataStack.sharedInstance.network.associateShare(nil, withId: _networkIdForShare[csc.share!.recordID.recordName]!)
        _networkIdForShare[csc.share!.recordID.recordName] = nil
        print("Did stop sharing!")
    }
    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        // TODO: fails when add, remove, add again
        assert(false, "Could not share: \(error)")
    }

    func itemTitle(for csc: UICloudSharingController) -> String? {
        guard let model = self.model else {
            return nil
        }

        guard
            let memoryId = DataStack.sharedInstance.memory.id(for: model.crdt),
            let networkId = DataStack.sharedInstance.memoryNetworkLayer.network(forMemory: memoryId),
            let metadata = DataStack.sharedInstance.network.metadata(networkId)
            else {
            return nil
        }

        return metadata.name
    }
}

class CursorDrawingView: UIView {
    var cursors: [UUID:CGRect] = [:] {
        didSet {
            self.setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        for cursor in cursors {
            let randomHue = CGFloat(cursor.key.hashValue % 1000)/999
            let randomColor = UIColor(hue: randomHue, saturation: 0.7, brightness: 0.9, alpha: 1)

            let path = UIBezierPath(rect: cursor.value)
            NSColor.random().setFill()
            path.fill()
        }
    }
}
