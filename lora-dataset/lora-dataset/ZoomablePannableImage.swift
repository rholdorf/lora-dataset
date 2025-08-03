import SwiftUI
import AppKit

/// Uma view SwiftUI que dá zoom com roda do mouse e pan com arraste.
struct ZoomablePannableImage: NSViewRepresentable {
    let image: NSImage?
    
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    
    func makeNSView(context: Context) -> ZoomableImageNSView {
        let view = ZoomableImageNSView()
        view.image = image
        view.scale = scale
        view.offset = offset
        view.onChange = { newScale, newOffset in
            DispatchQueue.main.async {
                scale = newScale
                offset = newOffset
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: ZoomableImageNSView, context: Context) {
        nsView.image = image
        nsView.scale = scale
        nsView.offset = offset
        nsView.needsDisplay = true
    }
}

/// NSView que trata zoom com scrollWheel e pan com mouse drag.
final class ZoomableImageNSView: NSView {
    var image: NSImage? {
        didSet {
            resetToFit()
        }
    }
    var scale: CGFloat = 1.0 {
        didSet { onChange?(scale, offset) }
    }
    var offset: CGSize = .zero {
        didSet { onChange?(scale, offset) }
    }
    
    var onChange: ((CGFloat, CGSize) -> Void)?
    
    private var isDragging = false
    private var lastDragLocation: NSPoint = .zero
    
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        // atualizar tracking area
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self,
                                       userInfo: nil))
        resetToFit()
    }
    
    private func resetToFit() {
        guard let img = image else { return }
        // calcula escala de "fit" baseado no tamanho da área visível (dentro da borda)
        let iw = img.size.width
        let ih = img.size.height
        if iw > 0 && ih > 0 && bounds.width > 0 && bounds.height > 0 {
            // Considera a área disponível dentro da borda (subtraindo o espaço da borda e padding)
            let availableWidth = bounds.width - 4 // 2 pixels de cada lado para a borda e clipping
            let availableHeight = bounds.height - 4 // 2 pixels de cada lado para a borda e clipping
            let fitScale = min(availableWidth / iw, availableHeight / ih)
            scale = fitScale
            offset = .zero
            needsDisplay = true
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let img = image else { return }
        
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        
        // Define a área de clipping para os bounds do componente
        context?.clip(to: bounds.insetBy(dx: 1, dy: 1))
        
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        context?.translateBy(x: center.x + offset.width, y: center.y + offset.height)
        context?.scaleBy(x: scale, y: scale)
        context?.translateBy(x: -img.size.width / 2, y: -img.size.height / 2)
        
        // Desenha a imagem (será cortada pelo clipping)
        img.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
        
        context?.restoreGState()
        
        // Desenha a borda do componente (fora das transformações e clipping)
        context?.setStrokeColor(NSColor.gray.cgColor)
        context?.setLineWidth(1.0)
        context?.stroke(bounds.insetBy(dx: 0.5, dy: 0.5))
    }

    
    // Zoom pela roda do mouse
    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        let zoomFactor: CGFloat = 1 + (delta * 0.0025) // ajuste de sensibilidade
        let oldScale = scale
        let newScale = max(0.1, min(scale * zoomFactor, 10))
        
        // Mantém o ponto sob o cursor como foco
        let mouseLocation = convert(event.locationInWindow, from: nil)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        
        let dx = (mouseLocation.x - center.x - offset.width) / oldScale
        let dy = (mouseLocation.y - center.y - offset.height) / oldScale
        
        scale = newScale
        offset = CGSize(
            width: offset.width - dx * (newScale - oldScale),
            height: offset.height - dy * (newScale - oldScale)
        )
        
        onChange?(scale, offset)
        needsDisplay = true
    }
    
    // Pan com clique e arraste
    override func mouseDown(with event: NSEvent) {
        isDragging = true
        lastDragLocation = convert(event.locationInWindow, from: nil)
        NSCursor.closedHand.push()
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let current = convert(event.locationInWindow, from: nil)
        let dx = current.x - lastDragLocation.x
        let dy = current.y - lastDragLocation.y
        offset = CGSize(width: offset.width + dx, height: offset.height + dy)
        lastDragLocation = current
        onChange?(scale, offset)
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        isDragging = false
        NSCursor.pop()
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: NSCursor.openHand)
    }
}
