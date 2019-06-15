//
//  CausalTreeDrawEditingView.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-20.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

// PERF: most of the algorithms in here are O(N) inefficient, to say nothing of the underlying CRDT perf

import AppKit
//import CRDTFramework_OSX

/////////////////
// MARK: - View -
/////////////////

class CausalTreeDrawEditingView: NSView, CausalTreeContentView
{
    weak var listener: CausalTreeListener?
    
    var buttonStack: NSStackView
    var b1: NSButton
    var b2: NSButton
    var b3: NSButton
    var b4: NSButton
    var b5: NSButton
    
    var drawBounds: NSRect
    {
        var bounds = self.bounds
        bounds.size = NSMakeSize(bounds.width - self.buttonStack.bounds.width, bounds.height)
        return bounds
    }
    
    let selectionRadius: CGFloat = 10
    var selection: CausalTreeBezierWrapper.PermPointId? = nil
    {
        didSet
        {
            reloadData()
        }
    }
    
    /// **Complexity:** O(weave)
    var selectionIndex: CausalTreeBezierWrapper.TempPointId?
    {
        if let sel = selection
        {
            return model.point(forPermPoint: sel)
        }
        else
        {
            return nil
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
    
    let foregroundColorAttributes = [NSAttributedString.Key.foregroundColor: NSColor.black]
    
    required init(frame frameRect: NSRect, crdt: CausalTreeBezierT)
    {
        self.model = CausalTreeBezierWrapper(crdt: crdt)
        
        self.buttonStack = NSStackView()    
        self.b1 = NSButton(title: "New Shape", target: nil, action: nil)
        self.b1.attributedTitle = NSAttributedString(string: self.b1.title, attributes: foregroundColorAttributes)
        self.b3 = NSButton(title: "Append Point", target: nil, action: nil)
        self.b3.attributedTitle = NSAttributedString(string: self.b3.title, attributes: foregroundColorAttributes)
        self.b4 = NSButton(title: "Delete Point", target: nil, action: nil)
        self.b4.attributedTitle = NSAttributedString(string: self.b4.title, attributes: foregroundColorAttributes)
        self.b2 = NSButton(title: "Cycle Shape Color", target: nil, action: nil)
        self.b2.attributedTitle = NSAttributedString(string: self.b2.title, attributes: foregroundColorAttributes)
        self.b5 = NSButton(title: "Cycle Point Round", target: nil, action: nil)
        self.b5.attributedTitle = NSAttributedString(string: self.b5.title, attributes: foregroundColorAttributes)
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
            
            //b1.alphaValue = 0.95
            //b2.alphaValue = 0.95
            //b3.alphaValue = 0.95
            //b4.alphaValue = 0.95
            //b5.alphaValue = 0.95
            
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
    
    @objc func causalTreeDidUpdate(sender: NSObject?)
    {
        timeMe({
            try! self.model.validate()
        }, "Upper Layer Validation")
        
        // let go of remotely deleted points
        if let sel = self.selection
        {
            let point = self.model.point(forPermPoint: sel)
            let selectedPointValid = self.model.pointIsValid(point)
            
            if !selectedPointValid
            {
                self.selection = nil
            }
        }
        
        reloadData()
    }
    
    func updateRevision(_ revision: Weft<CausalTreeStandardUUIDT>?)
    {
        self.selection = nil //permanent ids do not apply across revisions
        self.model.revision = revision
        
        reloadData()
    }
    
    /// **Complexity:** O(weave)
    func reloadData()
    {
        updateUi: do
        {
            b1.isEnabled = true
            b2.isEnabled = (model.shapesCount() > 0 && selection != nil)
            b3.isEnabled = (model.shapesCount() > 0 && selection != nil)
            b4.isEnabled = (model.shapesCount() > 0 && selection != nil)
            b5.isEnabled = (model.shapesCount() > 0 && selection != nil)
            
            b1.isEnabled = (b1.isEnabled && model.revision == nil)
            b2.isEnabled = (b2.isEnabled && model.revision == nil)
            b3.isEnabled = (b3.isEnabled && model.revision == nil)
            b4.isEnabled = (b4.isEnabled && model.revision == nil)
            b5.isEnabled = (b5.isEnabled && model.revision == nil)
            
            if let sel = selectionIndex
            {
                if model.isLastPoint(sel)
                {
                    self.b3.title = "Append Point"
                    self.b3.attributedTitle = NSAttributedString(string: self.b3.title, attributes: foregroundColorAttributes)
                }
                else
                {
                    self.b3.title = "Insert Point"
                    self.b3.attributedTitle = NSAttributedString(string: self.b3.title, attributes: foregroundColorAttributes)
                }
            }
        }
        
        self.setNeedsDisplay(self.bounds)
    }
    
    ////////////////////
    // MARK: - Drawing -
    ////////////////////
    
    /// **Complexity:** O(weave)
    override func draw(_ dirtyRect: NSRect)
    {
        let selectionShape: CausalTreeBezierWrapper.TempShapeId?
        let selIndex = selectionIndex
        if let sel = selIndex
        {
            selectionShape = model.shape(forPoint: sel)
        }
        else
        {
            selectionShape = nil
        }
        
        func sp(_ s: CausalTreeBezierWrapper.TempShapeId, _ p: CausalTreeBezierWrapper.TempPointId, pointValue: NSPoint, firstPointInShape: CausalTreeBezierWrapper.TempPointId) -> NSPoint
        {
            guard let m = mouse, let sel = selIndex else
            {
                return pointValue
            }
            
            // visualize a) point translation, b) shape translation operation before committing
            if selectionShape == s && (sel == firstPointInShape || sel == p)
            {
                return NSMakePoint(pointValue.x + m.delta.x, pointValue.y + m.delta.y)
            }
            else
            {
                return pointValue
            }
        }
        
        let shapes = model.shapes()
        
        for s in shapes
        {
            let pts = model.shapeData(s: s).filter { !$0.deleted }
            
            drawShape: do
            {
                if pts.count <= 1
                {
                    break drawShape
                }
                
                let path = NSBezierPath()
                
                for (i,pd) in pts.enumerated()
                {
                    let p = pd.range.lowerBound
                    let pv = model.rawValueForPoint(pd.range.lowerBound).applying(pd.transform)
                    
                    let shiftedPoint = sp(s,p, pointValue:pv, firstPointInShape: pts[0].range.lowerBound)
                    
                    let prePointData = pts[pts.index(pts.startIndex, offsetBy: ((Int(i - 1) % pts.count) + pts.count) % pts.count)]
                    let postPointData = pts[pts.index(pts.startIndex, offsetBy: ((Int(i + 1) % pts.count) + pts.count) % pts.count)]
                    let prev = model.rawValueForPoint(prePointData.range.lowerBound).applying(prePointData.transform)
                    let postv = model.rawValueForPoint(postPointData.range.lowerBound).applying(postPointData.transform)
                    let midPrePoint = NSPoint((Vector2(sp(s, prePointData.range.lowerBound, pointValue: prev, firstPointInShape: pts[0].range.lowerBound)) + Vector2(shiftedPoint)) / 2)
                    let midPostPoint = NSPoint((Vector2(sp(s, postPointData.range.lowerBound, pointValue: postv, firstPointInShape: pts[0].range.lowerBound)) + Vector2(shiftedPoint)) / 2)
                    
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
                path.lineJoinStyle = .round
                path.close()
                
                path.stroke()
                path.fill()
                
                //drawGreenLine: do
                //{
                //    break drawGreenLine
                //    let theFirstPoint = sp(s, model.firstPoint(inShape: s)!)
                //    let theLastPoint = sp(s, model.lastPoint(inShape: s)!)
                //
                //    let line = NSBezierPath()
                //    line.move(to: theLastPoint)
                //    line.line(to: theFirstPoint)
                //
                //    NSColor.green.setStroke()
                //    line.lineWidth = 1.5
                //
                //    line.stroke()
                //}
            }
            
            drawPoints: do
            {
                for pd in pts
                {
                    let i = pd.range.lowerBound
                    let iv = model.rawValueForPoint(pd.range.lowerBound).applying(pd.transform)
                    
                    let shiftedPoint = sp(s,i, pointValue: iv, firstPointInShape: pts[0].range.lowerBound)
                    
                    let radius: CGFloat = 3
                    let point = NSBezierPath(ovalIn: NSMakeRect(shiftedPoint.x-radius, shiftedPoint.y-radius, radius*2, radius*2))

                    (i == pts.first!.range.lowerBound ?
                        NSColor.green : (i == pts.last!.range.lowerBound ?
                            NSColor.red : (selectionShape == s && selIndex == i ?
                                NSColor.black.withAlphaComponent(1) : NSColor.black.withAlphaComponent(0.5)))).setFill()
                    
                    point.fill()

                    if selectionShape == s && selIndex == i
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
    
    /// **Complexity:** O(weave)
    override func mouseDown(with event: NSEvent)
    {
        if model.revision != nil { return }
        
        let m = self.convert(event.locationInWindow, from: nil)
        
        var select: CausalTreeBezierWrapper.TempPointId? = nil
        
        findSelection: do
        {
            let shapes = model.shapes()
            
            for s in shapes
            {
                let pts = model.shapeData(s: s).filter { !$0.deleted }
                
                for pd in pts
                {
                    let val = model.rawValueForPoint(pd.range.lowerBound).applying(pd.transform)
                    
                    if sqrt(pow(val.x - m.x, 2) + pow(val.y - m.y, 2)) < selectionRadius
                    {
                        select = pd.range.lowerBound
                        break findSelection
                    }
                }
            }
        }
        
        mouse = (m, NSPoint.zero)
        selection = (select != nil ?model.permPoint(forPoint: select!) : nil)
    }
    
    override func mouseDragged(with event: NSEvent)
    {
        guard let m = mouse else { return }
        
        let newM = self.convert(event.locationInWindow, from: nil)
        
        mouse = (m.start, NSMakePoint(newM.x - m.start.x, newM.y - m.start.y))
    }

    /// **Complexity:** O(weave)
    override func mouseUp(with event: NSEvent)
    {
        commitSelections: if let sel = selectionIndex, let m = mouse, m.delta != NSPoint.zero
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
        
        self.listener?.causalTreeDidUpdate?(sender: self)
        reloadData()
    }
    
    ////////////////////
    // MARK: - Buttons -
    ////////////////////
    
    /// **Complexity:** O(weave)
    @objc func newShape()
    {
        let randX = (CGFloat(arc4random_uniform(1001))/CGFloat(1000)) * drawBounds.width
        let randY = (CGFloat(arc4random_uniform(1001))/CGFloat(1000) * drawBounds.height)
        
        let newShapePoint = model.addShape(atX: randX, y: randY)
        self.selection = model.permPoint(forPoint: newShapePoint)
        
        model.updateAttributes(color: randomColor(), forShape: model.shapeForPoint(newShapePoint))
        
        self.listener?.causalTreeDidUpdate?(sender: self)
        self.reloadData()
    }
    
    /// **Complexity:** O(weave)
    @objc func addPoint()
    {
        guard let p = selectionIndex else { return }
        
        let sel = model.addShapePoint(afterPoint: p, withBounds: drawBounds)
        self.selection = model.permPoint(forPoint: sel)
        
        self.listener?.causalTreeDidUpdate?(sender: self)
        self.reloadData()
    }
    
    /// **Complexity:** O(weave)
    @objc func deletePoint()
    {
        guard let p = selectionIndex else { return }
        
        let prevPoint = model.nextValidPoint(beforePoint: p)
        self.selection = (prevPoint != nil && prevPoint != p ? model.permPoint(forPoint: prevPoint!) : nil)
        
        model.deleteShapePoint(p)
        
        self.listener?.causalTreeDidUpdate?(sender: self)
        self.reloadData()
    }
    
    /// **Complexity:** O(weave)
    @objc func cycleShapeColor()
    {
        guard let sel = selectionIndex else { return }
        
        let shape = model.shape(forPoint: sel)
        
        let color = randomColor()
        model.updateAttributes(color: color, forShape: shape)
        
        self.listener?.causalTreeDidUpdate?(sender: self)
        reloadData()
    }
    
    /// **Complexity:** O(weave)
    @objc func cyclePointRoundness()
    {
        guard let sel = selectionIndex else { return }
        
        let rounded = !model.attributes(forPoint: sel)
        model.updateAttributes(rounded: rounded, forPoint: sel)
        
        self.listener?.causalTreeDidUpdate?(sender: self)
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
