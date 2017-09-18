//
//  CausalTreeDisplayViewController.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-8-28.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

/* Causal tree visualizer. Pretty much as shown in the paper: a stack of yarns along with arrows
 connecting child atoms to their parents. Left click and hold to pan, right click to select atoms,
 middle click to append atoms. Can additionally display awarenses -- triggered by control VC. */

// TODO: delegate instead of crdt copy, like control VC?

import Cocoa

protocol CausalTreeDisplayViewControllerDelegate: class
{
    func crdtCopy(forCausalTreeDisplayViewController: CausalTreeDisplayViewController) -> CausalTreeT
    func didSelectAtom(_ atom: AtomId?, withButton: Int, inCausalTreeDisplayViewController: CausalTreeDisplayViewController)
}

class CausalTreeDisplayViewController: NSViewController, CausalTreeDrawingViewDelegate
{
    weak var delegate: CausalTreeDisplayViewControllerDelegate?
    {
        didSet
        {
            reloadData()
        }
    }
    
    var crdtCopy: CausalTreeT?
    var weaveDrawingView: CausalTreeDrawingView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let view = CausalTreeDrawingView(frame: self.view.bounds)
        view.delegate = self
        self.view.addSubview(view)
        view.autoresizingMask = [.width, .height]
        weaveDrawingView = view
        
        self.view.wantsLayer = true
        //self.view.layer!.drawsAsynchronously = true
        //self.view.canDrawConcurrently = true
        //view.canDrawConcurrently = true
    }
    
    func reloadData()
    {
        self.weaveDrawingView.setNeedsDisplay(self.weaveDrawingView.bounds)
    }
    
    func drawSelection(forAtom atom: AtomId?)
    {
        self.weaveDrawingView.selection = atom
    }
    
    func drawAwareness(forAtom atom: AtomId?)
    {
        self.weaveDrawingView.awareness = atom
    }
    
    override func mouseUp(with event: NSEvent) {
        weaveDrawingView.click(event.locationInWindow, 0)
    }
    override func rightMouseUp(with event: NSEvent) {
        weaveDrawingView.click(event.locationInWindow, 1)
    }
    override func otherMouseUp(with event: NSEvent) {
        weaveDrawingView.click(event.locationInWindow, 2)
    }
    
    override func mouseDragged(with event: NSEvent) {
        let xScalar: CGFloat = 5
        let yScalar: CGFloat = 1
        weaveDrawingView.offset = NSMakePoint(weaveDrawingView.offset.x + event.deltaX * xScalar,
                                              weaveDrawingView.offset.y - event.deltaY * yScalar)
    }
    
    func beginDraw(forView: CausalTreeDrawingView)
    {
        guard let delegate = self.delegate else { return }
        timeMe({
            self.crdtCopy = delegate.crdtCopy(forCausalTreeDisplayViewController: self)
        }, "WeaveCopy", every: 25)
    }
    
    func endDraw(forView: CausalTreeDrawingView)
    {
        self.crdtCopy = nil
    }
    
    func didSelectAtom(_ atom: AtomId?, withButton button: Int, forView: CausalTreeDrawingView)
    {
        // this is called from draw, so delay until next run loop iteration
        Timer.scheduledTimer(withTimeInterval: 0, repeats: false) { t in
            self.delegate?.didSelectAtom(atom, withButton: button, inCausalTreeDisplayViewController: self)
        }
    }
    
    func sites(forView: CausalTreeDrawingView) -> [SiteId] {
        guard let weave = crdtCopy else { assert(false); return []; }
        let sites = [SiteId](weave.weave.completeWeft().mapping.keys).sorted()
        return sites
    }
    
    func yarn(withSite site: SiteId, forView: CausalTreeDrawingView) -> ArraySlice<CausalTreeT.WeaveT.Atom> {
        guard let weave = crdtCopy else { assert(false); return ArraySlice<CausalTreeT.WeaveT.Atom>(); }
        return weave.weave.yarn(forSite: site)
    }
    
    func awareness(forAtom atom: AtomId) -> Weft? {
        guard let weave = crdtCopy else { assert(false); return nil; }
        var weft: Weft? = nil
        timeMe({
            weft = weave.weave.awarenessWeft(forAtom: atom)
        }, "AwarenessWeft")
        
        return weft
    }
}

