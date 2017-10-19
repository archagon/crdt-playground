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

    func configureView()
    {
        // Update the user interface for the detail item.
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
        // Do any additional setup after loading the view, typically from a nib.
        configureView()
    }

    override func didReceiveMemoryWarning()
    {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    var detailItem: NSDate?
    {
        didSet
        {
            // Update the view.
            configureView()
        }
    }
}

