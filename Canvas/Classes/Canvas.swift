//
//  Canvas.swift
//  Canvas
//
//  Created by Adeola Uthman on 10/7/18.
//

import UIKit
import CoreImage

/** An area of the screen that allows drawing. */
public class Canvas: UIView {
    
    /************************
     *                      *
     *       VARIABLES      *
     *                      *
     ************************/
    
    // -- PRIVATE VARS
    
    /** The touch color. */
    internal var isSavedImage: Bool = false
    
    /** The touch color. */
    internal var tileColor: CGColor = UIColor.clear.cgColor
    
    /** The touch points. */
    internal var currentPoint: CGPoint = CGPoint()
    internal var lastPoint: CGPoint = CGPoint()
    internal var lastLastPoint: CGPoint = CGPoint()
    internal var eraserStartPoint: CGPoint = CGPoint()
    
    /** The next node to be drawn on the canvas. */
    internal var nextNode: Node? = nil
    
    /** A collection of the layers on this canvas. */
    internal var _canvasLayers: [CanvasLayer] = []
    internal var _currentCanvasLayer: Int = 0
    
    /** The current brush that is being used to style drawings. */
    internal var _currentBrush: Brush = Brush.Default
    
    /** The current tool that is being used to draw. */
    internal var _currentTool: CanvasTool = CanvasTool.pen
    
    /** The copied nodes. */
    internal var _copiedNodes: [Node] = []
    
    
    
    // -- PUBLIC VARS
    
    /** Events delegate. */
    public var delegate: CanvasEvents?
    
    /** The brush that is currently being used to style drawings. */
    public var currentBrush: Brush {
        set { _currentBrush = newValue }
        get { return _currentBrush }
    }
    
    /** The tool that is currently being used to draw on the canvas. */
    public var currentTool: CanvasTool {
        set { _currentTool = newValue }
        get { return _currentTool }
    }
    
    /** The action to use for the eyedropper: set stroke or fill color. */
    public var eyedropperOptions: EyedropperOptions = .stroke
    
    /** The undo redo manager. */
    public var undoRedoManager: UndoRedoManager = UndoRedoManager()
    
    
    
    
    // -- COMPUTED PROPS
    
    /** The layer that you are currently on. */
    public var currentCanvasLayer: Int {
        return self._currentCanvasLayer
    }
    
    /** The layer that you are currently on. */
    public var currentLayer: CanvasLayer? {
        if self._currentCanvasLayer < 0 || self._currentCanvasLayer >= self._canvasLayers.count {
            return nil
        } else {
            return self._canvasLayers[self._currentCanvasLayer]
        }
    }
    
    /** The layers of the canvas. */
    public var canvasLayers: [CanvasLayer] {
        return self._canvasLayers
    }
    
    
    
    
    /************************
     *                      *
     *         INIT         *
     *                      *
     ************************/
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    public init(createDefaultLayer: Bool) {
        super.init(frame: CGRect.zero)
        setup(createDefaultLayer: createDefaultLayer)
    }
    
    private func setup(createDefaultLayer: Bool = false) {
        if createDefaultLayer == true {
            let defLay = CanvasLayer(type: LayerType.raster)
            self.addLayer(newLayer: defLay, position: .above)
        }
        backgroundColor = .clear
    }
    
    
    
    
    /************************
     *                      *
     *       FUNCTIONS      *
     *                      *
     ************************/
    
    // -- UNDO / REDO / CLEAR --
    
