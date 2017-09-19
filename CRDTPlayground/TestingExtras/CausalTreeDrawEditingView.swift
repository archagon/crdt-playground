//
//  CausalTreeDrawEditingView.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-20.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import AppKit

class CausalTreeDrawEditingView: NSView
{
    var buttonStack: NSStackView
    var b1: NSButton
    var b2: NSButton
    var b3: NSButton
    var b4: NSButton
    
    override init(frame frameRect: NSRect)
    {
        self.buttonStack = NSStackView()
        self.b1 = NSButton(title: "New Shape", target: nil, action: nil)
        self.b2 = NSButton(title: "Cycle Points", target: nil, action: nil)
        self.b3 = NSButton(title: "Add Point", target: nil, action: nil)
        self.b4 = NSButton(title: "Delete Point", target: nil, action: nil)
        
        super.init(frame: frameRect)
        
        self.wantsLayer = true
        self.layer!.backgroundColor = NSColor.white.cgColor
        
        self.addSubview(buttonStack)
        buttonStack.addArrangedSubview(b1)
        buttonStack.addArrangedSubview(b2)
        buttonStack.addArrangedSubview(b3)
        buttonStack.addArrangedSubview(b4)
        
        let metrics: [String:NSNumber] = [:]
        let views: [String:Any] = ["stack":buttonStack]
        
        setupButtons: do
        {
            self.b1.target = self
            self.b2.target = self
            self.b3.target = self
            self.b4.target = self
            self.b1.action = #selector(newShape)
            self.b2.action = #selector(cyclePoints)
            self.b3.action = #selector(addPoint)
            self.b4.action = #selector(deletePoint)
            
            b1.translatesAutoresizingMaskIntoConstraints = false
            b2.translatesAutoresizingMaskIntoConstraints = false
            b3.translatesAutoresizingMaskIntoConstraints = false
            b4.translatesAutoresizingMaskIntoConstraints = false
            
            b1.widthAnchor.constraint(equalTo: buttonStack.widthAnchor).isActive = true
            b2.widthAnchor.constraint(equalTo: buttonStack.widthAnchor).isActive = true
            b3.widthAnchor.constraint(equalTo: buttonStack.widthAnchor).isActive = true
            b4.widthAnchor.constraint(equalTo: buttonStack.widthAnchor).isActive = true
        }
        
        setupButtonStack: do
        {
            buttonStack.orientation = .vertical
            buttonStack.spacing = 2
            
            buttonStack.translatesAutoresizingMaskIntoConstraints = false
            let hConstraints = NSLayoutConstraint.constraints(withVisualFormat: "H:[stack]|", options: [], metrics: metrics, views: views)
            let vConstraints = NSLayoutConstraint.constraints(withVisualFormat: "V:|[stack]", options: [], metrics: metrics, views: views)
            NSLayoutConstraint.activate(hConstraints)
            NSLayoutConstraint.activate(vConstraints)
        }
    }
    
    required init?(coder decoder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect)
    {
        for shape in shapes
        {
            let path = NSBezierPath()
            
            for (i,point) in shape.enumerated()
            {
                if point.x.isNaN && point.y.isNaN
                {
                    continue
                }
                
                if path.elementCount == 0
                {
                    path.move(to: point)
                }
                else
                {
                    path.line(to: point)
                }
            }
            
            NSColor.black.setStroke()
            NSColor.yellow.setFill()
            path.lineWidth = 3
            path.lineJoinStyle = .roundLineJoinStyle
            path.close()
            path.stroke()
            path.fill()
        }
        
        var it = 0
        for shape in shapes
        {
            for (i,p) in shape.enumerated()
            {
                if p.x.isNaN && p.y.isNaN
                {
                    it += 1
                    continue
                }

                let radius: CGFloat = 4
                let point = NSBezierPath(ovalIn: NSMakeRect(p.x-radius, p.y-radius, radius*2, radius*2))

                NSColor.red.setFill()
                point.fill()

                if it == selectedPoint
                {
                    let radius: CGFloat = 6
                    let point = NSBezierPath(ovalIn: NSMakeRect(p.x-radius, p.y-radius, radius*2, radius*2))

                    NSColor.blue.setStroke()
                    point.stroke()
                }

                it += 1
            }
        }
    }
    
    func reloadData()
    {
        updateUi: do
        {
            b2.isEnabled = (shapes.count > 0)
            b3.isEnabled = (shapes.count > 0 && selectedPoint != nil)
            b4.isEnabled = (shapes.count > 0 && selectedPoint != nil)
        }
        
        self.setNeedsDisplay(self.bounds)
    }
    
    // TODO: replace with CRDT
    var shapes: [[NSPoint]] = []
    var selectedPoint: Int? = nil
    var drawBounds: NSRect { return self.bounds }
    
    func totalCount() -> Int
    {
        return shapes.reduce(0, { (r,s) in r+s.count })
    }
    
    @objc func newShape()
    {
        let randX = (CGFloat(arc4random_uniform(1001))/CGFloat(1000)) * drawBounds.width
        let randY = (CGFloat(arc4random_uniform(1001))/CGFloat(1000) * drawBounds.height)
        
        shapes += [[NSMakePoint(randX, randY)]]
        
        self.selectedPoint = totalCount() - 1
        
        self.reloadData()
    }
    
    @objc func cyclePoints()
    {
        if let p = selectedPoint
        {
            if p == totalCount() - 1
            {
                selectedPoint = nil
            }
            else
            {
                selectedPoint = p + 1
            }
        }
        else
        {
            if shapes.count > 0
            {
                selectedPoint = 0
            }
        }
        
        reloadData()
    }
    
    @objc func addPoint()
    {
        guard let p = selectedPoint else { return }
        
        let jx: CGFloat = 40
        let jy: CGFloat = 20
        let jitterX = (CGFloat(arc4random_uniform(1001))/CGFloat(1000)) * jx * 2 - jx
        let jitterY = (CGFloat(arc4random_uniform(1001))/CGFloat(1000)) * jy * 2 - jy
        
        let shapesLast = shapes.count-1
        shapes[shapesLast].append(NSMakePoint(shapes[shapesLast][shapes[shapesLast].count-1].x + jitterX,
                                              shapes[shapesLast][shapes[shapesLast].count-1].y + jitterY))
        
        self.selectedPoint = totalCount() - 1
        
        self.reloadData()
 
//        var it = 0
//        for shape in shapes
//        {
//            for (i,p) in shape.enumerated()
//            {
//                if it == p
//                {
//                    
//                }
//
//                it += 1
//            }
//        }
    }
    
    @objc func deletePoint()
    {
        guard let p = selectedPoint else { return }
        
        var it = 0
        findPoint: do
        {
            for (s,shape) in shapes.enumerated()
            {
                for (i,point) in shape.enumerated()
                {
                    if it == p
                    {
                        shapes[s][i] = NSMakePoint(CGFloat.nan, CGFloat.nan)
                        break findPoint
                    }

                    it += 1
                }
            }
        }
        
        if it == 0
        {
            if totalCount() != 0
            {
                self.selectedPoint = 0
            }
        }
        else
        {
            if totalCount() != 0
            {
                self.selectedPoint = p - 1
            }
        }
        
        self.reloadData()
    }
}
