//
//  TerminalMetalView.swift
//  VibeTerminal
//
//  Metal 终端渲染视图 (macOS 版本)
//  完整实现：字形缓存、光标渲染、增量更新、颜色支持
//

import SwiftUI
import MetalKit

// MARK: - SwiftUI NSViewRepresentable

struct TerminalMetalView: NSViewRepresentable {
    @ObservedObject var viewModel: TerminalViewModel

    func makeNSView(context: Context) -> TerminalMTKView {
        let mtkView = TerminalMTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false
        mtkView.preferredFramesPerSecond = 60
        mtkView.clearColor = MTLClearColor(red: 0.11, green: 0.11, blue: 0.11, alpha: 1.0)
        mtkView.viewModel = viewModel

        context.coordinator.mtkView = mtkView

        return mtkView
    }

    func updateNSView(_ nsView: TerminalMTKView, context: Context) {
        context.coordinator.needsRender = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator: NSObject, MTKViewDelegate {
        var viewModel: TerminalViewModel
        var mtkView: TerminalMTKView?
        var renderer: TerminalMetalRenderer?
        var needsRender: Bool = true
        private var fontScaleObserver: Any?

        init(viewModel: TerminalViewModel) {
            self.viewModel = viewModel
            super.init()

            // 监听字体缩放变化
            fontScaleObserver = NotificationCenter.default.addObserver(
                forName: .init("TerminalFontScaleChanged"), object: nil, queue: .main
            ) { [weak self] notif in
                guard let self = self,
                      let scale = notif.userInfo?["scale"] as? CGFloat,
                      let view = self.mtkView else { return }
                self.renderer?.fontScale = scale
                self.recalculateGridSize(for: view.drawableSize)
                self.needsRender = true
            }
        }

        deinit {
            if let obs = fontScaleObserver {
                NotificationCenter.default.removeObserver(obs)
            }
        }

        private var resizeDebounceTimer: Timer?
        private var isResizing = false

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // 拖动中：暂停 MTKView 绘制，内容冻结不拉伸
            view.isPaused = true
            isResizing = true

            resizeDebounceTimer?.invalidate()
            resizeDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.isResizing = false
                self.renderer?.updateDrawableSize(view.drawableSize)
                self.recalculateGridSize(for: view.drawableSize)
                self.needsRender = true
                // 恢复绘制
                view.isPaused = false
            }
        }

        private func recalculateGridSize(for size: CGSize) {
            guard let r = renderer else { return }
            let gw = r.cellPixelWidth
            let gh = r.cellPixelHeight
            guard gw > 0, gh > 0 else { return }

            let newCols = max(10, Int(size.width / gw))
            let newRows = max(4, Int(size.height / gh))
            let state = viewModel.terminalState
            guard newCols != state.cols || newRows != state.rows else { return }

            viewModel.resize(cols: newCols, rows: newRows)
            NotificationCenter.default.post(
                name: .init("TerminalResize"),
                object: nil,
                userInfo: ["cols": newCols, "rows": newRows]
            )
            needsRender = true
        }

        func draw(in view: MTKView) {
            if renderer == nil, let device = view.device {
                renderer = TerminalMetalRenderer(device: device, viewModel: viewModel)
                // 应用保存的字体缩放
                let savedScale = UserDefaults.standard.double(forKey: "terminalFontScale")
                if savedScale > 0 {
                    renderer?.fontScale = CGFloat(savedScale)
                }
                renderer?.updateDrawableSize(view.drawableSize)
                // 初始 resize
                mtkView(view, drawableSizeWillChange: view.drawableSize)
            }

            if !isResizing && (needsRender || viewModel.hasPendingUpdates) {
                renderer?.render(in: view)
                needsRender = false
                viewModel.clearPendingUpdates()
            }
        }
    }
}

// MARK: - 支持鼠标选择的 MTKView 子类

class TerminalMTKView: MTKView {
    weak var viewModel: TerminalViewModel?

    // 选区状态
    private var selectionStart: (col: Int, row: Int)?
    private var selectionEnd: (col: Int, row: Int)?
    private var isDragging = false

    override var acceptsFirstResponder: Bool { true }

    // 像素坐标 → 单元格坐标
    private func cellAt(point: NSPoint) -> (col: Int, row: Int)? {
        guard let vm = viewModel else { return nil }
        let cols = vm.terminalState.cols
        let rows = vm.terminalState.rows
        guard cols > 0, rows > 0 else { return nil }

        let cellW = bounds.width / CGFloat(cols)
        let cellH = bounds.height / CGFloat(rows)

        let col = Int(point.x / cellW)
        let row = Int((bounds.height - point.y) / cellH) // 翻转 Y

        return (col: max(0, min(col, cols - 1)), row: max(0, min(row, rows - 1)))
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let cell = cellAt(point: point) else { return }

        selectionStart = cell
        selectionEnd = cell
        isDragging = true

        viewModel?.setSelection(start: cell, end: cell)
        viewModel?.hasPendingUpdates = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let cell = cellAt(point: point) else { return }

        selectionEnd = cell
        if let start = selectionStart {
            viewModel?.setSelection(start: start, end: cell)
            viewModel?.hasPendingUpdates = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }

    // Cmd+C 复制选中文字
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            copySelection()
            return
        }
        // Escape 清除选区
        if event.keyCode == 53 {
            viewModel?.clearSelection()
            viewModel?.hasPendingUpdates = true
            return
        }
        super.keyDown(with: event)
    }

    private func copySelection() {
        guard let vm = viewModel,
              let sel = vm.selection else { return }

        var text = ""
        let state = vm.terminalState

        let startRow = min(sel.startRow, sel.endRow)
        let endRow = max(sel.startRow, sel.endRow)

        for row in startRow...endRow {
            let startCol: Int
            let endCol: Int

            if startRow == endRow {
                startCol = min(sel.startCol, sel.endCol)
                endCol = max(sel.startCol, sel.endCol)
            } else if row == startRow {
                startCol = (sel.startRow < sel.endRow) ? sel.startCol : sel.endCol
                endCol = state.cols - 1
            } else if row == endRow {
                startCol = 0
                endCol = (sel.startRow < sel.endRow) ? sel.endCol : sel.startCol
            } else {
                startCol = 0
                endCol = state.cols - 1
            }

            for col in startCol...endCol {
                if let cell = state.getCell(x: col, y: row) {
                    text.append(cell.char)
                }
            }
            if row < endRow {
                text.append("\n")
            }
        }

        // 去掉尾部空格
        let trimmed = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
            .joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
    }
}

