//
//  MetalRenderer.swift
//  VibeTerminal
//
//  Metal 渲染器 - 负责终端的 GPU 渲染
//

import Foundation
import Metal
import MetalKit

class MetalRenderer: NSObject {

    // MARK: - Properties

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var cursorPipelineState: MTLRenderPipelineState?

    // 字形缓存
    private let glyphCache: GlyphCache

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
    private var maxInstances: Int
    private var currentDrawableSize: CGSize = .zero
    private var needsFullRender: Bool = true  // 首次渲染或尺寸变化时需要全屏渲染

    // 性能统计
    private var frameCount: UInt64 = 0
    private var lastFrameTime: CFAbsoluteTime = 0
    private var fps: Double = 0

    // MARK: - Initialization

    init?(device: MTLDevice, metalKitView: MTKView) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!

        // 根据预期终端大小计算最大实例数
        let maxCols = 200  // 支持最多 200 列
        let maxRows = 100  // 支持最多 100 行
        self.maxInstances = maxCols * maxRows

        // 初始化字形缓存
        guard let cache = GlyphCache(device: device) else {
            return nil
        }
        self.glyphCache = cache

        // 创建基础四边形顶点（左下、右下、左上、右上，用于 triangle strip）
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

        // 创建光标实例缓冲（只需要一个实例）
        guard let ciBuffer = device.makeBuffer(length: MemoryLayout<CursorInstance>.stride, options: []) else {
            return nil
        }
        self.cursorInstanceBuffer = ciBuffer

        super.init()

        // 设置视图
        metalKitView.device = device
        metalKitView.clearColor = MTLClearColor(red: 0.11, green: 0.11, blue: 0.11, alpha: 1.0)
        metalKitView.framebufferOnly = false
        metalKitView.preferredFramesPerSecond = 60