    /** Allows the user to define custom behavior for undo and redo. For example, a custom function to undo changing the tool. */
    public func addCustomUndoRedo(cUndo: @escaping () -> Any?, cRedo: @escaping () -> Any?) {
        undoRedoManager.add(undo: cUndo, redo: cRedo)
    }
    
    
    /** Undo the last action on the canvas. */
    public func undo() {
        let _ = undoRedoManager.performUndo()
        setNeedsDisplay()
        self.delegate?.didUndo(on: self)
    }
    
    
    /** Redo the last action on the canvas. */
    public func redo() {
        let _ = undoRedoManager.performRedo()
        setNeedsDisplay()
        self.delegate?.didRedo(on: self)
    }
    
    
    /** Clears the entire canvas. */
    public func clear() {
        for i in 0..<_canvasLayers.count { clearLayer(at: i) }
        setNeedsDisplay()
    }
    
    
    /** Clears a drawing on the layer at the specified index. */
    public func clearLayer(at: Int) {
        if at < 0 || at >= _canvasLayers.count { return }
        _canvasLayers[at].clear(from: self)
        undoRedoManager.clearRedos()
        setNeedsDisplay()
    }
    
    
    
    // -- IMPORT / EXPORT --
    
    /** Exports the canvas drawing. */
    public func export() -> UIImage {
        UIGraphicsBeginImageContext(self.frame.size)
        guard let ctx = UIGraphicsGetCurrentContext() else { return UIImage() }
        self.layer.render(in: ctx)
        
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return img ?? UIImage()
    }
    
    
    /** Exports the drawing on a specific layer. */
    public func exportLayer(at: Int) -> UIImage {
        if at < 0 || at >= _canvasLayers.count { return UIImage() }
        if _canvasLayers[at].drawings.isEmpty { return UIImage() }
        UIGraphicsBeginImageContext(self.frame.size)
        
        for node in _canvasLayers[at].drawings {
            let path = build(from: node.points, using: node.instructions, tool: node.type)
            let shapeLayer = CAShapeLayer()
            shapeLayer.bounds = path.boundingBox
            shapeLayer.path = path
            shapeLayer.strokeColor = node.brush.strokeColor.cgColor
            shapeLayer.fillRule = CAShapeLayerFillRule.evenOdd
            shapeLayer.fillMode = CAMediaTimingFillMode.both
            shapeLayer.fillColor = node.brush.fillColor?.cgColor ?? nil
            shapeLayer.opacity = Float(node.brush.opacity)
            shapeLayer.lineWidth = node.brush.thickness
            shapeLayer.miterLimit = node.brush.miter
            switch node.brush.shape {
            case .butt:
                shapeLayer.lineCap = CAShapeLayerLineCap.butt
                break
            case .round:
                shapeLayer.lineCap = CAShapeLayerLineCap.round
                break
            case .square:
                shapeLayer.lineCap = CAShapeLayerLineCap.square
                break
            }
            switch node.brush.joinStyle {
            case .bevel:
                shapeLayer.lineJoin = CAShapeLayerLineJoin.bevel
                break
            case .miter:
                shapeLayer.lineJoin = CAShapeLayerLineJoin.miter
                break
            case .round:
                shapeLayer.lineJoin = CAShapeLayerLineJoin.round
                break
            }
            
            var nPos = path.boundingBox.origin
            nPos.x += path.boundingBox.width / 2
            nPos.y += path.boundingBox.height / 2
            shapeLayer.position = nPos
            
            shapeLayer.render(in: UIGraphicsGetCurrentContext()!)
        }
        
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return img ?? UIImage()
    }
    
    
    /** Exports the given nodes to a UIImage. */
    public static func export(nodes: [Node], size: CGSize) -> UIImage {
        UIGraphicsBeginImageContext(size)

        for node in nodes {
            let path = build(from: node.points, using: node.instructions, tool: node.type)
            let shapeLayer = CAShapeLayer()
            shapeLayer.bounds = path.boundingBox
            shapeLayer.path = path
            shapeLayer.strokeColor = node.brush.strokeColor.cgColor
            shapeLayer.fillRule = CAShapeLayerFillRule.evenOdd
            shapeLayer.fillMode = CAMediaTimingFillMode.both
            shapeLayer.fillColor = node.brush.fillColor?.cgColor ?? nil
            shapeLayer.opacity = Float(node.brush.opacity)
            shapeLayer.lineWidth = node.brush.thickness
            shapeLayer.miterLimit = node.brush.miter
            switch node.brush.shape {
            case .butt:
                shapeLayer.lineCap = CAShapeLayerLineCap.butt
                break
            case .round:
                shapeLayer.lineCap = CAShapeLayerLineCap.round
                break
            case .square:
                shapeLayer.lineCap = CAShapeLayerLineCap.square
                break
            }
            switch node.brush.joinStyle {
            case .bevel:
                shapeLayer.lineJoin = CAShapeLayerLineJoin.bevel
                break
            case .miter:
                shapeLayer.lineJoin = CAShapeLayerLineJoin.miter
                break
            case .round:
                shapeLayer.lineJoin = CAShapeLayerLineJoin.round
                break
            }
            
            var nPos = path.boundingBox.origin
            nPos.x += path.boundingBox.width / 2
            nPos.y += path.boundingBox.height / 2
            shapeLayer.position = nPos
            
            shapeLayer.render(in: UIGraphicsGetCurrentContext()!)
        }

        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return img ?? UIImage()
    }
    
    
    
