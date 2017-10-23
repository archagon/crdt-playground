//
//  DetailViewController.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-19.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import UIKit

class DetailViewController: UIViewController
{
    @IBOutlet weak var detailDescriptionLabel: UILabel!
    @IBOutlet weak var textViewContainer: UIView!
    var textView: UITextView!

    var crdt: CausalTreeString!
    
    func configureView()
    {
        if let detail = detailItem
        {
            if let label = detailDescriptionLabel
            {
                label.text = detail.description
            }
        }
    }

    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.view.backgroundColor = UIColor(hue: 0, saturation: 0, brightness: 0.95, alpha: 1)
        
        configureTextView: do
        {
            let contentSize = self.view.bounds.size
            
            let textStorage = CausalTreeCloudKitTextStorage(withCRDT: crdt)
            let textContainer = NSTextContainer()
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
            textContainer.lineBreakMode = .byCharWrapping
            textContainer.size = CGSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            let layoutManager = NSLayoutManager()
            layoutManager.addTextContainer(textContainer)
            textStorage.addLayoutManager(layoutManager)
            
            let textView = UITextView(frame: CGRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height), textContainer: textContainer)
            //textView.minSize = CGSize(0, contentSize.height)
            //textView.maxSize = CGSize(CGFloat.greatestFiniteMagnitude, CGFloat.greatestFiniteMagnitude)
            //textView.isVerticallyResizable = true
            //textView.isHorizontallyResizable = false
            
            self.textView = textView
            self.textViewContainer.addSubview(textView)
            
            textView.translatesAutoresizingMaskIntoConstraints = false
            let hConstraints = NSLayoutConstraint.constraints(withVisualFormat: "H:|[view]|", options: [], metrics: nil, views: ["view":textView])
            let vConstraints = NSLayoutConstraint.constraints(withVisualFormat: "V:|[view]|", options: [], metrics: nil, views: ["view":textView])
            NSLayoutConstraint.activate(hConstraints)
            NSLayoutConstraint.activate(vConstraints)
        }
        
        configureView()
    }

    var detailItem: NSDate?
    {
        didSet
        {
            configureView()
        }
    }
}