        // 设置渲染管线
        setupPipelines(metalKitView: metalKitView)
    }

    // MARK: - Pipeline Setup

    private func setupPipelines(metalKitView: MTKView) {
        guard let library = device.makeDefaultLibrary() else {
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
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat

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
        cursorPipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat

        // 光标使用加法混合使其更明显
        cursorPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        cursorPipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        cursorPipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        cursorPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        cursorPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        cursorPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        cursorPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        // 光标顶点描述符
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
        vertexDescriptor.attributes[2].format = .float2       // position
        vertexDescriptor.attributes[2].offset = 0
        vertexDescriptor.attributes[2].bufferIndex = 1

        vertexDescriptor.attributes[3].format = .float2       // size
        vertexDescriptor.attributes[3].offset = MemoryLayout<SIMD2<Float>>.stride
        vertexDescriptor.attributes[3].bufferIndex = 1

        vertexDescriptor.attributes[4].format = .float4       // uvRect
        vertexDescriptor.attributes[4].offset = MemoryLayout<SIMD2<Float>>.stride * 2
        vertexDescriptor.attributes[4].bufferIndex = 1

        vertexDescriptor.attributes[5].format = .float4       // fgColor
        vertexDescriptor.attributes[5].offset = MemoryLayout<SIMD2<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride
        vertexDescriptor.attributes[5].bufferIndex = 1

        vertexDescriptor.attributes[6].format = .float4       // bgColor
        vertexDescriptor.attributes[6].offset = MemoryLayout<SIMD2<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride * 2
        vertexDescriptor.attributes[6].bufferIndex = 1

        vertexDescriptor.attributes[7].format = .uint         // attrs
        vertexDescriptor.attributes[7].offset = MemoryLayout<SIMD2<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride * 3
        vertexDescriptor.attributes[7].bufferIndex = 1

        vertexDescriptor.layouts[1].stride = MemoryLayout<Instance>.stride
        vertexDescriptor.layouts[1].stepFunction = .perInstance

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

        // Buffer 1: 光标实例
        vertexDescriptor.attributes[1].format = .float2       // position
        vertexDescriptor.attributes[1].offset = 0
        vertexDescriptor.attributes[1].bufferIndex = 1

        vertexDescriptor.attributes[2].format = .float2       // size
        vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD2<Float>>.stride
        vertexDescriptor.attributes[2].bufferIndex = 1

        vertexDescriptor.attributes[3].format = .float4       // color
        vertexDescriptor.attributes[3].offset = MemoryLayout<SIMD2<Float>>.stride * 2
        vertexDescriptor.attributes[3].bufferIndex = 1

        vertexDescriptor.attributes[4].format = .uint         // style
        vertexDescriptor.attributes[4].offset = MemoryLayout<SIMD2<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride
        vertexDescriptor.attributes[4].bufferIndex = 1

        vertexDescriptor.layouts[1].stride = MemoryLayout<CursorInstance>.stride
        vertexDescriptor.layouts[1].stepFunction = .perInstance

        return vertexDescriptor
    }

    // MARK: - Rendering

    func render(state: TerminalState, in drawable: CAMetalDrawable) {
        let drawableSize = drawable.texture.width > 0 ? CGSize(width: CGFloat(drawable.texture.width),
                                                                 height: CGFloat(drawable.texture.height)) : CGSize(width: 1, height: 1)

        // 更新尺寸
        if currentDrawableSize != drawableSize {
            currentDrawableSize = drawableSize
            needsFullRender = true
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = makeRenderPassDescriptor(drawable: drawable) else {
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

            // 如果没有脏区域且不需要全屏渲染，跳过字符渲染
            if !needsFullRender && dirtyRegions.isEmpty {
                // 只渲染光标
            } else {
                let instances: [Instance]
                if needsFullRender || dirtyRegions.isEmpty {
                    // 全屏渲染
                    instances = buildInstances(from: state, drawableSize: drawableSize)
                    needsFullRender = false
                } else {
                    // 只渲染脏区域
                    instances = buildInstancesForDirtyRegions(dirtyRegions, from: state, drawableSize: drawableSize)
                }

                let instanceData = instances.withUnsafeBufferPointer { buffer in
                    Data(buffer: buffer)
                }

            memcpy(instanceBuffer.contents, instanceData, instanceData.count)

            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(instanceBuffer, offset: 0, index: 1)
            renderEncoder.setFragmentTexture(glyphCache.texture, index: 0)

            // 绘制所有字符
            if instances.count > 0 {
                renderEncoder.drawPrimitives(type: .triangleStrip,
                                            vertexStart: 0,
                                            vertexCount: 4,
                                            instanceCount: instances.count)
            }
        }

        // 渲染光标
        if state.cursorVisible, let cursorPipeline = cursorPipelineState {
            renderEncoder.setRenderPipelineState(cursorPipeline)

            let cursorInstance = buildCursorInstance(from: state, drawableSize: drawableSize)
            memcpy(cursorInstanceBuffer.contents, &cursorInstance, MemoryLayout<CursorInstance>.stride)

            renderEncoder.setVertexBuffer(cursorVertexBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(cursorInstanceBuffer, offset: 0, index: 1)

            renderEncoder.drawPrimitives(type: .triangleStrip,
                                        vertexStart: 0,
                                        vertexCount: 4,
                                        instanceCount: 1)
        }

        renderEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()

        // 更新 FPS 统计
        updateFPS()
    }

    private func makeRenderPassDescriptor(drawable: CAMetalDrawable) -> MTLRenderPassDescriptor? {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.11, green: 0.11, blue: 0.11, alpha: 1.0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        return renderPassDescriptor
    }

    // MARK: - Instance Building

    private func buildInstances(from state: TerminalState, drawableSize: CGSize) -> [Instance] {
        var instances: [Instance] = []
        instances.reserveCapacity(state.cols * state.rows)

        let cellWidth = 1.0 / CGFloat(state.cols)
        let cellHeight = 1.0 / CGFloat(state.rows)

        for y in 0..<state.rows {
            for x in 0..<state.cols {
                guard let cell = state.getCell(x: x, y: y) else { continue }

                // 计算位置（归一化坐标）
                let posX = CGFloat(x) * cellWidth
                let posY = CGFloat(y) * cellHeight

                // 获取字形纹理坐标
                let uvRect = glyphCache.getUVRect(for: cell.char)

                // 如果字形无效（返回零），字符可能不在缓存中
                // GlyphCache 会自动尝试缓存，但第一次可能返回零

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

        return instances
    }

    /// 只为指定的脏区域构建实例数据（优化渲染）
    private func buildInstancesForDirtyRegions(_ regions: [DirtyRegion], from state: TerminalState, drawableSize: CGSize) -> [Instance] {
        var instances: [Instance] = []

        // 预估容量
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

    private func buildCursorInstance(from state: TerminalState, drawableSize: CGSize) -> CursorInstance {
        let cellWidth = 1.0 / CGFloat(state.cols)
        let cellHeight = 1.0 / CGFloat(state.rows)

        let posX = CGFloat(state.cursorX) * cellWidth
        let posY = CGFloat(state.cursorY) * cellHeight

        // 光标颜色（使用前景色的高亮版本或固定颜色）
        let cursorColor: SIMD4<Float>
        if let cell = state.getCell(x: state.cursorX, y: state.cursorY) {
            // 使用反转的前景色作为光标颜色
            cursorColor = SIMD4(1.0 - rgbToFloat(cell.fgColor).r,
                                1.0 - rgbToFloat(cell.fgColor).g,
                                1.0 - rgbToFloat(cell.fgColor).b,
                                0.8)
        } else {
            cursorColor = SIMD4(1.0, 1.0, 1.0, 0.8)  // 默认白色半透明
        }

        // 样式转换
        let style: UInt32
        switch state.cursorStyle {
        case .block:
            style = 0
        case .underline:
            style = 1
        case .bar:
            style = 2
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
            fps = Double(frameCount)
            frameCount = 0
            lastFrameTime = now

            #if DEBUG
            // print("FPS: \(fps)")
            #endif
        }
    }

    func getFPS() -> Double {
        return fps
    }
}

// MARK: - MTKViewDelegate
extension MetalRenderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        currentDrawableSize = size
    }

    func draw(in view: MTKView) {
        // 这个方法由 MTKView 自动调用
        // 实际渲染由 render(state:in:) 处理
    }
}