    // -- COPY / PASTE --
    
    /** Copies a particular node so that it can be pasted later. */
    public func copy(nodes: [Node]) {
        _copiedNodes = nodes
        self.delegate?.didCopyNodes(on: self, nodes: nodes)
    }
    
    
    /** Pastes the copied node on to the current layer. */
    public func paste() {
        guard let cl = currentLayer else { return }
        cl.drawings.append(contentsOf: _copiedNodes)
        setNeedsDisplay()
        
        undoRedoManager.add(undo: {
            if cl.drawings.count > 0 {
                cl.drawings.removeLast()
            }
            return nil
        }, redo: {
            cl.drawings.append(contentsOf: self._copiedNodes)
            return nil
        })
        
        self.delegate?.didPasteNodes(on: self, on: cl, nodes: _copiedNodes)
    }
    

    
    
    /************************
     *                      *
     *        DRAWING       *
     *                      *
     ************************/
    
    public override func draw(_ rect: CGRect) {
        // 1.) Clear all sublayers.
        layer.sublayers = []
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        // 2.) Go through each layer and render it using either raster or vector graphics.
        for i in (0..<self._canvasLayers.count).reversed() {
            let layer = self._canvasLayers[i]
            if layer.isVisible == false { continue }

            if layer.type == .raster {
                drawTiledBrush(layer: layer, in: context)
                //drawRaster(layer: layer, rect)
            } else {
                drawVector(layer: layer, rect)
            }
        }
        
        // 2.5.) If there are node that are selected, draw the selection box.
        /* if let currLayer = self.currentLayer {
            guard let context = UIGraphicsGetCurrentContext() else { return }
            for node in currLayer.selectedNodes {
                let path = build(from: node.points, using: node.instructions, tool: node.type)
                
                context.addPath(path)
                context.setLineCap(.butt)
                context.setLineJoin(.miter)
                context.setLineWidth(1)
                context.setMiterLimit(1)
                context.setAlpha(1)
                context.setBlendMode(.normal)
                context.setStrokeColor(UIColor.black.cgColor)
                context.setLineDash(phase: 0, lengths: [10, 10])
                context.stroke(path.boundingBox)
            }
        }*/
        
        // 3.) Draw the temporary drawing.
        tileColor = UIColor(patternImage: currentBrush.colored ?? UIImage()).cgColor

        guard let next = nextNode else { return }
        guard let context = UIGraphicsGetCurrentContext() else { return }
        if _currentTool == .selection {
            let path = build(from: next.points, using: next.instructions, tool: next.type)
            context.addPath(path)
            context.setLineCap(.butt)
            context.setLineJoin(.miter)
            context.setStrokeColor(tileColor)
            context.setMiterLimit(1)
            context.setAlpha(1)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [10, 10])
            context.setBlendMode(.normal)
            context.strokePath()
        } else {
            let path = build(from: next.points, using: next.instructions, tool: next.type)
            context.addPath(path)
            context.setLineCap(self._currentBrush.shape)
            context.setLineJoin(self._currentBrush.joinStyle)
            context.setLineWidth(self._currentBrush.thickness)
            context.setStrokeColor(tileColor)
            context.setMiterLimit(self._currentBrush.miter)
            context.setAlpha(self._currentBrush.opacity)
            context.setBlendMode(.normal)
            context.strokePath()
        }
    }

    
    private func drawTiledBrush(layer: CanvasLayer, in context: CGContext) {
        for node in layer.drawings {
            
            //guard let colored = node.brush.colored else { continue }
            // 🎨 Цвет кисти (как паттерн)
            if !node.brush.isEraser { tileColor = UIColor(patternImage: (node.brush.colored ?? UIImage())!).cgColor }
            
            if isSavedImage {
                if let image = node.image {
                    guard let path = node.points.first, path.count >= 2 else { return }

                    let origin = path[0]
                    let bottomRight = path.count > 2 ? path[2] : path[1]

                    let width = bottomRight.x - origin.x
                    let height = bottomRight.y - origin.y

                    let frame = CGRect(
                        x: origin.x,
                        y: origin.y,
                        width: abs(width),
                        height: abs(height)
                    )

                    if let cgImage = image.cgImage {
                        context.saveGState()
                        context.translateBy(x: 0, y: frame.origin.y * 2 + frame.size.height)
                        context.scaleBy(x: 1.0, y: -1.0)
                        context.setAlpha(node.brush.opacity)
                        context.draw(cgImage, in: frame)

                        context.restoreGState()
                    }
                }
                //return
            }

            for pointArray in node.points {
                guard pointArray.count > 1 else { continue }

                let path = CGMutablePath()
                path.move(to: pointArray[0])
                for point in pointArray.dropFirst() {
                    path.addLine(to: point)
                }

                context.saveGState()
                context.addPath(path)
                context.setLineWidth(node.brush.thickness)
                context.setLineCap(.round)
                context.setLineJoin(.round)

                if node.brush.isEraser {
                    context.setBlendMode(.clear)
                    context.setAlpha(1.0)
                } else {
                    context.setStrokeColor(tileColor)
                    context.setAlpha(node.brush.opacity)
                    context.setBlendMode(.normal)
                }

                context.strokePath()
                context.restoreGState()
            }
        }
    }
    
    private func drawRaster(layer: CanvasLayer, _ rect: CGRect) {
        
        guard let context = UIGraphicsGetCurrentContext() else { return }

        for node in layer.drawings {
            
            if let image = node.image {
                guard let path = node.points.first, path.count >= 2 else { continue }

                let origin = path[0]
                let bottomRight = path.count > 2 ? path[2] : path[1]

                let width = bottomRight.x - origin.x
                let height = bottomRight.y - origin.y

                let frame = CGRect(x: origin.x,
                                   y: origin.y,
                                   width: abs(width),
                                   height: abs(height))

                if let cgImage = image.cgImage {
                    context.saveGState()
                    context.setAlpha(node.brush.opacity)
                    context.draw(cgImage, in: frame)
                    context.restoreGState()
                }

                continue
            }
            
            guard let cgImage = node.brush.colored?.cgImage else { continue }
            
            let thickness = node.brush.thickness
            //let alpha = node.brush.opacity
            //let spacing = thickness //* 0.3 // 20–40% перекрытия
            
            let overlapRatio: CGFloat = 0.3
            let spacing = thickness * (1.0 - overlapRatio)
            let alpha = node.brush.opacity * min(1.0, 1.0 / (1.0 - overlapRatio))
    
            for strokePoints in node.points {
                guard strokePoints.count > 1 else { continue }
                
                var lastPoint = strokePoints[0]
                
                for currentPoint in strokePoints.dropFirst() {
                    let dx = currentPoint.x - lastPoint.x
                    let dy = currentPoint.y - lastPoint.y
                    let distance = hypot(dx, dy)
                    let steps = max(Int(distance / spacing), 1)
                    
                    let angle = atan2(dy, dx)
                    
                    for step in 0..<steps {
                        let t = CGFloat(step) / CGFloat(steps)
                        let x = lastPoint.x + dx * t
                        let y = lastPoint.y + dy * t
                        let center = CGPoint(x: x, y: y)
                        
                        let drawRect = CGRect(
                            x: center.x - thickness / 2,
                            y: center.y - thickness / 2,
                            width: thickness,
                            height: thickness
                        )
                        
                        context.saveGState()
                        context.translateBy(x: center.x, y: center.y)
                        context.rotate(by: angle)
                        context.translateBy(x: -center.x, y: -center.y)
                        context.setAlpha(alpha)
                        context.draw(cgImage, in: drawRect)
                        context.restoreGState()
                    }
                    
                    lastPoint = currentPoint
                }
            }
        }
    }
    
    private func renderImage() {

    }
    
    private func drawVector(layer: CanvasLayer, _ rect: CGRect) {
        for node in layer.drawings {
            let path = build(from: node.points, using: node.instructions, tool: node.type)
            let shapeLayer = CAShapeLayer()
            
            if let texture = node.brush.texture?.cgImage {
                shapeLayer.fillColor = UIColor.clear.cgColor
                shapeLayer.strokeColor = nil
                shapeLayer.contents = texture
                shapeLayer.contentsGravity = .resizeAspectFill
            } else {
                shapeLayer.strokeColor = node.brush.strokeColor.cgColor
            }
            shapeLayer.bounds = path.boundingBox
            shapeLayer.path = path
            shapeLayer.strokeColor = node.brush.strokeColor.cgColor
            shapeLayer.fillRule = CAShapeLayerFillRule.evenOdd
            shapeLayer.fillMode = CAMediaTimingFillMode.both
            shapeLayer.fillColor = node.brush.fillColor?.cgColor ?? nil
            shapeLayer.opacity = Float(node.brush.opacity)
            shapeLayer.lineWidth = node.brush.thickness
            shapeLayer.miterLimit = node.brush.miter
            switch node.brush.shape {
            case .butt:
                shapeLayer.lineCap = CAShapeLayerLineCap.butt
                break
            case .round:
                shapeLayer.lineCap = CAShapeLayerLineCap.round
                break
            case .square:
                shapeLayer.lineCap = CAShapeLayerLineCap.square
                break
            }
            switch node.brush.joinStyle {
            case .bevel:
                shapeLayer.lineJoin = CAShapeLayerLineJoin.bevel
                break
            case .miter:
                shapeLayer.lineJoin = CAShapeLayerLineJoin.miter
                break
            case .round:
                shapeLayer.lineJoin = CAShapeLayerLineJoin.round
                break
            }
            
            var nPos = path.boundingBox.origin
            nPos.x += path.boundingBox.width / 2
            nPos.y += path.boundingBox.height / 2
            shapeLayer.position = nPos
            
            let insertIndex = self._currentCanvasLayer == 0 ? 0 : self._currentCanvasLayer
            self.layer.insertSublayer(shapeLayer, at: UInt32(insertIndex))
        }
    }
    
    /// Добавляет изображение на текущий слой канваса.
    public func drawImage(_ image: UIImage, in frame: CGRect) {
        isSavedImage = true
        guard let layer = currentLayer else { return }

        let node = Node(type: .image)
        node.points = [[
            CGPoint(x: 0, y: 0),
            CGPoint(x: image.size.width, y: 0),
            CGPoint(x: image.size.width, y: image.size.height),
            CGPoint(x: 0, y: image.size.height)
        ]]
        node.image = image
        
        layer.drawings.append(node)
        setNeedsDisplay()
    }
    
}