// MARK: - Terminal View Model

class TerminalViewModel: ObservableObject {
    @Published var terminalState: TerminalState
    @Published var cursorPosition: CGPoint = .zero
    @Published var isConnected = false
    @Published var fps: Double = 0

    var hasPendingUpdates: Bool = false

    // 选区
    struct Selection {
        var startCol: Int
        var startRow: Int
        var endCol: Int
        var endRow: Int
    }
    var selection: Selection?

    func setSelection(start: (col: Int, row: Int), end: (col: Int, row: Int)) {
        selection = Selection(startCol: start.col, startRow: start.row, endCol: end.col, endRow: end.row)
    }

    func clearSelection() {
        selection = nil
    }

    func isCellSelected(col: Int, row: Int) -> Bool {
        guard let sel = selection else { return false }
        let minRow = min(sel.startRow, sel.endRow)
        let maxRow = max(sel.startRow, sel.endRow)
        guard row >= minRow && row <= maxRow else { return false }

        if minRow == maxRow {
            let minCol = min(sel.startCol, sel.endCol)
            let maxCol = max(sel.startCol, sel.endCol)
            return col >= minCol && col <= maxCol
        } else if row == minRow {
            let startCol = (sel.startRow < sel.endRow) ? sel.startCol : sel.endCol
            return col >= startCol
        } else if row == maxRow {
            let endCol = (sel.startRow < sel.endRow) ? sel.endCol : sel.startCol
            return col <= endCol
        }
        return true // 中间行全选
    }

    init(cols: Int = 80, rows: Int = 24) {
        self.terminalState = TerminalState(cols: cols, rows: rows)
    }

    // MARK: - 内容更新

    func updateCell(char: Character, x: Int, y: Int,
                   fgColor: SIMD4<UInt8>? = nil, bgColor: SIMD4<UInt8>? = nil,
                   attrs: UInt16? = nil) {
        var cell = terminalState.getCell(x: x, y: y) ?? TerminalCell()
        cell.char = char
        if let fg = fgColor { cell.fgColor = fg }
        if let bg = bgColor { cell.bgColor = bg }
        if let attr = attrs { cell.attrs = attr }
        terminalState.setCell(cell, atX: x, y: y)
        hasPendingUpdates = true
    }

    func updateLine(cells: [TerminalCell], y: Int) {
        for (x, cell) in cells.enumerated() {
            terminalState.setCell(cell, atX: x, y: y)
        }
        hasPendingUpdates = true
    }

    func clearScreen() {
        terminalState.clearScreen()
        hasPendingUpdates = true
    }

    func resize(cols: Int, rows: Int) {
        terminalState.resize(cols: cols, rows: rows)
        hasPendingUpdates = true
    }

    // MARK: - 光标操作

    func moveCursor(x: Int, y: Int) {
        terminalState.setCursor(x: x, y: y)
        let info = terminalState.getCursorInfo()
        cursorPosition = CGPoint(x: info.x, y: info.y)
        hasPendingUpdates = true
    }

    func setCursorVisible(_ visible: Bool) {
        terminalState.setCursorVisible(visible)
        hasPendingUpdates = true
    }

    func setCursorStyle(_ style: CursorInfo.CursorStyle) {
        terminalState.setCursorStyle(style)
        hasPendingUpdates = true
    }

    // MARK: - 批量更新

    func updateAllCells(_ cells: [[TerminalCell]], cols: Int, rows: Int) {
        terminalState.importAllCells(cells, cols: cols, rows: rows)
        hasPendingUpdates = true
    }

    func updateFPS(_ fps: Double) {
        self.fps = fps
    }

    func clearPendingUpdates() {
        hasPendingUpdates = false
    }

    // MARK: - 输入通知

    func notifyInputReceived() {
        hasPendingUpdates = true
    }

    // MARK: - 会话连接

    private var ptySession: PTYSession?
    private var sessionDelegate: TerminalViewModelDelegate?

    func connect(session: PTYSession) {
        self.ptySession = session
        // 创建并保存委托，防止被释放
        let delegate = TerminalViewModelDelegate(viewModel: self)
        self.sessionDelegate = delegate
        session.delegate = delegate
    }

    func disconnect() {
        ptySession = nil
        sessionDelegate = nil
        isConnected = false
    }
}

// MARK: - 终端视图模型委托

class TerminalViewModelDelegate: PTYSessionDelegate {
    weak var viewModel: TerminalViewModel?

    init(viewModel: TerminalViewModel) {
        self.viewModel = viewModel
    }

    func session(_ session: PTYSession, didReceiveFrame frame: TerminalFrame) {
        // 更新终端状态
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let viewModel = self.viewModel else { return }

            // 应用帧到终端状态
            for cell in frame.cells {
                let x = Int(cell.x)
                let y = Int(cell.y)
                if x < viewModel.terminalState.cols && y < viewModel.terminalState.rows {
                    let fgColor = SIMD4<UInt8>(cell.fgR, cell.fgG, cell.fgB, 255)
                    let bgColor = SIMD4<UInt8>(cell.bgR, cell.bgG, cell.bgB, 255)
                    viewModel.updateCell(
                        char: cell.char.first ?? " ",
                        x: x,
                        y: y,
                        fgColor: fgColor,
                        bgColor: bgColor,
                        attrs: cell.attrs
                    )
                }
            }

            // 更新光标位置
            viewModel.cursorPosition = CGPoint(
                x: CGFloat(frame.cursorX),
                y: CGFloat(frame.cursorY)
            )
        }
    }

    func session(_ session: PTYSession, didChangeState state: PTYSession.State) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .connected:
                self?.viewModel?.isConnected = true
            case .disconnected, .failed:
                self?.viewModel?.isConnected = false
            default:
                break
            }
        }
    }

    func session(_ session: PTYSession, didReceiveError error: Error) {
        print("PTY Session error: \(error)")
    }
}

// MARK: - Metal Renderer