protocol CausalTreeDrawingViewDelegate: class {
    func didSelectAtom(_ atom: AtomId?, withButton: Int, forView: CausalTreeDrawingView)
    func sites(forView: CausalTreeDrawingView) -> [SiteId]
    func yarn(withSite site: SiteId, forView: CausalTreeDrawingView) -> ArraySlice<CausalTreeT.WeaveT.Atom>
    func awareness(forAtom atom: AtomId) -> Weft?
    func beginDraw(forView: CausalTreeDrawingView)
    func endDraw(forView: CausalTreeDrawingView)
}

class CausalTreeDrawingView: NSView, CALayerDelegate {
    weak var delegate: CausalTreeDrawingViewDelegate?
    
    //would be much better as a scroll view, but not worth the effort, really
    private var _offset: NSPoint = NSMakePoint(0, 0)
    var offset: NSPoint {
        get {
            return _offset
        }
        set {
            _offset = newValue
            setNeedsDisplay(self.bounds)
        }
    }
    
    private var _enqueuedClick: (NSPoint,Int)? = nil
    func click(_ position: NSPoint, _ button: Int) {
        _enqueuedClick = (position,button)
        setNeedsDisplay(self.bounds)
    }
    
    var selection: AtomId?
    {
        didSet
        {
            setNeedsDisplay(self.bounds)
        }
    }
    var awareness: AtomId?
    {
        didSet
        {
            setNeedsDisplay(self.bounds)
        }
    }
    
