//
//  CausalTreeDrawEditingView.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-20.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

// PERF: most of the algorithms in here are O(N) inefficient, to say nothing of the underlying CRDT perf

/* How do we move an entire shape? Three possible ways:
     > move each individual point
     > add a "move" operation
     > implicitly, by moving the first point
 Moving each individual point is bad, b/c if another peer adds points then they won't get moved. So the choice is
 between an implicit operation and an explicit operation. Text editing works via implicit operations, i.e. every
 new character, instead of overwriting the previous character, implicitly shifts over every successive character.
 Here, for the sake of completeness, let's use operations. */

import AppKit

enum Operation: Hashable
{
    var hashValue: Int
    {
        switch self
        {
        case .translate(let delta):
            return 0 ^ delta.x.hashValue ^ delta.y.hashValue
        }
    }
    
    static func ==(lhs: Operation, rhs: Operation) -> Bool
    {
        switch lhs
        {
        case .translate(let d1):
            switch rhs
            {
            case .translate(let d2):
                return d1 == d2
            }
        }
    }
    
    case translate(delta: NSPoint)
}

//////////////////
// MARK: - Model -
//////////////////

// this is where the CT structure is mapped to our local model
class CausalTreeBezierLayer
{
    private unowned var crdt: CausalTreeBezierT
    
    // TODO: replace with CRDT
    var shapes: [[NSPoint]] = []
    var shapeAttributes: [(NSColor)] = [] //color
    var pointAttributes: [[(Bool)]] = [] //roundness
    var shapeOperations: [[Operation]] = [] //translation
    
    init(crdt: CausalTreeBezierT) {
        self.crdt = crdt
    }
    
    func totalPointsCount() -> Int
    {
        return shapes.reduce(0, { (r,s) in r+s.count })
    }
    
    func shapesCount() -> Int
    {
        return shapes.count
    }
    
    func shapeCount(_ s: Int, withInvalid: Bool = false) -> Int
    {
        if withInvalid
        {
            return shapes[s].count
        }
        else
        {
            var t = 0
            for i in 0..<shapes[s].count
            {
                if pointIsValid(i, forShape: s)
                {
                    t += 1
                }
            }
            return t
        }
    }
    
    func pointValue(_ p: Int, forShape s: Int) -> NSPoint?
    {
        if pointIsValid(p, forShape: s)
        {
            let t = transform(forOperations: operations(forShape: s))
            return shapes[s][p].applying(t)
        }
        else
        {
            return nil
        }
    }
    
    func pointIsValid(_ p: Int, forShape s: Int) -> Bool
    {
        return !shapes[s][p].x.isNaN && !shapes[s][p].y.isNaN
    }
    
    func nextValidPoint(afterPoint p: Int, forShape s: Int, looping: Bool = true) -> Int?
    {
        let fullShapeCount = shapeCount(s, withInvalid: true)
        
        for i0 in 0..<fullShapeCount
        {
            var i = p + 1 + i0
            
            if !looping && i >= fullShapeCount
            {
                return nil
            }
            
            i = (((i % fullShapeCount) + fullShapeCount) % fullShapeCount)
            
            if pointIsValid(i, forShape: s)
            {
                return i
            }
        }
        
        return nil
    }
    
    func nextValidPoint(beforePoint p: Int, forShape s: Int, looping: Bool = true) -> Int?
    {
        let fullShapeCount = shapeCount(s, withInvalid: true)
        
        for i0 in 0..<fullShapeCount
        {
            var i = p - 1 - i0
            
            if !looping && i < 0
            {
                return nil
            }
            
            i = (((i % fullShapeCount) + fullShapeCount) % fullShapeCount)
            
            if pointIsValid(i, forShape: s)
            {
                return i
            }
        }
        
        return nil
    }
    
    func isFirstPoint(_ p: Int, inShape s: Int) -> Bool
    {
        return nextValidPoint(beforePoint: p, forShape: s, looping: false) == nil
    }
    