class TerminalMetalRenderer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    // 字体缩放因子（1.0 = 默认，>1 放大，<1 缩小）
    var fontScale: CGFloat = 1.0

    // 字体的像素尺寸（乘以缩放因子）
    var cellPixelWidth: CGFloat { glyphCache.glyphWidth * fontScale }
    var cellPixelHeight: CGFloat { glyphCache.glyphHeight * fontScale }
    private var pipelineState: MTLRenderPipelineState?
    private var cursorPipelineState: MTLRenderPipelineState?

    // 字形缓存
    private let glyphCache: GlyphCache

    // 纹理采样器
    private var samplerState: MTLSamplerState?

    // 顶点和实例缓冲
    private var vertexBuffer: MTLBuffer
    private var instanceBuffer: MTLBuffer
    private var cursorVertexBuffer: MTLBuffer
    private var cursorInstanceBuffer: MTLBuffer

    // 顶点数据结构
    struct Vertex {
        var position: SIMD2<Float>
        var uv: SIMD2<Float>
    }

    // 实例数据结构（匹配着色器）
    struct Instance {
        var position: SIMD2<Float>    // 屏幕位置（归一化）
        var size: SIMD2<Float>         // 字符大小（归一化）
        var uvRect: SIMD4<Float>       // 纹理坐标 (x, y, w, h)
        var fgColor: SIMD4<Float>      // 前景色
        var bgColor: SIMD4<Float>      // 背景色
        var attrs: UInt32              // 属性标志
    }

    // 光标实例数据
    struct CursorInstance {
        var position: SIMD2<Float>
        var size: SIMD2<Float>
        var color: SIMD4<Float>
        var style: UInt32
    }

    // 渲染参数
    private let maxInstances: Int
    private(set) var drawableSize: CGSize = .zero
    private var needsFullRender: Bool = true

    // 性能统计
    private var frameCount: UInt64 = 0
    private var lastFrameTime: CFAbsoluteTime = 0
    private var currentFPS: Double = 0

    // ViewModel 引用
    private weak var viewModel: TerminalViewModel?

    init?(device: MTLDevice, viewModel: TerminalViewModel) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.viewModel = viewModel

        // 根据预期终端大小计算最大实例数
        let maxCols = 200
        let maxRows = 100
        self.maxInstances = maxCols * maxRows

        // 初始化字形缓存
        guard let cache = GlyphCache(device: device) else {
            return nil
        }
        self.glyphCache = cache

        // 创建基础四边形顶点（左下、右下、左上、右上）
        let quadVertices: [Vertex] = [
            Vertex(position: SIMD2(0, 0), uv: SIMD2(0, 1)),   // 左下
            Vertex(position: SIMD2(1, 0), uv: SIMD2(1, 1)),   // 右下
            Vertex(position: SIMD2(0, 1), uv: SIMD2(0, 0)),   // 左上
            Vertex(position: SIMD2(1, 1), uv: SIMD2(1, 0)),   // 右上
        ]

        guard let vBuffer = device.makeBuffer(bytes: quadVertices,
                                              length: quadVertices.count * MemoryLayout<Vertex>.stride,
                                              options: []) else {
            return nil
        }
        self.vertexBuffer = vBuffer

        // 创建实例缓冲
        let instanceSize = maxInstances * MemoryLayout<Instance>.stride
        guard let iBuffer = device.makeBuffer(length: instanceSize, options: []) else {
            return nil
        }
        self.instanceBuffer = iBuffer

        // 创建光标顶点缓冲（复用四边形）
        self.cursorVertexBuffer = vBuffer

        // 创建光标实例缓冲
        guard let ciBuffer = device.makeBuffer(length: MemoryLayout<CursorInstance>.stride, options: []) else {
            return nil
        }
        self.cursorInstanceBuffer = ciBuffer

        // 设置渲染管线
        setupPipelines()
    }

    private func setupPipelines() {
        guard let library = Self.loadMetalLibrary(device: device) else {
            print("Failed to create Metal library")
            return
        }

        let vertexFunction = library.makeFunction(name: "vertex_main")
        let fragmentFunction = library.makeFunction(name: "fragment_main")

        // 字符渲染管线
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Terminal Character Pipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Alpha 混合设置
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        // 顶点描述符
        let vertexDescriptor = buildVertexDescriptor()
        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }

        // 光标渲染管线
        let cursorVertexFunction = library.makeFunction(name: "vertex_cursor")
        let cursorFragmentFunction = library.makeFunction(name: "fragment_cursor")

        let cursorPipelineDescriptor = MTLRenderPipelineDescriptor()
        cursorPipelineDescriptor.label = "Cursor Pipeline"
        cursorPipelineDescriptor.vertexFunction = cursorVertexFunction
        cursorPipelineDescriptor.fragmentFunction = cursorFragmentFunction
        cursorPipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        cursorPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        cursorPipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        cursorPipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        cursorPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        cursorPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        cursorPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        cursorPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        let cursorVertexDescriptor = buildCursorVertexDescriptor()
        cursorPipelineDescriptor.vertexDescriptor = cursorVertexDescriptor

        do {
            cursorPipelineState = try device.makeRenderPipelineState(descriptor: cursorPipelineDescriptor)
        } catch {
            print("Failed to create cursor pipeline state: \(error)")
        }

        // 创建纹理采样器
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .nearest
        samplerDescriptor.magFilter = .nearest
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        self.samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
    }

    private func buildVertexDescriptor() -> MTLVertexDescriptor {
        let vertexDescriptor = MTLVertexDescriptor()

        // Buffer 0: 基础顶点
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0

        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0

        vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        // Buffer 1: 实例数据 — 通过 shader 的 constant* 直接读取，不需要 vertex descriptor

        return vertexDescriptor
    }

    private func buildCursorVertexDescriptor() -> MTLVertexDescriptor {
        let vertexDescriptor = MTLVertexDescriptor()

        // Buffer 0: 基础顶点
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0

        vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        // Buffer 1: 光标实例 — 通过 shader 的 constant* 直接读取

        return vertexDescriptor
    }

    private func writeDiag(_ msg: String) {
        let path = "/tmp/vibing-render-diag.log"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(msg.data(using: .utf8)!)
            fh.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: msg.data(using: .utf8))
        }
    }

    /// 加载 Metal shader library - 支持 SPM bundle 资源
    private static func loadMetalLibrary(device: MTLDevice) -> MTLLibrary? {
        // 1. 尝试默认 library (Xcode 编译的 .metallib)
        if let library = device.makeDefaultLibrary() {
            return library
        }

        // 2. 尝试从 SPM bundle 加载 .metal 源码并编译
        if let shaderURL = Bundle.module.url(forResource: "Shaders", withExtension: "metal") {
            do {
                let source = try String(contentsOf: shaderURL, encoding: .utf8)
                let library = try device.makeLibrary(source: source, options: nil)
                return library
            } catch {
                print("Failed to compile Metal shaders from source: \(error)")
            }
        }

        // 3. 尝试从文件系统加载
        let possiblePaths = [
            Bundle.main.bundlePath + "/Resources/Shaders.metal",
            Bundle.main.bundlePath + "/../Resources/Shaders.metal",
        ]
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                do {
                    let source = try String(contentsOfFile: path, encoding: .utf8)
                    let library = try device.makeLibrary(source: source, options: nil)
                    return library
                } catch {
                    print("Failed to compile Metal shaders from \(path): \(error)")
                }
            }
        }

        print("No Metal shader library found")
        return nil
    }

    /// 更新 drawable 大小
    func updateDrawableSize(_ size: CGSize) {
        if drawableSize != size {
            drawableSize = size
            needsFullRender = true
        }
    }

    private var diagDone = false

    func render(in view: MTKView) {
        guard let state = viewModel?.terminalState else {
            writeDiag("render: NO viewModel or terminalState\n")
            return
        }

        // 一次性诊断
        if !diagDone {
            diagDone = true
            var diag = "=== RENDER DIAGNOSTIC ===\n"
            diag += "drawableSize: \(view.drawableSize)\n"
            diag += "state: cols=\(state.cols) rows=\(state.rows)\n"
            diag += "pipelineState: \(pipelineState != nil)\n"
            diag += "cursorPipelineState: \(cursorPipelineState != nil)\n"
            diag += "samplerState: \(samplerState != nil)\n"
            diag += "glyphCache.texture: \(glyphCache.texture.width)x\(glyphCache.texture.height)\n"

            // 检查前几个 cell
            for y in 0..<min(3, state.rows) {
                for x in 0..<min(10, state.cols) {
                    if let cell = state.getCell(x: x, y: y) {
                        if cell.char != " " {
                            diag += "cell[\(x),\(y)]: char='\(cell.char)' fg=\(cell.fgColor) bg=\(cell.bgColor)\n"
                        }
                    }
                }
            }

            // 检查 glyph cache
            let spaceUV = glyphCache.getUVRect(for: " ")
            let aUV = glyphCache.getUVRect(for: "a")
            diag += "glyph ' ': uv=\(spaceUV)\n"
            diag += "glyph 'a': uv=\(aUV)\n"

            // 构建实例看看
            let instances = buildInstances(from: state)
            diag += "instances count: \(instances.count)\n"
            if let first = instances.first {
                diag += "first instance: pos=\(first.position) size=\(first.size) uv=\(first.uvRect) fg=\(first.fgColor) bg=\(first.bgColor)\n"
            }
            // 找第一个非空格
            if let nonSpace = instances.first(where: { $0.uvRect != spaceUV }) {
                diag += "first non-space: pos=\(nonSpace.position) uv=\(nonSpace.uvRect) fg=\(nonSpace.fgColor) bg=\(nonSpace.bgColor)\n"
            }

            diag += "=== END ===\n"
            writeDiag(diag)
        }

        updateDrawableSize(view.drawableSize)

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        // 渲染字符
        if let pipeline = pipelineState {
            renderEncoder.setRenderPipelineState(pipeline)

            // 获取脏区域并构建实例数据
            let dirtyRegions = state.getAndClearDirtyCellRegions()

            let instances: [Instance]
            if needsFullRender || dirtyRegions.isEmpty {
                // 全屏渲染
                instances = buildInstances(from: state)
                needsFullRender = false
            } else {
                // 只渲染脏区域
                instances = buildInstancesForDirtyRegions(dirtyRegions, from: state)
            }

            if !instances.isEmpty {
                instances.withUnsafeBufferPointer { buffer in
                    memcpy(instanceBuffer.contents(), buffer.baseAddress!, buffer.count * MemoryLayout<Instance>.stride)
                }

                renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                renderEncoder.setVertexBuffer(instanceBuffer, offset: 0, index: 1)
                renderEncoder.setFragmentTexture(glyphCache.texture, index: 0)
                if let sampler = samplerState {
                    renderEncoder.setFragmentSamplerState(sampler, index: 0)
                }

                renderEncoder.drawPrimitives(type: .triangleStrip,
                                            vertexStart: 0,
                                            vertexCount: 4,
                                            instanceCount: instances.count)
            }
        }

        // 渲染光标
        if let cursorPipeline = cursorPipelineState {
            let cursorInfo = state.getCursorInfo()
            if cursorInfo.visible {
                renderEncoder.setRenderPipelineState(cursorPipeline)

                var cursorInstance = buildCursorInstance(from: state)
                withUnsafeBytes(of: &cursorInstance) { buffer in
                    memcpy(cursorInstanceBuffer.contents(), buffer.baseAddress!, MemoryLayout<CursorInstance>.stride)
                }

                renderEncoder.setVertexBuffer(cursorVertexBuffer, offset: 0, index: 0)
                renderEncoder.setVertexBuffer(cursorInstanceBuffer, offset: 0, index: 1)

                renderEncoder.drawPrimitives(type: .triangleStrip,
                                            vertexStart: 0,
                                            vertexCount: 4,
                                            instanceCount: 1)
            }
        }

        renderEncoder.endEncoding()

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()

        // 更新 FPS
        updateFPS()
    }

    // MARK: - Instance Building

    private func buildInstances(from state: TerminalState) -> [Instance] {
        var instances: [Instance] = []
        instances.reserveCapacity(state.cols * state.rows)

        // 用字体像素尺寸占 drawable 比例，保持正确宽高比
        let cellWidth: CGFloat
        let cellHeight: CGFloat
        if drawableSize.width > 0 && drawableSize.height > 0 {
            cellWidth = glyphCache.glyphWidth / drawableSize.width
            cellHeight = glyphCache.glyphHeight / drawableSize.height
        } else {
            cellWidth = 1.0 / CGFloat(state.cols)
            cellHeight = 1.0 / CGFloat(state.rows)
        }

        for y in 0..<state.rows {
            for x in 0..<state.cols {
                guard let cell = state.getCell(x: x, y: y) else { continue }

                // 像素对齐：先算像素坐标再归一化，避免亚像素抖动
                let pixelX = floor(CGFloat(x) * glyphCache.glyphWidth)
                let pixelY = floor(CGFloat(y) * glyphCache.glyphHeight)
                let posX = drawableSize.width > 0 ? pixelX / drawableSize.width : CGFloat(x) * cellWidth
                let posY = drawableSize.height > 0 ? pixelY / drawableSize.height : CGFloat(y) * cellHeight

                let uvRect = glyphCache.getUVRect(for: cell.char)

                var fg = rgbToFloat(cell.fgColor)
                var bg = rgbToFloat(cell.bgColor)

                // 选中的 cell 反转前景/背景
                if let vm = viewModel, vm.isCellSelected(col: x, row: y) {
                    let tmp = fg
                    fg = bg
                    bg = tmp
                    // 高亮选区背景
                    bg = SIMD4<Float>(0.2, 0.4, 0.8, 1.0)
                    fg = SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
                }

                let instance = Instance(
                    position: SIMD2(Float(posX), Float(posY)),
                    size: SIMD2(Float(cellWidth), Float(cellHeight)),
                    uvRect: uvRect,
                    fgColor: fg,
                    bgColor: bg,
                    attrs: UInt32(cell.attrs)
                )
                instances.append(instance)
            }
        }

        return instances
    }

    private func buildInstancesForDirtyRegions(_ regions: [DirtyRegion], from state: TerminalState) -> [Instance] {
        var instances: [Instance] = []

        let estimatedCells = regions.reduce(0) { $0 + $1.width * $1.height }
        instances.reserveCapacity(min(estimatedCells, state.cols * state.rows))

        let cellWidth = 1.0 / CGFloat(state.cols)
        let cellHeight = 1.0 / CGFloat(state.rows)

        for region in regions {
            let maxX = min(region.x + region.width, state.cols)
            let maxY = min(region.y + region.height, state.rows)

            for y in region.y..<maxY {
                for x in region.x..<maxX {
                    guard let cell = state.getCell(x: x, y: y) else { continue }

                    let posX = CGFloat(x) * cellWidth
                    let posY = CGFloat(y) * cellHeight

                    let uvRect = glyphCache.getUVRect(for: cell.char)

                    let instance = Instance(
                        position: SIMD2(Float(posX), Float(posY)),
                        size: SIMD2(Float(cellWidth), Float(cellHeight)),
                        uvRect: uvRect,
                        fgColor: rgbToFloat(cell.fgColor),
                        bgColor: rgbToFloat(cell.bgColor),
                        attrs: UInt32(cell.attrs)
                    )
                    instances.append(instance)
                }
            }
        }

        return instances
    }

    private func buildCursorInstance(from state: TerminalState) -> CursorInstance {
        let cellWidth = 1.0 / CGFloat(state.cols)
        let cellHeight = 1.0 / CGFloat(state.rows)

        let info = state.getCursorInfo()
        let posX = CGFloat(info.x) * cellWidth
        let posY = CGFloat(info.y) * cellHeight

        // 光标颜色
        let cursorColor: SIMD4<Float>
        if let cell = state.getCell(x: info.x, y: info.y) {
            let fg = rgbToFloat(cell.fgColor)
            cursorColor = SIMD4(1.0 - fg[0],
                                1.0 - fg[1],
                                1.0 - fg[2],
                                0.8)
        } else {
            cursorColor = SIMD4(1.0, 1.0, 1.0, 0.8)
        }

        // 样式转换
        let style: UInt32
        switch info.style {
        case .block: style = 0
        case .underline: style = 1
        case .bar: style = 2
        }

        return CursorInstance(
            position: SIMD2(Float(posX), Float(posY)),
            size: SIMD2(Float(cellWidth), Float(cellHeight)),
            color: cursorColor,
            style: style
        )
    }

    // MARK: - Utility

    private func rgbToFloat(_ color: SIMD4<UInt8>) -> SIMD4<Float> {
        return SIMD4(
            Float(color[0]) / 255.0,
            Float(color[1]) / 255.0,
            Float(color[2]) / 255.0,
            Float(color[3]) / 255.0
        )
    }

    private func updateFPS() {
        let now = CFAbsoluteTimeGetCurrent()
        frameCount += 1

        if now - lastFrameTime >= 1.0 {
            currentFPS = Double(frameCount)
            frameCount = 0
            lastFrameTime = now

            DispatchQueue.main.async {
                self.viewModel?.updateFPS(self.currentFPS)
            }
        }
    }
}

