//
//  CausalTreeDrawEditingView.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-20.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

// NEXT: end token
// PERF: most of the algorithms in here are O(N) inefficient, to say nothing of the underlying CRDT perf

import AppKit

/////////////////
// MARK: - View -
/////////////////

class CausalTreeDrawEditingView: NSView, CausalTreeListener
{
    var buttonStack: NSStackView
    var b1: NSButton
    var b2: NSButton
    var b3: NSButton
    var b4: NSButton
    var b5: NSButton
    
    var drawBounds: NSRect { return self.bounds }
    
    let selectionRadius: CGFloat = 10
    var selection: CausalTreeBezierWrapper.PermPointId? = nil
    {
        didSet
        {
            reloadData()
        }
    }
    
    var mouse: (start:NSPoint, delta:NSPoint)?
    {
        didSet
        {
            setNeedsDisplay(self.bounds)
        }
    }
    
    var model: CausalTreeBezierWrapper
    
    //////////////////////
    // MARK: - Lifecycle -
    //////////////////////
    
    required init(frame frameRect: NSRect, crdt: CausalTreeBezierT)
    {
        self.model = CausalTreeBezierWrapper(crdt: crdt)
        
        self.buttonStack = NSStackView()
        self.b1 = NSButton(title: "New Shape", target: nil, action: nil)
        self.b3 = NSButton(title: "Append Point", target: nil, action: nil)
        self.b4 = NSButton(title: "Delete Point", target: nil, action: nil)
        self.b2 = NSButton(title: "Cycle Shape Color", target: nil, action: nil)
        self.b5 = NSButton(title: "Cycle Point Round", target: nil, action: nil)
        
        super.init(frame: frameRect)
        
        self.wantsLayer = true
        self.layer!.backgroundColor = NSColor.white.cgColor
        
        self.addSubview(buttonStack)
        buttonStack.addArrangedSubview(b1)
        buttonStack.addArrangedSubview(b3)
        buttonStack.addArrangedSubview(b4)
        buttonStack.addArrangedSubview(b2)
        buttonStack.addArrangedSubview(b5)
        
        let metrics: [String:NSNumber] = [:]
        let views: [String:Any] = ["stack":buttonStack]
        
        setupButtons: do
        {
            self.b1.target = self
            self.b2.target = self
            self.b3.target = self
            self.b4.target = self
            self.b5.target = self
            self.b1.action = #selector(newShape)
            self.b3.action = #selector(addPoint)
            self.b4.action = #selector(deletePoint)
            self.b2.action = #selector(cycleShapeColor)
            self.b5.action = #selector(cyclePointRoundness)
            
            b1.translatesAutoresizingMaskIntoConstraints = false
            b2.translatesAutoresizingMaskIntoConstraints = false
            b3.translatesAutoresizingMaskIntoConstraints = false
            b4.translatesAutoresizingMaskIntoConstraints = false
            b5.translatesAutoresizingMaskIntoConstraints = false
            
            b1.widthAnchor.constraint(equalTo: buttonStack.widthAnchor).isActive = true
            b2.widthAnchor.constraint(equalTo: buttonStack.widthAnchor).isActive = true
            b3.widthAnchor.constraint(equalTo: buttonStack.widthAnchor).isActive = true
            b4.widthAnchor.constraint(equalTo: buttonStack.widthAnchor).isActive = true
            b5.widthAnchor.constraint(equalTo: buttonStack.widthAnchor).isActive = true
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
    
    func causalTreeDidUpdate()
    {
        timeMe({
            try! self.model.validate()
        }, "Upper Layer Validation")
        
        reloadData()
    }
    
    func reloadData()
    {
        updateUi: do
        {
            b2.isEnabled = (model.shapesCount() > 0)
            b3.isEnabled = (model.shapesCount() > 0 && selection != nil)
            b4.isEnabled = (model.shapesCount() > 0 && selection != nil)
            b5.isEnabled = (model.shapesCount() > 0 && selection != nil)
            
            if let sel = selection
            {
                if model.isLastPoint(sel)
                {
                    self.b3.title = "Append Point"
                }
                else
                {
                    self.b3.title = "Insert Point"
                }
            }
        }
        
        self.setNeedsDisplay(self.bounds)
    }
    
    ////////////////////
    // MARK: - Drawing -
    ////////////////////
    
    override func draw(_ dirtyRect: NSRect)
    {
        let selectionShape: CausalTreeBezierWrapper.ShapeId?
        if let sel = selection
        {
            selectionShape = model.shape(forPoint: sel)
        }
        else
        {
            selectionShape = nil
        }
        
        func sp(_ s: CausalTreeBezierWrapper.ShapeId, _ p: CausalTreeBezierWrapper.PointId) -> NSPoint
        {
            let point = model.pointValue(p)!
            
            guard let m = mouse, let sel = selection else
            {
                return point
            }
            
            // visualize a) point translation, b) shape translation operation before committing
            if selectionShape == s && (sel == model.firstPoint(inShape: s) || sel == p)
            {
                return NSMakePoint(point.x + m.delta.x, point.y + m.delta.y)
            }
            else
            {
                return point
            }
        }
        
        let shapes = model.shapes()
        
        for s in shapes
        {
            let pts = model.points(forShape: s)
            
            drawShape: do
            {
                if pts.count <= 1
                {
                    break drawShape
                }
                
                let path = NSBezierPath()
                
                for (i,p) in pts.enumerated()
                {
                    let shiftedPoint = sp(s,p)
                    
                    let prePointIndex = pts[pts.index(pts.startIndex, offsetBy: ((Int64(i - 1) % pts.count) + pts.count) % pts.count)]
                    let postPointIndex = pts[pts.index(pts.startIndex, offsetBy: ((Int64(i + 1) % pts.count) + pts.count) % pts.count)]
                    let midPrePoint = NSPoint((Vector2(sp(s, prePointIndex)) + Vector2(shiftedPoint)) / 2)
                    let midPostPoint = NSPoint((Vector2(sp(s, postPointIndex)) + Vector2(shiftedPoint)) / 2)
                    
                    if path.elementCount == 0
                    {
                        path.move(to: midPrePoint)
                    }
                    else
                    {
                        path.line(to: midPrePoint)
                    }
                    
                    if model.attributes(forPoint: p)
                    {
                        path.curve(to: midPostPoint, controlPoint1: shiftedPoint, controlPoint2: shiftedPoint)
                    }
                    else
                    {
                        path.line(to: shiftedPoint)
                        path.line(to: midPostPoint)
                    }
                }
                
                NSColor.black.setStroke()
                model.attributes(forShape: s).setFill()
                path.lineWidth = 1.5
                path.lineJoinStyle = .roundLineJoinStyle
                path.close()
                
                path.stroke()
                path.fill()
                
                drawGreenLine: do
                {
                    break drawGreenLine
                    let theFirstPoint = sp(s, model.firstPoint(inShape: s)!)
                    let theLastPoint = sp(s, model.lastPoint(inShape: s)!)
                    
                    let line = NSBezierPath()
                    line.move(to: theLastPoint)
                    line.line(to: theFirstPoint)
                    
                    NSColor.green.setStroke()
                    line.lineWidth = 1.5
                    
                    line.stroke()
                }
            }
            
            drawPoints: do
            {
                for i in pts
                {
                    let shiftedPoint = sp(s,i)
                    
                    let radius: CGFloat = 3
                    let point = NSBezierPath(ovalIn: NSMakeRect(shiftedPoint.x-radius, shiftedPoint.y-radius, radius*2, radius*2))

                    (model.isFirstPoint(i) ?
                        NSColor.green : (model.isLastPoint(i) ?
                            NSColor.red : (selectionShape == s && selection == i ?
                                NSColor.black.withAlphaComponent(1) : NSColor.black.withAlphaComponent(0.5)))).setFill()
                    
                    point.fill()

                    if selectionShape == s && selection == i
                    {
                        let radius: CGFloat = 4
                        let point = NSBezierPath(ovalIn: NSMakeRect(shiftedPoint.x-radius, shiftedPoint.y-radius, radius*2, radius*2))

                        NSColor.blue.setStroke()
                        
                        point.stroke()
                    }
                }
            }
        }
        
        // mouse selection circle
        if let sel = mouse
        {
            let pos = NSMakePoint(sel.start.x + sel.delta.x, sel.start.y + sel.delta.y)
            
            let radius: CGFloat = selectionRadius
            let point = NSBezierPath(ovalIn: NSMakeRect(pos.x-radius, pos.y-radius, radius*2, radius*2))
            
            NSColor.blue.withAlphaComponent(0.25).setFill()
            point.fill()
        }
    }
    
    //////////////////
    // MARK: - Mouse -
    //////////////////
    
    override func mouseDown(with event: NSEvent)
    {
        let m = self.convert(event.locationInWindow, from: nil)
        
        var select: CausalTreeBezierWrapper.PointId? = nil
        
        findSelection: do
        {
            let shapes = model.shapes()
            
            for s in shapes
            {
                let pts = model.points(forShape: s)
                
                for p in pts
                {
                    guard let val = model.pointValue(p) else
                    {
                        continue
                    }
                    
                    if sqrt(pow(val.x - m.x, 2) + pow(val.y - m.y, 2)) < selectionRadius
                    {
                        select = p
                        break findSelection
                    }
                }
            }
        }
        
        mouse = (m, NSPoint.zero)
        selection = select
    }
    
    override func mouseDragged(with event: NSEvent)
    {
        guard let m = mouse else { return }
        
        let newM = self.convert(event.locationInWindow, from: nil)
        
        mouse = (m.start, NSMakePoint(newM.x - m.start.x, newM.y - m.start.y))
    }

    override func mouseUp(with event: NSEvent)
    {
        commitSelections: if let sel = selection, let m = mouse
        {
            if model.isFirstPoint(sel)
            {
                let shape = model.shape(forPoint: sel)
                model.updateShape(shape, withDelta: m.delta)
            }
            else
            {
                model.updateShapePoint(sel, withDelta: m.delta)
            }
        }
        
        mouse = nil
        
        reloadData()
    }
    
    ////////////////////
    // MARK: - Buttons -
    ////////////////////
    
    @objc func newShape()
    {
        let randX = (CGFloat(arc4random_uniform(1001))/CGFloat(1000)) * drawBounds.width
        let randY = (CGFloat(arc4random_uniform(1001))/CGFloat(1000) * drawBounds.height)
        
        let newShape = model.addShape(atX: randX, y: randY)
        model.updateAttributes(color: randomColor(), forShape: newShape)
        
        self.selection = model.firstPoint(inShape: newShape)!
        
        self.reloadData()
    }
    
    @objc func addPoint()
    {
        guard let p = selection else { return }
        
        let sel = model.addShapePoint(afterPoint: p, withBounds: drawBounds)
        
        self.selection = sel
        self.reloadData()
    }
    
    @objc func deletePoint()
    {
        guard let p = selection else { return }
        
        let prevPoint = model.nextValidPoint(beforePoint: p)
        model.deleteShapePoint(p)
        
        self.selection = prevPoint
        self.reloadData()
    }
    
    @objc func cycleShapeColor()
    {
        guard let sel = selection else
        {
            return
        }
        
        let shape = model.shape(forPoint: sel)
        
        let color = randomColor()
        model.updateAttributes(color: color, forShape: shape)
        
        reloadData()
    }
    
    @objc func cyclePointRoundness()
    {
        guard let sel = selection else
        {
            return
        }
        
        let rounded = !model.attributes(forPoint: sel)
        model.updateAttributes(rounded: rounded, forPoint: sel)
        
        reloadData()
    }
}

/////////////////
// MARK: - Util -
/////////////////

func randomColor() -> NSColor
{
    let hue = CGFloat(arc4random_uniform(1000))/1001.0
    return NSColor(hue: hue, saturation: 0.5, brightness: 0.99, alpha: 1)
}