    func isLastPoint(_ p: Int, inShape s: Int) -> Bool
    {
        return nextValidPoint(afterPoint: p, forShape: s, looping: false) == nil
    }
    
    func firstPoint(inShape s: Int) -> Int?
    {
        for i in 0..<shapes[s].count
        {
            if pointIsValid(i, forShape: s)
            {
                return i
            }
        }
        
        return nil
    }
    
    func lastPoint(inShape s: Int) -> Int?
    {
        for i in (0..<shapes[s].count).reversed()
        {
            if pointIsValid(i, forShape: s)
            {
                return i
            }
        }
        
        return nil
    }
    
    func points(forShape s: Int) -> AnyCollection<Int>
    {
        // PERF: I'm not sure to what extent lazy works in this stack, but whatever
        let countArray = Array<Int>(0..<shapes[s].count).lazy
        let filteredArray = countArray.filter { i in self.pointIsValid(i, forShape: s) }
        let lazyArray = filteredArray.lazy
        
        return AnyCollection(lazyArray)
    }
    
    func addShape(atX x: CGFloat, y: CGFloat) -> Int
    {
        let randX = x
        let randY = y
        
        shapes.append([NSMakePoint(randX, randY)])
        shapeAttributes.append((randomColor()))
        pointAttributes.append([arc4random_uniform(2) == 0])
        shapeOperations.append([])
        assert(shapes.count == shapeAttributes.count)
        assert(shapes.count == pointAttributes.count)
        assert(shapes.count == shapeOperations.count)
        
        return shapes.count - 1
    }
    
    func updateShapePoint(_ p: Int, inShape s: Int, withDelta delta: NSPoint)
    {
        let value = NSMakePoint(shapes[s][p].x + delta.x, shapes[s][p].y + delta.y)
        
        updateShapePoint(p, inShape: s, withValue: value)
    }
    
    func updateShapePoints(_ points: CountableClosedRange<Int>, inShape s: Int, withDelta delta: NSPoint)
    {
        for p in points
        {
            updateShapePoint(p, inShape: s, withDelta: delta)
        }
    }
    
    private func updateShapePoint(_ p: Int, inShape: Int, withValue: NSPoint)
    {
        shapes[inShape][p] = withValue
    }
    