// MARK: - Glyph Cache (产品级版本 - 大容量 + 多纹理支持)

class GlyphCache {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private(set) var texture: MTLTexture

    // 纹理配置
    private let atlasSize: Int = 4096
    // 字形尺寸 — 基于字体真实尺寸（宽 ≠ 高）
    private(set) var glyphWidth: CGFloat = 1
    private(set) var glyphHeight: CGFloat = 1
    // 兼容旧代码
    private var glyphSize: CGFloat { glyphHeight }
    private let maxGlyphs: Int

    // UV 坐标缓存 - 使用并发安全字典
    private var uvCache: [Character: SIMD4<Float>] = [:]
    private let cacheLock = NSLock()

    // 字体
    private var font: CTFont
    private var fontAttributes: [NSAttributedString.Key: Any]

    // 下一个可用的位置
    private var nextX: Int = 0
    private var nextY: Int = 0

    // 预渲染的字符范围
    private let asciiRange: ClosedRange<UInt32> = 32...126

    // 异步上传队列
    private var pendingUploads: [(char: Character, x: Int, y: Int, pixels: [UInt8])] = []
    private let uploadQueue = DispatchQueue(label: "com.vibeterminal.glyphcache.upload", qos: .userInitiated)
    private var isUploading = false

    // CPU 端像素数据缓存（用于立即读取）
    private var pixelData: [Character: [UInt8]] = [:]

