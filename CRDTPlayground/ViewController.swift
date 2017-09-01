//
//  ViewController.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-8-28.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Cocoa

class ViewController: NSViewController, WeaveDrawingViewDelegate {
    var weave: Weave<UUID, String> = Weave()
    
    var weaveDrawingView: WeaveDrawingView!
    
    //override func loadView() {
    //    let view = WeaveDrawingView(frame: NSMakeRect(0, 0, 800, 300))
    //    self.view = view
    //    view.delegate = self
    //}
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let view = WeaveDrawingView(frame: self.view.bounds)
        view.delegate = self
        self.view.addSubview(view)
        view.autoresizingMask = [.width, .height]
        weaveDrawingView = view
        
        self.view.wantsLayer = true
        self.view.layer!.drawsAsynchronously = true
        self.view.canDrawConcurrently = true
        view.canDrawConcurrently = true
        
        //WeaveTest(&self.weave)
        WeaveHardConcurrency(&self.weave)
    }
    
    override var representedObject: Any? {
        didSet {
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        let scalar: CGFloat = 1.5
        weaveDrawingView.offset = NSMakePoint(weaveDrawingView.offset.x + event.deltaX * scalar,
                                              weaveDrawingView.offset.y - event.deltaY * scalar)
    }
    
    func sites(forView: WeaveDrawingView) -> [Weave<UUID, String>.SiteId] {
        return weave.sites.map({ (uuid: UUID) -> Weave<UUID, String>.SiteId in
            return weave.siteId(forSite: uuid)!
        })
    }
    
    func yarn(withSite site: Weave<UUID, String>.SiteId, forView: WeaveDrawingView) -> AnyBidirectionalCollection<Weave<UUID, String>.Atom> {
        return weave.yarn(forSite: site)
    }
    
    func index(forAtomClock clock: Weave<UUID, String>.Clock, atSite site: Weave<UUID, String>.SiteId) -> Int? {
        return weave.index(forSite: site, beforeCommit: clock, equalOnly: true)
    }
}

protocol WeaveDrawingViewDelegate: class {
    func sites(forView: WeaveDrawingView) -> [Weave<UUID, String>.SiteId]
    func yarn(withSite site: Weave<UUID, String>.SiteId, forView: WeaveDrawingView) -> AnyBidirectionalCollection<Weave<UUID, String>.Atom>
    func index(forAtomClock clock: Weave<UUID, String>.Clock, atSite site: Weave<UUID, String>.SiteId) -> Int?
}

class WeaveDrawingView: NSView, CALayerDelegate {
    weak var delegate: WeaveDrawingViewDelegate?
    
