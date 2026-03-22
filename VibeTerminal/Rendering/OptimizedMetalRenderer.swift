//
//  OptimizedMetalRenderer.swift
//  VibeTerminal
//
//  优化的 Metal 渲染器 - 使用持久化实例缓冲和更好的脏区域管理
//
//  性能优化：
//  - 持久化实例缓冲，避免每帧重新分配
//  - 直接写入 GPU 内存，减少 CPU-GPU 拷贝
//  - 优化的脏区域管理
//

import MetalKit

// MARK: - 优化的 Metal 渲染器

final class OptimizedMetalRenderer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var cursorPipelineState: MTLRenderPipelineState?

    // 字形缓存
    private let glyphCache: GlyphCache

    // 持久化缓冲区
    private var vertexBuffer: MTLBuffer
    private var instanceBuffer: MTLBuffer
    private var cursorVertexBuffer: MTLBuffer
    private var cursorInstanceBuffer: MTLBuffer

    // 直接内存访问
    private var instancePointer: UnsafeMutableRawPointer
    private var cursorInstancePointer: UnsafeMutableRawPointer

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

    // 顶点数据结构
    struct Vertex {
        var position: SIMD2<Float>
        var uv: SIMD2<Float>
    }

    // 实例数据结构
    struct Instance {
        var position: SIMD2<Float>
        var size: SIMD2<Float>
        var uvRect: SIMD4<Float>
        var fgColor: SIMD4<Float>
        var bgColor: SIMD4<Float>
        var attrs: UInt32
    }

    // 光标实例数据
    struct CursorInstance {
        var position: SIMD2<Float>
        var size: SIMD2<Float>
        var color: SIMD4<Float>
        var style: UInt32
    }

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

        // 创建基础四边形顶点
        let quadVertices: [Vertex] = [
            Vertex(position: SIMD2(0, 0), uv: SIMD2(0, 1)),
            Vertex(position: SIMD2(1, 0), uv: SIMD2(1, 1)),
            Vertex(position: SIMD2(0, 1), uv: SIMD2(0, 0)),
            Vertex(position: SIMD2(1, 1), uv: SIMD2(1, 0)),
        ]

        guard let vBuffer = device.makeBuffer(bytes: quadVertices,
                                              length: quadVertices.count * MemoryLayout<Vertex>.stride,
                                              options: []) else {
            return nil
        }
        self.vertexBuffer = vBuffer
        self.cursorVertexBuffer = vBuffer

        // 创建持久化实例缓冲区（CPU 可写）
        let instanceSize = maxInstances * MemoryLayout<Instance>.stride
        let instanceResourceOptions: MTLResourceOptions = [.storageModeShared]

        guard let iBuffer = device.makeBuffer(length: instanceSize, options: instanceResourceOptions) else {
            return nil
        }
        self.instanceBuffer = iBuffer
        self.instancePointer = iBuffer.contents()

        // 创建光标实例缓冲区
        guard let ciBuffer = device.makeBuffer(length: MemoryLayout<CursorInstance>.stride, options: instanceResourceOptions) else {
            return nil
        }
        self.cursorInstanceBuffer = ciBuffer
        self.cursorInstancePointer = ciBuffer.contents()

        // 设置渲染管线
        setupPipelines()
    }

    private func setupPipelines() {
        guard let library = device.makeDefaultLibrary() else {
            print("Failed to create Metal library")
            return
        }

        let vertexFunction = library.makeFunction(name: "vertex_main")
        let fragmentFunction = library.makeFunction(name: "fragment_main")

        // 字符渲染管线
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Optimized Terminal Pipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

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
        cursorPipelineDescriptor.label = "Optimized Cursor Pipeline"
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

        // Buffer 1: 实例数据
        vertexDescriptor.attributes[2].format = .float2
        vertexDescriptor.attributes[2].offset = 0
        vertexDescriptor.attributes[2].bufferIndex = 1

        vertexDescriptor.attributes[3].format = .float2
        vertexDescriptor.attributes[3].offset = MemoryLayout<SIMD2<Float>>.stride
        vertexDescriptor.attributes[3].bufferIndex = 1

        vertexDescriptor.attributes[4].format = .float4
        vertexDescriptor.attributes[4].offset = MemoryLayout<SIMD2<Float>>.stride * 2
        vertexDescriptor.attributes[4].bufferIndex = 1

        vertexDescriptor.attributes[5].format = .float4
        vertexDescriptor.attributes[5].offset = MemoryLayout<SIMD2<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride
        vertexDescriptor.attributes[5].bufferIndex = 1

        vertexDescriptor.attributes[6].format = .float4
        vertexDescriptor.attributes[6].offset = MemoryLayout<SIMD2<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride * 2
        vertexDescriptor.attributes[6].bufferIndex = 1

        vertexDescriptor.attributes[7].format = .uint
        vertexDescriptor.attributes[7].offset = MemoryLayout<SIMD2<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride * 3
        vertexDescriptor.attributes[7].bufferIndex = 1

        vertexDescriptor.layouts[1].stride = MemoryLayout<Instance>.stride
        vertexDescriptor.layouts[1].stepFunction = .perInstance

        return vertexDescriptor
    }

    private func buildCursorVertexDescriptor() -> MTLVertexDescriptor {
        let vertexDescriptor = MTLVertexDescriptor()

        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0

        vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = 0
        vertexDescriptor.attributes[1].bufferIndex = 1

        vertexDescriptor.attributes[2].format = .float2
        vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD2<Float>>.stride
        vertexDescriptor.attributes[2].bufferIndex = 1

        vertexDescriptor.attributes[3].format = .float4
        vertexDescriptor.attributes[3].offset = MemoryLayout<SIMD2<Float>>.stride * 2
        vertexDescriptor.attributes[3].bufferIndex = 1

        vertexDescriptor.attributes[4].format = .uint
        vertexDescriptor.attributes[4].offset = MemoryLayout<SIMD2<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride
        vertexDescriptor.attributes[4].bufferIndex = 1

        vertexDescriptor.layouts[1].stride = MemoryLayout<CursorInstance>.stride
        vertexDescriptor.layouts[1].stepFunction = .perInstance

        return vertexDescriptor
    }

    /// 更新 drawable 大小
    func updateDrawableSize(_ size: CGSize) {
        if drawableSize != size {
            drawableSize = size
            needsFullRender = true
        }
    }

    func render(in view: MTKView) {
        guard let state = viewModel?.terminalState else { return }

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

            let dirtyRegions = state.getAndClearDirtyCellRegions()
            let instanceCount: Int

            if needsFullRender || dirtyRegions.isEmpty {
                instanceCount = buildAllInstances(from: state)
                needsFullRender = false
            } else {
                instanceCount = buildDirtyInstances(dirtyRegions, from: state)
            }

            if instanceCount > 0 {
                renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                renderEncoder.setVertexBuffer(instanceBuffer, offset: 0, index: 1)
                renderEncoder.setFragmentTexture(glyphCache.texture, index: 0)

                renderEncoder.drawPrimitives(type: .triangleStrip,
                                            vertexStart: 0,
                                            vertexCount: 4,
                                            instanceCount: instanceCount)
            }
        }

        // 渲染光标
        if let cursorPipeline = cursorPipelineState {
            let cursorInfo = state.getCursorInfo()
            if cursorInfo.visible {
                renderEncoder.setRenderPipelineState(cursorPipeline)

                buildCursorInstance(from: state)

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

        updateFPS()
    }

    // MARK: - 优化的实例构建

    /// 直接写入 GPU 内存构建所有实例
    @inline(__always)
    private func buildAllInstances(from state: TerminalState) -> Int {
        let cellWidth = 1.0 / Float(state.cols)
        let cellHeight = 1.0 / Float(state.rows)

        var count = 0
        let basePtr = instancePointer.assumingMemoryBound(to: Instance.self)

        for y in 0..<state.rows {
            let posY = Float(y) * cellHeight

            for x in 0..<state.cols {
                guard let cell = state.getCell(x: x, y: y) else { continue }

                let posX = Float(x) * cellWidth
                let uvRect = glyphCache.getUVRect(for: cell.char)

                basePtr[count] = Instance(
                    position: SIMD2(posX, posY),
                    size: SIMD2(cellWidth, cellHeight),
                    uvRect: uvRect,
                    fgColor: rgbToFloat(cell.fgColor),
                    bgColor: rgbToFloat(cell.bgColor),
                    attrs: UInt32(cell.attrs)
                )
                count += 1
            }
        }

        return count
    }

    /// 只构建脏区域的实例
    @inline(__always)
    private func buildDirtyInstances(_ regions: [DirtyRegion], from state: TerminalState) -> Int {
        let cellWidth = 1.0 / Float(state.cols)
        let cellHeight = 1.0 / Float(state.rows)

        var count = 0
        let basePtr = instancePointer.assumingMemoryBound(to: Instance.self)

        for region in regions {
            let maxX = min(region.x + region.width, state.cols)
            let maxY = min(region.y + region.height, state.rows)

            for y in region.y..<maxY {
                let posY = Float(y) * cellHeight

                for x in region.x..<maxX {
                    guard let cell = state.getCell(x: x, y: y) else { continue }

                    let posX = Float(x) * cellWidth
                    let uvRect = glyphCache.getUVRect(for: cell.char)

                    basePtr[count] = Instance(
                        position: SIMD2(posX, posY),
                        size: SIMD2(cellWidth, cellHeight),
                        uvRect: uvRect,
                        fgColor: rgbToFloat(cell.fgColor),
                        bgColor: rgbToFloat(cell.bgColor),
                        attrs: UInt32(cell.attrs)
                    )
                    count += 1
                }
            }
        }

        return count
    }

    /// 构建光标实例（直接写入 GPU 内存）
    @inline(__always)
    private func buildCursorInstance(from state: TerminalState) {
        let cellWidth = 1.0 / Float(state.cols)
        let cellHeight = 1.0 / Float(state.rows)

        let info = state.getCursorInfo()
        let posX = Float(info.x) * cellWidth
        let posY = Float(info.y) * cellHeight

        let cursorColor: SIMD4<Float>
        if let cell = state.getCell(x: info.x, y: info.y) {
            let fg = rgbToFloat(cell.fgColor)
            cursorColor = SIMD4(1.0 - fg[0], 1.0 - fg[1], 1.0 - fg[2], 0.8)
        } else {
            cursorColor = SIMD4(1.0, 1.0, 1.0, 0.8)
        }

        let style: UInt32
        switch info.style {
        case .block: style = 0
        case .underline: style = 1
        case .bar: style = 2
        }

        let ptr = cursorInstancePointer.assumingMemoryBound(to: CursorInstance.self)
        ptr.pointee = CursorInstance(
            position: SIMD2(posX, posY),
            size: SIMD2(cellWidth, cellHeight),
            color: cursorColor,
            style: style
        )
    }

    // MARK: - Utility

    @inline(__always)
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