    func addShapePoint(toShape: Int, afterPoint: Int, withBounds bounds: NSRect? = nil) -> (Int, Int)
    {
        assert(pointIsValid(afterPoint, forShape: toShape))
        
        let minLength: Scalar = 10
        let maxLength: Scalar = 30
        let maxCCAngle: Scalar = 70
        let maxCAngle: Scalar = 20
        let offset: CGFloat = 4
        
        let shapeIndex = toShape
        let pointIndex = afterPoint
        
        let point = shapes[shapeIndex][pointIndex]
        assert(pointIsValid(pointIndex, forShape: shapeIndex))
        let length = minLength + Scalar(arc4random_uniform(UInt32(maxLength - minLength)))
        
        let previousPointIndex = nextValidPoint(beforePoint: pointIndex, forShape: shapeIndex)
        let nextPointIndex = nextValidPoint(afterPoint: pointIndex, forShape: shapeIndex, looping: false)
        
        let pointIsOnlyPoint = shapeCount(toShape) == 1
        let pointIsEndPoint = isLastPoint(afterPoint, inShape: toShape)
        let pointIsInsertion = !pointIsOnlyPoint && !pointIsEndPoint
        
        var newPoint: NSPoint
        
        addNewPoint: do
        {
            let angle: Scalar
            var vec: Vector2
            
            if pointIsOnlyPoint
            {
                let fakePreviousPoint: NSPoint = NSMakePoint(point.x - CGFloat(length), point.y)
                angle = Scalar(arc4random_uniform(360))
                vec = Vector2(point) - Vector2(fakePreviousPoint)
            }
            else if pointIsEndPoint
            {
                let previousPoint = shapes[shapeIndex][previousPointIndex!]
                angle = -maxCAngle + Scalar(arc4random_uniform(UInt32(maxCAngle + maxCCAngle)))
                vec = Vector2(point) - Vector2(previousPoint)
            }
            else
            {
                let nextPoint = shapes[shapeIndex][nextPointIndex!]
                angle = -maxCAngle + Scalar(arc4random_uniform(UInt32(maxCAngle + maxCCAngle)))
                vec = Vector2(nextPoint) - Vector2(point)
            }
            
            vec = vec.normalized() * length
            vec = vec.rotated(by: angle * ((2*Scalar.pi)/360))
            
            let tempNewPoint = NSMakePoint(point.x + CGFloat(vec.x), point.y + CGFloat(vec.y))
            if let b = bounds
            {
                let t = transform(forOperations: operations(forShape: shapeIndex)).inverted()
                let tBounds = b.applying(t)
                
                newPoint = NSMakePoint(min(max(tempNewPoint.x, tBounds.minX + offset), tBounds.maxX - offset),
                                       min(max(tempNewPoint.y, tBounds.minY + offset), tBounds.maxY - offset))
            }
            else
            {
                newPoint = tempNewPoint
            }
        }
        
        mutate: do
        {
            if pointIsInsertion
            {
                let nextPoint = shapes[shapeIndex][nextPointIndex!]
                
                //a dot normalized b
                let vOld = Vector2(nextPoint) - Vector2(point)
                let vNew = Vector2(newPoint) - Vector2(point)
                let vProj = (vOld.normalized() * vNew.dot(vOld.normalized()))
                
                let lastIndex = lastPoint(inShape: shapeIndex)!
                
                // TODO: sentinel
                updateShapePoints(nextPointIndex!...lastIndex, inShape: shapeIndex, withDelta: NSPoint(vProj))
            }
            
            shapes[shapeIndex].insert(newPoint, at: pointIndex + 1)
            pointAttributes[shapeIndex].insert(arc4random_uniform(2) == 0, at: pointIndex + 1)
        }
        
        return (shapeIndex, pointIndex + 1)
    }
    
    func deleteShapePoint(_ p: Int, fromShape s: Int) -> (Int,Int)?
    {
        updateShapePoint(p, inShape: s, withValue: NSMakePoint(CGFloat.nan, CGFloat.nan))
        
        if let prevPoint = nextValidPoint(beforePoint: p, forShape: s)
        {
            return (s,prevPoint)
        }
        else
        {
            return nil
        }
    }
    
    func attributes(forShape s: Int) -> (NSColor)
    {
        return shapeAttributes[s]
    }
    
    func attributes(forPoint p: Int, inShape s: Int) -> (Bool)
    {
        return pointAttributes[s][p]
    }
    
    func operations(forShape s: Int) -> [Operation]
    {
        return shapeOperations[s]
    }
    
    func transform(forOperations ops: [Operation]) -> CGAffineTransform
    {
        var transform = CGAffineTransform.identity
        for o in ops
        {
            switch o
            {
            case .translate(let delta):
                transform = transform.concatenating(CGAffineTransform(translationX: delta.x, y: delta.y))
            }
        }
        return transform
    }
    
    func updateAttributes(color: NSColor, forShape s: Int)
    {
        shapeAttributes[s] = (color)
    }
    
    func updateAttributes(rounded: Bool, forPoint p: Int, inShape s: Int)
    {
        pointAttributes[s][p] = (rounded)
    }
    
    func addOperation(_ o: Operation, toShape s: Int)
    {
        if shapeOperations[s].isEmpty
        {
            shapeOperations[s].append(o)
        }
        else
        {
            let lastOperation = shapeOperations[s].last!
            
            switch o
            {
            case .translate(let d1):
                switch lastOperation
                {
                case .translate(let d2):
                    // consolidate adjascent translations
                    shapeOperations[s][shapeOperations[s].count - 1] = .translate(delta: NSMakePoint(d1.x + d2.x, d1.y + d2.y))
                }
            }
        }
    }
}

/////////////////
// MARK: - View -
/////////////////