    // 默认字符（当缓存未命中时使用）
    private static let defaultUV = SIMD4<Float>(0, 0, 0, 0)

    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            return nil
        }
        self.commandQueue = queue
        // 创建字体 — 用较大尺寸渲染以获得清晰度
        let fontSize: CGFloat = 28
        let menloFont = NSFont(name: "Menlo", size: fontSize)
            ?? NSFont(name: "Courier", size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        self.font = CTFontCreateWithName(menloFont.fontName as CFString, fontSize, nil)

        // 根据字体真实尺寸计算字形宽高
        let testStr = NSAttributedString(string: "M", attributes: [.font: menloFont])
        let testBounds = testStr.boundingRect(with: CGSize(width: 200, height: 200), options: .usesLineFragmentOrigin)
        self.glyphWidth = ceil(testBounds.width) + 2   // 加 padding 防截断
        self.glyphHeight = ceil(menloFont.ascender - menloFont.descender + menloFont.leading) + 2

        self.maxGlyphs = Int(atlasSize / Int(glyphWidth)) * Int(atlasSize / Int(glyphHeight))
        self.fontAttributes = [
            .font: menloFont,
            .foregroundColor: NSColor.white
        ]

        // 创建纹理集 - 使用 private storageMode 以优化 GPU 访问
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: atlasSize,
            height: atlasSize,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .renderTarget]
        textureDescriptor.storageMode = .shared

        guard let tex = device.makeTexture(descriptor: textureDescriptor) else {
            return nil
        }
        self.texture = tex

        // 初始化并预渲染常用字符（批量处理）
        renderInitialGlyphs()

        // 启动批量上传定时器
        startBatchUploadTimer()
    }

    private func renderInitialGlyphs() {
        // 收集所有需要预渲染的字符
        var charsToPreload: [Character] = []

        // ASCII 可打印字符
        for c: UInt32 in asciiRange {
            if let scalar = UnicodeScalar(c) {
                charsToPreload.append(Character(scalar))
            }
        }

        // 额外的常用 Unicode 字符
        charsToPreload.append(contentsOf: [
            // 拉丁扩展
            "à", "á", "â", "ã", "ä", "å", "æ", "ç", "è", "é", "ê", "ë",
            "ì", "í", "î", "ï", "ð", "ñ", "ò", "ó", "ô", "õ", "ö", "ø",
            "ù", "ú", "û", "ü", "ý", "þ", "ÿ",
            // 符号
            "¡", "¢", "£", "¤", "¥", "¦", "§", "¨", "©", "ª", "«", "¬",
            "®", "¯", "°", "±", "²", "³", "´", "µ", "¶", "·", "¸", "¹",
            "º", "»", "¼", "½", "¾", "¿",
            // 箭头和其他符号
            "←", "↑", "→", "↓", "↔", "↕", "↖", "↗", "↘", "↙",
            "─", "│", "┌", "┐", "└", "┘", "├", "┤", "┬", "┴", "┼",
            "■", "□", "▪", "▫", "▬", "▲", "△", "▴", "▸", "▾", "▿",
            "◆", "◇", "○", "●", "◘", "◙",
            // 货币符号
            "€", "₩", "¥", "£", "¢",
            // 数学符号
            "×", "÷", "±", "∓", "√", "∞", "≈", "≠", "≤", "≥",
            // 引号
            "\u{201C}", "\u{201D}", "\u{2018}", "\u{2019}", "'",
            // 破折号
            "–", "—",
            // 其他
            "…", "•", "°", "©", "®", "™", "§", "¶",
            // 方块绘制字符
            "░", "▒", "▓", "█",
        ] as [Character])

        // 批量渲染预加载字符（使用同步方式，因为这是初始化阶段）
        for char in charsToPreload {
            cacheCharacterSync(char)
        }
    }

    // 启动批量上传定时器
    private func startBatchUploadTimer() {
        // 每 16ms 批量上传一次（约 60fps）
        uploadQueue.asyncAfter(deadline: .now() + 0.016) { [weak self] in
            self?.flushPendingUploads()
            self?.startBatchUploadTimer()
        }
    }

    // 异步批量上传待处理的字形
    private func flushPendingUploads() {
        cacheLock.lock()
        let uploads = pendingUploads
        pendingUploads.removeAll()
        cacheLock.unlock()

        guard !uploads.isEmpty else { return }

        // 批量上传到 GPU
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            return
        }

        for (char, x, y, pixelData) in uploads {
            uploadGlyphPixels(pixelData, to: blitEncoder, at: x, y: y)
        }

        blitEncoder.endEncoding()

        // 异步提交，不等待完成
        commandBuffer.addCompletedHandler { [weak self] _ in
            // 上传完成，可以在这里做清理工作
        }
        commandBuffer.commit()
    }

    // 直接上传像素数据到纹理
    private func uploadGlyphPixels(_ pixels: [UInt8], to blitEncoder: MTLBlitCommandEncoder, at x: Int, y: Int) {
        let gw = Int(glyphWidth)
        let gh = Int(glyphHeight)
        let bytesPerRow = gw * 4
        let bytesPerImage = gw * 4
        let size = MTLSize(width: gw, height: gh, depth: 1)
        let origin = MTLOrigin(x: x, y: y, z: 0)

        pixels.withUnsafeBytes { ptr in
            texture.replace(
                region: MTLRegionMake2D(origin.x, origin.y, size.width, size.height),
                mipmapLevel: 0,
                slice: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: bytesPerRow,
                bytesPerImage: bytesPerImage
            )
        }
    }

    // 同步缓存字符（用于初始化）
    private func cacheCharacterSync(_ char: Character) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if uvCache[char] != nil {
            return
        }

        let gw = Int(glyphWidth)
        let gh = Int(glyphHeight)

        if nextY + gh > atlasSize {
            print("Glyph cache full - cannot cache character: \(char)")
            return
        }

        // 渲染字形并获取像素数据
        if let pixels = renderGlyphToPixels(char) {
            let bytesPerRow = gw * 4
            let bytesPerImage = gw * 4
            let size = MTLSize(width: gw, height: gh, depth: 1)
            let origin = MTLOrigin(x: nextX, y: nextY, z: 0)

            pixels.withUnsafeBytes { ptr in
                texture.replace(
                    region: MTLRegionMake2D(origin.x, origin.y, size.width, size.height),
                    mipmapLevel: 0,
                    slice: 0,
                    withBytes: ptr.baseAddress!,
                    bytesPerRow: bytesPerRow,
                    bytesPerImage: bytesPerImage
                )
            }

            // 缓存像素数据
            pixelData[char] = pixels
        }

        let u = Float(nextX) / Float(atlasSize)
        let v = Float(nextY) / Float(atlasSize)
        let w = Float(glyphWidth) / Float(atlasSize)
        let h = Float(glyphHeight) / Float(atlasSize)

        uvCache[char] = SIMD4(u, v, w, h)

        nextX += gw
        if nextX + gw > atlasSize {
            nextX = 0
            nextY += gh
        }
    }

    // 异步缓存字符（用于运行时）
    private func cacheCharacterAsync(_ char: Character) {
        cacheLock.lock()
        let alreadyCached = uvCache[char] != nil

        // 检查是否有空间（需要检查下一行是否会溢出）
        let gw = Int(glyphWidth)
        let gh = Int(glyphHeight)
        let hasSpace = (nextY + gh) < atlasSize

        if !alreadyCached && hasSpace {
            let x = nextX
            let y = nextY

            let u = Float(nextX) / Float(atlasSize)
            let v = Float(nextY) / Float(atlasSize)
            let w = Float(glyphWidth) / Float(atlasSize)
            let h = Float(glyphHeight) / Float(atlasSize)
            uvCache[char] = SIMD4(u, v, w, h)

            nextX += gw
            if nextX + gw > atlasSize {
                nextX = 0
                nextY += gh
            }
            cacheLock.unlock()

            // 在后台线程生成像素数据
            uploadQueue.async { [weak self] in
                guard let self = self else { return }
                if let pixels = self.renderGlyphToPixels(char) {
                    // 加入待上传队列
                    self.cacheLock.lock()
                    self.pendingUploads.append((char, x, y, pixels))
                    self.pixelData[char] = pixels
                    self.cacheLock.unlock()
                }
            }
        } else {
            cacheLock.unlock()
            // 缓存已满，静默失败（使用空格作为占位符）
        }
    }

    // 渲染字形到像素数据（不直接操作纹理）
    private func renderGlyphToPixels(_ char: Character) -> [UInt8]? {
        let gw = Int(glyphWidth)
        let gh = Int(glyphHeight)
        let size = CGSize(width: CGFloat(gw), height: CGFloat(gh))
        let bitsPerComponent = 8
        let bytesPerRow = gw * 4
        let pixelDataSize = gw * gh * 4

        var pixels = [UInt8](repeating: 0, count: pixelDataSize)

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: &pixels,
            width: gw,
            height: gh,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue  // BGRA for Metal
        ) else {
            return nil
        }

        context.clear(CGRect(origin: .zero, size: size))

        let attrString = NSAttributedString(string: String(char), attributes: fontAttributes)
        let bounds = attrString.boundingRect(with: size, options: .usesLineFragmentOrigin, context: nil)

        let textOrigin = CGPoint(
            x: (size.width - bounds.width) / 2 - bounds.origin.x,
            y: (size.height - bounds.height) / 2
        )

        // 移动绘制位置到字形中心
        context.textPosition = textOrigin
        CTLineDraw(CTLineCreateWithAttributedString(attrString), context)

        return pixels
    }

    func getUVRect(for char: Character) -> SIMD4<Float> {
        // 快速路径：检查是否已缓存
        cacheLock.lock()
        let uv = uvCache[char]
        cacheLock.unlock()

        if let uv = uv {
            return uv
        }

        // 未缓存，尝试异步渲染
        cacheCharacterAsync(char)

        // 返回空格的 UV（作为占位符）
        cacheLock.lock()
        let spaceUV = uvCache[" "]
        cacheLock.unlock()

        return spaceUV ?? Self.defaultUV
    }

    func getFontMetrics() -> (ascent: CGFloat, descent: CGFloat, leading: CGFloat) {
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        return (ascent, descent, leading)
    }

    func getCharWidth(for char: Character) -> CGFloat {
        let unichars = [UniChar](char.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: 1)

        if CTFontGetGlyphsForCharacters(font, unichars, &glyphs, 1) {
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advance, 1)
            return advance.width
        }

        return glyphSize
    }

    func preloadUnicodeRange(_ range: ClosedRange<UInt32>) {
        for c in range {
            if let scalar = UnicodeScalar(c) {
                cacheCharacterSync(Character(scalar))
            }
        }
    }
}

