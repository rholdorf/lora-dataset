import SwiftUI
import AppKit

/// Uma view SwiftUI que dá zoom com roda do mouse e pan com arraste.
struct ZoomablePannableImage: NSViewRepresentable {
    let image: NSImage?
    
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: ZoomablePannableImage
        
        init(_ parent: ZoomablePannableImage) {
            self.parent = parent
        }
        
        func updateBindings(scale: CGFloat, offset: CGSize) {
            // Só atualiza se os valores realmente mudaram
            if abs(parent.scale - scale) > 0.001 {
                parent.scale = scale
            }
            if abs(parent.offset.width - offset.width) > 0.1 || abs(parent.offset.height - offset.height) > 0.1 {
                parent.offset = offset
            }
        }
    }
    
    func makeNSView(context: Context) -> ZoomableImageNSView {
        let view = ZoomableImageNSView()
        view.image = image
        view.scale = scale
        view.offset = offset
        view.coordinator = context.coordinator
        // Initialize zoom to fit on creation
        view.resetToFit()
        return view
    }
    
    func updateNSView(_ nsView: ZoomableImageNSView, context: Context) {
        // Atualiza imagem e reset quando diferente
        nsView.coordinator = context.coordinator
        if nsView.image !== image {
            nsView.image = image
            nsView.resetToFit()
            // Atualiza bindings SwiftUI
            context.coordinator.updateBindings(scale: nsView.scale, offset: nsView.offset)
        }
        // Sincroniza scale e offset sem disparar callbacks
        nsView.isUpdatingProgrammatically = true
        if abs(nsView.scale - scale) > 0.001 {
            nsView.scale = scale
        }
        if abs(nsView.offset.width - offset.width) > 0.1 || abs(nsView.offset.height - offset.height) > 0.1 {
            nsView.offset = offset
        }
        nsView.isUpdatingProgrammatically = false
        // Força redraw
        nsView.needsDisplay = true
    }
}

/// NSView que trata zoom com scrollWheel e pan com mouse drag.
final class ZoomableImageNSView: NSView {
    // Image without automatic reset; zoom resets explicitly in updateNSView
    var image: NSImage?
    var scale: CGFloat = 1.0 {
        didSet { 
            if scale != oldValue && !isUpdatingProgrammatically {
                notifyChanges()
            }
        }
    }
    var offset: CGSize = .zero {
        didSet { 
            if offset != oldValue && !isUpdatingProgrammatically {
                notifyChanges()
            }
        }
    }
    
    var onChange: ((CGFloat, CGSize) -> Void)?
    weak var coordinator: ZoomablePannableImage.Coordinator?
    
    private var isDragging = false
    private var lastDragLocation: NSPoint = .zero
    private var isInitialized = false
    var isUpdatingProgrammatically = false
    
    private func notifyChanges() {
        // Usa async para evitar modificar state durante view update
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.coordinator?.updateBindings(scale: self.scale, offset: self.offset)
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupView()
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && !isInitialized {
            setupView()
        }
    }
    
    private func setupView() {
        guard !isInitialized else { return }
        isInitialized = true
        
        // Configuração inicial das tracking areas
        updateTrackingAreas()
    }
    
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        updateTrackingAreas()
        
        // Só chama resetToFit se a view mudou significativamente de tamanho
        let sizeDifference = abs(bounds.width - oldSize.width) + abs(bounds.height - oldSize.height)
        if sizeDifference > 1.0 {
            resetToFit()
        }
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Remove todas as tracking areas existentes
        trackingAreas.forEach { removeTrackingArea($0) }
        
        // Adiciona nova tracking area apenas se a view tem tamanho válido
        if bounds.width > 0 && bounds.height > 0 {
            addTrackingArea(NSTrackingArea(rect: bounds,
                                           options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                           owner: self,
                                           userInfo: nil))
        }
    }
    
    public func resetToFit() {
        guard let img = image else { return }
        // calcula escala de "fit" baseado no tamanho da área visível (dentro da borda)
        let iw = img.size.width
        let ih = img.size.height
        if iw > 0 && ih > 0 && bounds.width > 0 && bounds.height > 0 {
            // Considera a área disponível dentro da borda (subtraindo o espaço da borda e padding)
            let availableWidth = bounds.width - 4 // 2 pixels de cada lado para a borda e clipping
            let availableHeight = bounds.height - 4 // 2 pixels de cada lado para a borda e clipping
            let fitScale = min(availableWidth / iw, availableHeight / ih)
            
            // Marca como atualização programática para evitar callback loop
            isUpdatingProgrammatically = true
            scale = fitScale
            offset = .zero
            isUpdatingProgrammatically = false
            
            needsDisplay = true
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let img = image else { return }
        
        // Verifica se estamos na main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.needsDisplay = true
            }
            return
        }
        
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
        
        // Só chama notifyChanges se não estamos atualizando programaticamente
        if !isUpdatingProgrammatically {
            notifyChanges()
        }
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
        
        // Só chama notifyChanges se não estamos atualizando programaticamente
        if !isUpdatingProgrammatically {
            notifyChanges()
        }
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