    //would be much better as a scroll view, but not worth the effort, really
    private var _offset: NSPoint = NSMakePoint(0, 0)
    var offset: NSPoint {
        get {
            return _offset
        }
        set {
            _offset = NSMakePoint(min(newValue.x, 0), max(newValue.y, 0))
            setNeedsDisplay(self.bounds)
            print("offset is \(offset)")
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
    
    func updateWeave(weave: Weave<UUID, String>) {
        // 1. copy weave memory so we can avoid conflicts
        
        // 2. perform weave drawing on a separate thread
        
        // 3. signal our layer that the context is available to draw
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
        print("fps: \(fps) (main thread \(Thread.isMainThread)), \(layer.drawsAsynchronously)")
        lastClock = clock
        
        guard let delegate = self.delegate else {
            return
        }
        
        NSGraphicsContext.saveGraphicsState()
        let gctx = NSGraphicsContext.init(cgContext: ctx, flipped: false)
        NSGraphicsContext.current = gctx
        
        // warning: in async, might cause occasional wonkiness
        let bounds = self.bounds
        
        // color background
        NSColor.white.setFill()
        NSBezierPath(rect: bounds).fill()
        
        // TODO: bounding boxes
        
        let translation = CGAffineTransform.init(translationX: offset.x, y: offset.y).inverted()
        ctx.translateBy(x: offset.x, y: offset.y)
        
        let atomRadius: CGFloat = 10
        let atomGap: CGFloat = 10
        let yarnGap: CGFloat = 40
        let connectorThickness: CGFloat = 2
        
        let sites = delegate.sites(forView: self)
        let yarns = sites.count
        
        // memoized expensive call
        var indexForAtomClockAtSite: ((Weave<UUID, String>.Clock, Weave<UUID, String>.SiteId)->Int?) = {
            var memoized: [Weave<UUID, String>.SiteId:[Weave<UUID, String>.Clock:Int?]] = [:]
            func _memoizedIndexForAtomClockAtSite(_ clock: Weave<UUID, String>.Clock, _ site: Weave<UUID, String>.SiteId) -> Int? {
                if let mClock = memoized[site], let mRet = mClock[clock] {
                    return mRet
                }
                else {
                    let ret = delegate.index(forAtomClock: clock, atSite: site)
                    if memoized[site] == nil {
                        memoized[site] = [:]
                    }
                    memoized[site]![clock] = ret
                    return ret
                }
            }
            return _memoizedIndexForAtomClockAtSite
        }()
        
        // position functions
        func atomCenter(row: Int, column: Int) -> NSPoint {
            let x = (atomGap/2 + atomRadius*2 + atomGap/2) * CGFloat(column) + (atomGap/2 + atomRadius)
            let y = bounds.size.height - ((yarnGap/2 + atomRadius*2 + atomGap/2) * CGFloat(row) + (yarnGap/2 + atomRadius))
            
            return NSMakePoint(x, y)
        }
        func atomSiteCenter(site: Weave<UUID, String>.SiteId, clock: Weave<UUID, String>.Clock) -> NSPoint? {
            if let siteIndex = sites.index(of: site), let atomIndex = indexForAtomClockAtSite(clock, site) {
                return atomCenter(row: Int(siteIndex), column: Int(atomIndex))
            }
            
            return nil
        }
        
        // drawing functions
        func drawArrow(from p0: NSPoint, to p1: NSPoint) {
            let angle = 30 * (2 * CGFloat.pi)/360
            let peak = atomRadius * 0.8
            let xOffset = atomRadius * 0.5
            let yOffset = atomRadius * 0.5
            let arrowLength = atomRadius * 0.6
            let arrowAngle = 20 * (2 * CGFloat.pi)/360
            
            let color = NSColor(white: 0.5, alpha: 1)
            
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
        let atomLabelAttributes: [NSAttributedStringKey:AnyObject] = [NSAttributedStringKey.paragraphStyle:atomLabelParagraphStyle, NSAttributedStringKey.font:atomLabelFont]
        let atomLabel: NSMutableString = ""
        
        // string construction caching
        let clockLabelParagraphStyle = NSMutableParagraphStyle()
        clockLabelParagraphStyle.alignment = .center
        let clockLabelFont = NSFont.systemFont(ofSize: 8, weight: NSFont.Weight.thin)
        let clockLabelAttributes: [NSAttributedStringKey:AnyObject] = [NSAttributedStringKey.paragraphStyle:clockLabelParagraphStyle, NSAttributedStringKey.font:clockLabelFont, NSAttributedStringKey.foregroundColor:NSColor.darkGray]
        let clockLabel: NSMutableString = ""
        
        for i in 0..<yarns {
            let color = colors[i]
            
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
                    let p = atomSiteCenter(site: sites[i], clock: elements[index].id.clock)!
                    
                    let ovalRect = NSMakeRect(p.x - atomRadius, p.y - atomRadius, atomRadius * 2, atomRadius * 2)
                    
                    if !bounds.applying(translation).intersects(ovalRect) {
                        continue
                    }
                    
                    let atom = NSBezierPath(ovalIn: ovalRect)
                    
                    NSColor.white.setFill()
                    atom.fill()
                    color.setStroke()
                    atom.lineWidth = 1.5
                    atom.stroke()
                    
                    drawText: do {
                        //break drawText
                        
                        let labelRect = NSMakeRect(ovalRect.minX, ovalRect.minY+5, ovalRect.width, ovalRect.height)
                        if elements[index].id.clock == Weave<UUID, String>.StartClock {
                            atomLabel.replaceCharacters(in: NSMakeRange(0, atomLabel.length), with: "⚀")
                        }
                        else if elements[index].id.clock == Weave<UUID, String>.EndClock {
                            atomLabel.replaceCharacters(in: NSMakeRange(0, atomLabel.length), with: "⚅")
                        }
                        else {
                            atomLabel.replaceCharacters(in: NSMakeRange(0, atomLabel.length), with: elements[index].value)
                        }
                        atomLabel.draw(with: labelRect, options: [], attributes: atomLabelAttributes)
                        
                        let timeRect = NSMakeRect(ovalRect.minX, ovalRect.minY-yarnGap*(1/3.0), ovalRect.width, yarnGap*(1/3.0))
                        clockLabel.replaceCharacters(in: NSMakeRange(0, clockLabel.length), with: "\(elements[index].id.clock)")
                        clockLabel.draw(with: timeRect, options: [], attributes: clockLabelAttributes)
                    }
                }
            }
            
            drawConnections: do {
                for j in elementRange {
                    let index = elements.index(elements.startIndex, offsetBy: j)
                    
                    let previousAtom = elements[index].cause
                    
                    if previousAtom == Weave<UUID, String>.NullAtomId {
                        continue
                    }
                    guard let p0 = atomSiteCenter(site: previousAtom.site, clock: previousAtom.clock) else {
                        continue
                    }
                    guard let p1 = atomSiteCenter(site: elements[index].id.site, clock: elements[index].id.clock) else {
                        continue
                    }
                    
                    let p0Bounds = NSMakeRect(p0.x-atomRadius, p0.y-atomRadius, atomRadius*2, atomRadius*2)
                    let p1Bounds = NSMakeRect(p1.x-atomRadius, p1.y-atomRadius, atomRadius*2, atomRadius*2)
                    
                    if !bounds.applying(translation).intersects(p0Bounds) && !bounds.applying(translation).intersects(p1Bounds) {
                        continue
                    }
                    
                    drawArrow(from: p1, to: p0)
                }
            }
        }
        
        NSGraphicsContext.restoreGraphicsState()
    }
}