// MARK: - Terminal State

struct TerminalCell {
    var char: Character = " "
    var fgColor: SIMD4<UInt8> = SIMD4(212, 212, 212, 255)
    var bgColor: SIMD4<UInt8> = SIMD4(28, 28, 28, 255)
    var attrs: UInt16 = 0

    struct Attrs {
        static let bold: UInt16 = 1 << 0
        static let dim: UInt16 = 1 << 1
        static let italic: UInt16 = 1 << 2
        static let underline: UInt16 = 1 << 3
        static let blink: UInt16 = 1 << 4
        static let reverse: UInt16 = 1 << 5
        static let hidden: UInt16 = 1 << 6
        static let strikethrough: UInt16 = 1 << 7
    }

    var isBold: Bool { (attrs & Attrs.bold) != 0 }
    var isDim: Bool { (attrs & Attrs.dim) != 0 }
    var isItalic: Bool { (attrs & Attrs.italic) != 0 }
    var isUnderline: Bool { (attrs & Attrs.underline) != 0 }
    var isBlink: Bool { (attrs & Attrs.blink) != 0 }
    var isReverse: Bool { (attrs & Attrs.reverse) != 0 }
    var isHidden: Bool { (attrs & Attrs.hidden) != 0 }
    var isStrikethrough: Bool { (attrs & Attrs.strikethrough) != 0 }
}