    private var selectedAtom: AtomId?
    {
        didSet
        {
            if selectedAtom == nil
            {
                awareness = nil
            }
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .duringViewResize
        self.layer!.drawsAsynchronously = true
        //self.layer?.shouldRasterize = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func makeBackingLayer() -> CALayer {
        let tiledLayer = CALayer()
        tiledLayer.delegate = self
        return tiledLayer
    }
    
    var colors: [NSColor] = { ()->[NSColor] in
        var colors = [NSColor.red, NSColor.blue, NSColor.green, NSColor.purple, NSColor.magenta, NSColor.brown, NSColor.cyan]
        for i in 0..<colors.count {
            let j = Int(arc4random_uniform(UInt32(colors.count)))
            let t = colors[j]
            colors[j] = colors[i]
            colors[i] = t
        }
        return colors
    }()
    
    // can't have this if using updateLayer
    var lastClock = CACurrentMediaTime()
    var fps: CFTimeInterval = 0
    //override func updateLayer() {
    //override func draw(_ dirtyRect: NSRect) {
    func draw(_ layer: CALayer, in ctx: CGContext) {
        let clock = CACurrentMediaTime()
        let ratio: CFTimeInterval = 0.05
        fps = fps * (1 - ratio) + (1/(clock - lastClock)) * ratio
        //print("fps: \(fps) (main thread \(Thread.isMainThread)), \(layer.drawsAsynchronously)")
        lastClock = clock
        
        guard let delegate = self.delegate else {
            return
        }
        
        delegate.beginDraw(forView: self)
        defer { delegate.endDraw(forView: self) }
        
        NSGraphicsContext.saveGraphicsState()
        let gctx = NSGraphicsContext.init(cgContext: ctx, flipped: false)
        NSGraphicsContext.current = gctx
        
        // warning: in async, might cause occasional wonkiness
        let bounds = self.bounds
        
        // color background
        NSColor(white: 0.98, alpha: 1).setFill()
        NSBezierPath(rect: bounds).fill()
        
        let translation = CGAffineTransform.init(translationX: offset.x, y: offset.y).inverted()
        ctx.translateBy(x: offset.x, y: offset.y)
        
        let atomRadius: CGFloat = 10
        let atomGap: CGFloat = 20
        let yarnGap: CGFloat = 40
        let connectorThickness: CGFloat = 2
        let disabledColor: NSColor = NSColor(white: 0.9, alpha: 1)
        
        let sites = delegate.sites(forView: self)
        let yarns = sites.count
        
        // position functions
        func atomCenter(row: Int, column: Int) -> NSPoint {
            let x = (atomGap/2 + atomRadius*2 + atomGap/2) * CGFloat(column) + (atomGap/2 + atomRadius)
            let y = bounds.size.height - ((yarnGap/2 + atomRadius*2 + atomGap/2) * CGFloat(row) + (yarnGap/2 + atomRadius))
            
            return NSMakePoint(x, y)
        }
        func atomSiteCenter(site: SiteId, index: CausalTreeT.WeaveT.YarnIndex) -> NSPoint? {
            return atomCenter(row: Int(site), column: Int(index))
        }
        
        // drawing functions
        func drawArrow(from p0: NSPoint, to p1: NSPoint, color: NSColor) {
            let angle = 30 * (2 * CGFloat.pi)/360
            let peak = atomRadius * 0.8
            let xOffset = atomRadius * 0.5
            let yOffset = atomRadius * 0.5
            let arrowLength = atomRadius * 0.6
            let arrowAngle = 20 * (2 * CGFloat.pi)/360
            
            let path = NSBezierPath()
            let arrowSegmentStart: NSPoint
            let arrowSegmentEnd: NSPoint
            
            // easy case: atoms close together
            //if p0.y == p1.y || (abs(p0.x - p1.x) <= (atomRadius * 2 + atomGap)) {
            do {
                // initial point calculations
                let v0_0 = Vector2(p0)
                let v1_0 = Vector2(p1)
                let v_m_0 = (v0_0 + v1_0) / 2
                let v_perp = (v_m_0 - v0_0).rotated(by: -Scalar.pi/2).normalized()
                let v0_parl = (v_m_0 - v0_0).normalized()
                let v1_parl = (v_m_0 - v1_0).normalized()
                
                // shifted vertices
                let v_0 = v0_0 + v_perp * Scalar(yOffset) + v0_parl * Scalar(xOffset)
                let v_1 = v1_0 + v_perp * Scalar(yOffset) + v1_parl * Scalar(xOffset)
                let v_m = (v_0 + v_1) / 2
                
                // high point
                let d = CGFloat((v_1 - v_0).length)
                let h = Scalar(tan(angle) * (d/2))
                let v_h = v_perp * h + v_m
                
                // bezier control points
                let p = min(h, Scalar(peak))
                let l = (h - p) / Scalar(cos(CGFloat.pi - CGFloat.pi/2 - angle))
                let v_p = v_perp * p + v_m
                let b_0 = v_0 + (v_h - v_0).normalized() * max((v_h - v_0).length - l, 0)
                let b_1 = v_1 + (v_h - v_1).normalized() * max((v_h - v_1).length - l, 0)
                
                // arrowhead estimation
                let approxLength = (b_0 - v_0).length + (b_1 - b_0).length + (b_1 - b_1).length
                let halfArrowRatio = Scalar(arrowLength) / (approxLength / 2)
                arrowSegmentStart = NSPoint(b_1 + (b_0 - b_1).normalized() * ((b_0 - b_1).length / 2) * halfArrowRatio)
                arrowSegmentEnd = NSPoint(v_1)
                
                path.move(to: NSPoint(v_0))
                path.curve(to: NSPoint(v_1), controlPoint1: NSPoint(b_0), controlPoint2: NSPoint(b_1))
                //path.line(to: NSPoint(b_0))
                //path.line(to: NSPoint(b_1))
                //path.line(to: NSPoint(b_0))
                //path.line(to: NSPoint(v_h))
                //path.line(to: NSPoint(v_1))
            }
            //// bendy verticals
            //else {
            //    path.move(to: p0)
            //    path.line(to: p1)
            //
            //    arrowSegmentStart = p0
            //    arrowSegmentEnd = p1
            //}
            
            color.setStroke()
            path.lineWidth = 1
            path.stroke()
            
            arrowhead: do {
                let side = arrowLength * tan(arrowAngle)
                
                let a_parl = (Vector2(arrowSegmentStart) - Vector2(arrowSegmentEnd)).normalized()
                let a_perp_l = a_parl.rotated(by: Scalar.pi/2).normalized()
                let a_perp_r = a_parl.rotated(by: -Scalar.pi/2).normalized()
                let a_0 = Vector2(arrowSegmentEnd)
                let a_1 = Vector2(arrowSegmentEnd) + a_parl * Scalar(arrowLength)
                let a_l = a_1 + a_perp_l * Scalar(side)
                let a_r = a_1 + a_perp_r * Scalar(side)
                
                path.removeAllPoints()
                path.move(to: NSPoint(a_0))
                path.line(to: NSPoint(a_l))
                path.line(to: NSPoint(a_r))
                path.close()
                color.setFill()
                path.fill()
            }
        }
        // TODO: move the rest of the drawing functions here
        
        // string construction caching
        let atomLabelParagraphStyle = NSMutableParagraphStyle()
        atomLabelParagraphStyle.alignment = .center
        let atomLabelFont = NSFont.systemFont(ofSize: 14, weight: NSFont.Weight.bold)
        let atomLabel: NSMutableString = ""
        
        // string construction caching
        let clockLabelParagraphStyle = NSMutableParagraphStyle()
        clockLabelParagraphStyle.alignment = .center
        let clockLabelFont = NSFont.systemFont(ofSize: 8, weight: NSFont.Weight.thin)
        let clockLabel: NSMutableString = ""
        
        var awarenessWeftToDraw: Weft?
        clickProcessing: do {
            if let click = _enqueuedClick {
                var quickAndDirtyHitTesting: [(circle:(c:NSPoint,r:CGFloat),atom:AtomId)] = []
                selectedAtom = nil
                for i in 0..<yarns {
                    let elements = delegate.yarn(withSite: sites[i], forView: self)
                    let elementRange = 0..<min(elements.count, elements.count)
                    for j in elementRange {
                        let index = elements.index(elements.startIndex, offsetBy: j)
                        // TODO: slow, but used here to ensure consistency
                        let p = atomSiteCenter(site: sites[i], index: elements[index].id.index)!
                        let ovalRect = NSMakeRect(p.x - atomRadius, p.y - atomRadius, atomRadius * 2, atomRadius * 2)
                        if !bounds.applying(translation).intersects(ovalRect) {
                            continue
                        }
                        quickAndDirtyHitTesting.append((circle: (c: NSMakePoint(ovalRect.midX, ovalRect.midY),
                                                                 r: ovalRect.size.width/2),
                                                        atom: elements[index].id))
                    }
                }
                for item in quickAndDirtyHitTesting {
                    let translatedClick = click.0.applying(translation)
                    let d = sqrt(pow(translatedClick.x - item.circle.c.x, 2) + pow(translatedClick.y - item.circle.c.y, 2))
                    if d <= item.circle.r {
                        selectedAtom = item.atom
                        break
                    }
                }
                self.delegate?.didSelectAtom(selectedAtom, withButton: click.1, forView: self)
            }
        }
        postClickProcessing: do {
            if let anAtom = self.awareness {
                let yarn = delegate.yarn(withSite: anAtom.site, forView: self)
                let atomIndex = anAtom.index
                let atom = yarn[yarn.startIndex + Int(atomIndex)]
                let awareness = delegate.awareness(forAtom: atom.id)!
                let sortedAwareness = awareness.mapping.sorted(by: { (a, b) -> Bool in a.key < b.key })
                awarenessWeftToDraw = awareness
                printAwareness: do {
                    break printAwareness
                    if _enqueuedClick != nil {
                        var string = "awareness: "
                        for m in sortedAwareness {
                            string += "\(m.key):\(m.value), "
                        }
                        print(string)
                    }
                }
            }
        }
        _enqueuedClick = nil
        
        for i in 0..<yarns {
            let color = colors[i % colors.count]
            
            let elements = delegate.yarn(withSite: sites[i], forView: self)
            let elementRange = 0..<min(elements.count, elements.count)
            
            drawConnectors: do {
                break drawConnectors //no connectors for now
                
                for j in elementRange {
                    let p = atomCenter(row: i, column: Int(j) - 1)
                    
                    let rect = NSMakeRect(p.x, p.y - connectorThickness/2, atomGap, connectorThickness)
                    if !bounds.applying(translation).intersects(rect) {
                        continue
                    }
                    
                    let connector = NSBezierPath()
                    connector.move(to: NSMakePoint(p.x + 2, p.y))
                    connector.line(to: NSMakePoint(p.x + (atomRadius + atomGap + atomRadius) - 2, p.y))
                    
                    color.setStroke()
                    connector.lineWidth = connectorThickness
                    connector.stroke()
                }
            }
            
            drawAtoms: do {
                //break drawAtoms
                
                for j in elementRange {
                    let index = elements.index(elements.startIndex, offsetBy: j)
                    
                    // TODO: slow, but used here to ensure consistency
                    let p = atomSiteCenter(site: sites[i], index: elements[index].id.index)!
                    
                    let ovalRect = NSMakeRect(p.x - atomRadius, p.y - atomRadius, atomRadius * 2, atomRadius * 2)
                    
                    if !bounds.applying(translation).intersects(ovalRect) {
                        continue
                    }
                    
                    let atom = NSBezierPath(ovalIn: ovalRect)
                    
                    if elements[index].id == self.selection
                    {
                        let offset: CGFloat = 4
                        let selectionCircle = NSBezierPath(ovalIn: NSMakeRect(ovalRect.origin.x - offset,
                                                                              ovalRect.origin.y - offset,
                                                                              ovalRect.size.width + offset * 2,
                                                                              ovalRect.size.height + offset * 2))
                        NSColor.blue.setFill()
                        NSColor.blue.setStroke()
                        selectionCircle.lineWidth = 2
                        //selectionCircle.fill()
                        selectionCircle.stroke()
                    }
                    
                    NSColor.white.setFill()
                    atom.fill()
                    color.setStroke()
                    if let awareness = awarenessWeftToDraw {
                        if let siteAwareness = awareness.mapping[SiteId(i)],
                            siteAwareness >= elements[index].id.index {
                        }
                        else {
                            disabledColor.setStroke()
                        }
                    }
                    atom.lineWidth = 1.5
                    atom.stroke()
                    
                    drawText: do {
                        //break drawText
                        
                        var atomLabelAttributes: [NSAttributedStringKey:AnyObject] = [NSAttributedStringKey.paragraphStyle:atomLabelParagraphStyle, NSAttributedStringKey.font:atomLabelFont]
                        var clockLabelAttributes: [NSAttributedStringKey:AnyObject] = [NSAttributedStringKey.paragraphStyle:clockLabelParagraphStyle, NSAttributedStringKey.font:clockLabelFont, NSAttributedStringKey.foregroundColor:NSColor.darkGray]
                        if let awareness = awarenessWeftToDraw {
                            if let siteAwareness = awareness.mapping[SiteId(i)],
                                siteAwareness >= elements[index].id.index {
                            }
                            else {
                                atomLabelAttributes[NSAttributedStringKey.foregroundColor] = disabledColor
                                clockLabelAttributes[NSAttributedStringKey.foregroundColor] = disabledColor
                            }
                        }
                        
                        switch elements[index].type
                        {
                        case .none:
                            atomLabel.replaceCharacters(in: NSMakeRange(0, atomLabel.length), with: elements[index].value.atomDescription)
                        case .start:
                            atomLabel.replaceCharacters(in: NSMakeRange(0, atomLabel.length), with: "𝒷")
                        case .end:
                            atomLabel.replaceCharacters(in: NSMakeRange(0, atomLabel.length), with: "ℯ")
                        case .commit:
                            atomLabel.replaceCharacters(in: NSMakeRange(0, atomLabel.length), with: "⍉")
                        case .delete:
                            atomLabel.replaceCharacters(in: NSMakeRange(0, atomLabel.length), with: "⨂")
                        }
                        
                        let labelRect = NSMakeRect(ovalRect.minX, ovalRect.minY+5, ovalRect.width, ovalRect.height)
                        atomLabel.draw(with: labelRect, options: [], attributes: atomLabelAttributes)
                        
                        let timeRect = NSMakeRect(ovalRect.minX, ovalRect.minY-yarnGap*(1/3.0), ovalRect.width, yarnGap*(1/3.0))
                        clockLabel.replaceCharacters(in: NSMakeRange(0, clockLabel.length), with: "\(elements[index].id.index)")
                        clockLabel.draw(with: timeRect, options: [], attributes: clockLabelAttributes)
                    }
                }
            }
        }
        
        func drawConnection(_ from: AtomId, _ to: AtomId, color: NSColor)
        {
            if to == from || to == NullAtomId {
                return
            }
            guard let p0 = atomSiteCenter(site: to.site, index: to.index) else {
                return
            }
            guard let p1 = atomSiteCenter(site: from.site, index: from.index) else {
                return
            }
            
            let p0Bounds = NSMakeRect(p0.x-atomRadius, p0.y-atomRadius, atomRadius*2, atomRadius*2)
            let p1Bounds = NSMakeRect(p1.x-atomRadius, p1.y-atomRadius, atomRadius*2, atomRadius*2)
            
            // only show arrow when atoms are close to the screen, to avoid ten million arrows on screen at once
            var mid = NSMakePoint(p0Bounds.midX, p0Bounds.midY)
            let p0b = p0Bounds.applying(CGAffineTransform.init(translationX: -mid.x, y: -mid.y)).applying(CGAffineTransform.init(scaleX: 25, y: 1)).applying(CGAffineTransform.init(translationX: mid.x, y: mid.y))
            mid = NSMakePoint(p1Bounds.midX, p1Bounds.midY)
            let p1b = p1Bounds.applying(CGAffineTransform.init(translationX: -mid.x, y: -mid.y)).applying(CGAffineTransform.init(scaleX: 25, y: 1)).applying(CGAffineTransform.init(translationX: mid.x, y: mid.y))
            if !bounds.applying(translation).intersects(p0b) && !bounds.applying(translation).intersects(p1b) {
                return
            }
            
            drawArrow(from: p1, to: p0, color: color)
        }
        
        for i in 0..<yarns {
            let elements = delegate.yarn(withSite: sites[i], forView: self)
            let elementRange = 0..<min(elements.count, elements.count)
            
            drawConnections: do {
                //break drawConnections
                for j in elementRange {
                    let index = elements.index(elements.startIndex, offsetBy: j)
                    
                    var disabled = false
                    if let awareness = awarenessWeftToDraw {
                        if let siteAwareness = awareness.mapping[SiteId(i)],
                            siteAwareness >= elements[index].index {
                        }
                        else {
                            disabled = true
                        }
                    }
                    
                    let causeColor = (disabled ? disabledColor : NSColor(white: 0.5, alpha: 1))
                    let refColor = (disabled ? disabledColor : NSColor.red)
                    
                    drawConnection(elements[index].id, elements[index].cause, color: causeColor)
                    drawConnection(elements[index].id, elements[index].reference, color: refColor)
                }
            }
        }
        
        NSGraphicsContext.restoreGraphicsState()
    }
}