class CausalTreeDrawEditingView: NSView
{
    var buttonStack: NSStackView
    var b1: NSButton
    var b2: NSButton
    var b3: NSButton
    var b4: NSButton
    var b5: NSButton
    
    var drawBounds: NSRect { return self.bounds }
    
    let selectionRadius: CGFloat = 10
    var selection: (Int,Int)? = nil
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
    
    var model: CausalTreeBezierLayer
    
    //////////////////////
    // MARK: - Lifecycle -
    //////////////////////
    
    required init(frame frameRect: NSRect, crdt: CausalTreeBezierT)
    {
        self.model = CausalTreeBezierLayer(crdt: crdt)
        
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
                if model.isLastPoint(sel.1, inShape: sel.0)
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
        func sp(_ s: Int, _ p: Int) -> NSPoint
        {
            let point = model.pointValue(p, forShape: s)!
            
            guard let m = mouse, let sel = selection else
            {
                return point
            }
            
            // visualize a) point translation, b) shape translation operation before committing
            if sel.0 == s && (sel.1 == model.firstPoint(inShape: s) || sel.1 == p)
            {
                return NSMakePoint(point.x + m.delta.x, point.y + m.delta.y)
            }
            else
            {
                return point
            }
        }
        
        for s in 0..<model.shapesCount()
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
                    
                    if model.attributes(forPoint: p, inShape: s)
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

                    (model.isFirstPoint(i, inShape: s) ?
                        NSColor.green : (model.isLastPoint(i, inShape: s) ?
                            NSColor.red : (selection?.0 == s && selection?.1 == i ?
                                NSColor.black.withAlphaComponent(1) : NSColor.black.withAlphaComponent(0.5)))).setFill()
                    
                    point.fill()

                    if selection?.0 == s && selection?.1 == i
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
    
    override func mouseDown(with event: NSEvent) {
        let m = self.convert(event.locationInWindow, from: nil)
        
        var select: (Int, Int)? = nil
        
        findSelection: for s in 0..<model.shapesCount()
        {
            let pts = model.points(forShape: s)
            
            for p in pts
            {
                guard let val = model.pointValue(p, forShape: s) else
                {
                    continue
                }
                
                if sqrt(pow(val.x - m.x, 2) + pow(val.y - m.y, 2)) < selectionRadius
                {
                    select = (s,p)
                    break findSelection
                }
            }
        }
        
        mouse = (m, NSPoint.zero)
        selection = select
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let m = mouse else { return }
        
        let newM = self.convert(event.locationInWindow, from: nil)
        
        mouse = (m.start, NSMakePoint(newM.x - m.start.x, newM.y - m.start.y))
    }

    override func mouseUp(with event: NSEvent) {
        commitSelections: if let sel = selection, let m = mouse
        {
            if model.isFirstPoint(sel.1, inShape: sel.0)
            {
                model.addOperation(.translate(delta: m.delta), toShape: sel.0)
            }
            else
            {
                model.updateShapePoint(sel.1, inShape: sel.0, withDelta: m.delta)
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
        
        self.selection = (newShape, 0)
        
        self.reloadData()
    }
    
    @objc func addPoint()
    {
        guard let p = selection else { return }
        
        let sel = model.addShapePoint(toShape: p.0, afterPoint: p.1, withBounds: drawBounds)
        
        self.selection = sel
        self.reloadData()
    }
    
    @objc func deletePoint()
    {
        guard let p = selection else { return }
        
        let sel = model.deleteShapePoint(p.1, fromShape: p.0)
        
        self.selection = sel
        self.reloadData()
    }
    
    @objc func cycleShapeColor()
    {
        guard let sel = selection else
        {
            return
        }
        
        let color = randomColor()
        model.updateAttributes(color: color, forShape: sel.0)
        
        reloadData()
    }
    
    @objc func cyclePointRoundness()
    {
        guard let sel = selection else
        {
            return
        }
        
        let rounded = !model.attributes(forPoint: sel.1, inShape: sel.0)
        model.updateAttributes(rounded: rounded, forPoint: sel.1, inShape: sel.0)
        
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