struct DirtyRegion {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    func intersects(_ other: DirtyRegion) -> Bool {
        return x < other.x + other.width &&
               x + width > other.x &&
               y < other.y + other.height &&
               y + height > other.y
    }

    func merged(_ other: DirtyRegion) -> DirtyRegion {
        let minX = min(x, other.x)
        let minY = min(y, other.y)
        let maxX = max(x + width, other.x + other.width)
        let maxY = max(y + height, other.y + other.height)
        return DirtyRegion(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

struct CursorInfo {
    var x: Int
    var y: Int
    var visible: Bool = true
    var style: CursorStyle = .block

    enum CursorStyle {
        case block
        case underline
        case bar
    }
}

class TerminalState {
    private(set) var cols: Int
    private(set) var rows: Int
    private(set) var cells: [[TerminalCell]]

    private(set) var cursorX: Int = 0
    private(set) var cursorY: Int = 0
    private(set) var cursorVisible: Bool = true
    private(set) var cursorStyle: CursorInfo.CursorStyle = .block

    var scrollTop: Int = 0
    var scrollBottom: Int = 0

    private var dirtyRegions: [DirtyRegion] = []

    init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        self.cells = Array(repeating: Array(repeating: TerminalCell(), count: cols), count: rows)
        self.scrollBottom = rows - 1
    }

    func resize(cols: Int, rows: Int) {
        var newCells = Array(repeating: Array(repeating: TerminalCell(), count: cols), count: rows)

        let copyRows = min(self.rows, rows)
        let copyCols = min(self.cols, cols)

        for y in 0..<copyRows {
            for x in 0..<copyCols {
                newCells[y][x] = cells[y][x]
            }
        }

        self.cells = newCells
        self.cols = cols
        self.rows = rows
        self.scrollBottom = rows - 1

        cursorX = min(cursorX, cols - 1)
        cursorY = min(cursorY, rows - 1)

        markDirty(DirtyRegion(x: 0, y: 0, width: cols, height: rows))
    }

    func markDirty(_ region: DirtyRegion) {
        var merged = false
        for i in 0..<dirtyRegions.count {
            if dirtyRegions[i].intersects(region) {
                dirtyRegions[i] = dirtyRegions[i].merged(region)
                merged = true
                break
            }
        }
        if !merged {
            dirtyRegions.append(region)
        }
    }

    func markDirty(x: Int, y: Int, width: Int = 1, height: Int = 1) {
        markDirty(DirtyRegion(x: x, y: y, width: width, height: height))
    }

    func getAndClearDirtyCellRegions() -> [DirtyRegion] {
        let regions = dirtyRegions
        dirtyRegions.removeAll()
        return regions
    }

    func clearScreen() {
        for y in 0..<rows {
            for x in 0..<cols {
                cells[y][x] = TerminalCell()
            }
        }
        markDirty(DirtyRegion(x: 0, y: 0, width: cols, height: rows))
    }

    func clearLine(y: Int) {
        guard y < rows else { return }
        for x in 0..<cols {
            cells[y][x] = TerminalCell()
        }
        markDirty(x: 0, y: y, width: cols, height: 1)
    }

    func write(char: Character, atX x: Int, y: Int) {
        guard y < rows, x < cols else { return }
        cells[y][x].char = char
        markDirty(x: x, y: y)
    }

    func setCell(_ cell: TerminalCell, atX x: Int, y: Int) {
        guard y < rows, x < cols else { return }
        cells[y][x] = cell
        markDirty(x: x, y: y)
    }

    func getCell(x: Int, y: Int) -> TerminalCell? {
        guard y < rows, x < cols else { return nil }
        return cells[y][x]
    }

    func setCursor(x: Int, y: Int) {
        let oldX = cursorX
        let oldY = cursorY

        cursorX = max(0, min(x, cols - 1))
        cursorY = max(0, min(y, rows - 1))

        markDirty(x: oldX, y: oldY)
        markDirty(x: cursorX, y: cursorY)
    }

    func setCursorVisible(_ visible: Bool) {
        cursorVisible = visible
        markDirty(x: cursorX, y: cursorY)
    }

    func setCursorStyle(_ style: CursorInfo.CursorStyle) {
        cursorStyle = style
        markDirty(x: cursorX, y: cursorY)
    }

    func getCursorInfo() -> CursorInfo {
        return CursorInfo(x: cursorX, y: cursorY, visible: cursorVisible, style: cursorStyle)
    }

    func scrollUp(amount: Int = 1) {
        let scrollHeight = scrollBottom - scrollTop + 1
        guard amount > 0 && amount < scrollHeight else { return }

        for y in scrollTop..<(scrollBottom - amount + 1) {
            cells[y] = cells[y + amount]
        }

        for y in (scrollBottom - amount + 1)...scrollBottom {
            cells[y] = Array(repeating: TerminalCell(), count: cols)
        }

        markDirty(x: 0, y: scrollTop, width: cols, height: scrollHeight)
    }

    func scrollDown(amount: Int = 1) {
        let scrollHeight = scrollBottom - scrollTop + 1
        guard amount > 0 && amount < scrollHeight else { return }

        for y in stride(from: scrollBottom, through: scrollTop + amount, by: -1) {
            cells[y] = cells[y - amount]
        }

        for y in scrollTop..<(scrollTop + amount) {
            cells[y] = Array(repeating: TerminalCell(), count: cols)
        }

        markDirty(x: 0, y: scrollTop, width: cols, height: scrollHeight)
    }

    func updateRegion(cells: [[TerminalCell]], x: Int, y: Int) {
        let height = cells.count
        let width = cells.first?.count ?? 0

        for dy in 0..<height {
            let targetY = y + dy
            guard targetY < rows else { continue }

            for dx in 0..<width {
                let targetX = x + dx
                guard targetX < cols else { continue }

                self.cells[targetY][targetX] = cells[dy][dx]
            }
        }

        markDirty(x: x, y: y, width: width, height: height)
    }

    func exportAllCells() -> [[TerminalCell]] {
        return cells.map { $0.map { $0 } }
    }

    func importAllCells(_ importedCells: [[TerminalCell]], cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        self.cells = importedCells.map { row in
            Array(row.prefix(cols))
        }

        while cells.count < rows {
            cells.append(Array(repeating: TerminalCell(), count: cols))
        }

        markDirty(DirtyRegion(x: 0, y: 0, width: cols, height: rows))
    }
}

// MARK: - SIMD4 Extension

extension SIMD4 where Scalar == UInt8 {
    var r: Scalar { self[0] }
    var g: Scalar { self[1] }
    var b: Scalar { self[2] }
    var a: Scalar { self[3] }
}

// MARK: - Color Constants

extension TerminalCell {
    static func color(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) -> SIMD4<UInt8> {
        SIMD4(r, g, b, a)
    }

    // ANSI 16 色
    static let black = color(r: 0, g: 0, b: 0)
    static let red = color(r: 205, g: 49, b: 49)
    static let green = color(r: 13, g: 188, b: 121)
    static let yellow = color(r: 229, g: 229, b: 16)
    static let blue = color(r: 36, g: 114, b: 200)
    static let magenta = color(r: 188, g: 63, b: 188)
    static let cyan = color(r: 17, g: 168, b: 205)
    static let white = color(r: 229, g: 229, b: 229)

    // Bright variants
    static let brightBlack = color(r: 102, g: 102, b: 102)
    static let brightRed = color(r: 241, g: 76, b: 76)
    static let brightGreen = color(r: 35, g: 209, b: 139)
    static let brightYellow = color(r: 245, g: 245, b: 67)
    static let brightBlue = color(r: 59, g: 142, b: 234)
    static let brightMagenta = color(r: 211, g: 101, b: 211)
    static let brightCyan = color(r: 41, g: 184, b: 219)
    static let brightWhite = color(r: 255, g: 255, b: 255)
}
