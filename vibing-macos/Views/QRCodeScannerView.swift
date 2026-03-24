//
//  QRCodeScannerView.swift
//  VibeTerminal
//
//  二维码扫描视图 - 用于扫描其他设备的配对码
//

import SwiftUI
import AVFoundation
import Vision

// MARK: - 扫描结果

enum QRScanResult {
    case success(accountId: String, deviceId: String, code: String)
    case error(QRScanError)
    case cancelled
}

enum QRScanError: LocalizedError {
    case cameraPermissionDenied
    case cameraNotAvailable
    case invalidQRCodeFormat
    case invalidPairingCodeFormat
    case pairingCodeExpired
    case scanningFailed(String)

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            return "Camera access is required to scan QR codes. Please grant permission in System Settings."
        case .cameraNotAvailable:
            return "Camera is not available on this device."
        case .invalidQRCodeFormat:
            return "The scanned QR code is not a valid Vibing pairing code."
        case .invalidPairingCodeFormat:
            return "Invalid pairing code format."
        case .pairingCodeExpired:
            return "This pairing code has expired. Please generate a new one."
        case .scanningFailed(let message):
            return "Scanning failed: \(message)"
        }
    }
}

// MARK: - 扫描配置

struct QRScannerConfig {
    static let scanAreaSize: CGFloat = 280
    static let cornerRadius: CGFloat = 12
    static let lineWidth: CGFloat = 3
    static let animationDuration: Double = 2.0
    static let codeValidityDuration: TimeInterval = 300 // 5 minutes
}

// MARK: - 主扫描视图

struct QRCodeScannerView: View {
    @StateObject private var scannerModel = QRScannerModel()
    @Environment(\.dismiss) var dismiss

    let onScanResult: (QRScanResult) -> Void

    var body: some View {
        ZStack {
            // 相机预览
            CameraPreviewView(session: scannerModel.captureSession)
                .ignoresSafeArea()

            // 扫描界面 UI
            scannerOverlay
        }
        .onAppear {
            scannerModel.startScanning { result in
                handleScanResult(result)
            }
        }
        .onDisappear {
            scannerModel.stopScanning()
        }
        .alert("Error", isPresented: $scannerModel.showError) {
            Button("OK") {
                if scannerModel.shouldDismiss {
                    dismiss()
                }
            }
        } message: {
            Text(scannerModel.errorMessage)
        }
    }

    private var scannerOverlay: some View {
        VStack {
            // 顶部提示
            topBar

            Spacer()

            // 取景框
            scanFrame
                .frame(width: QRScannerConfig.scanAreaSize, height: QRScannerConfig.scanAreaSize)

            Spacer()

            // 底部操作
            bottomBar
        }
        .background(
            // 半透明遮罩
            VStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(height: 120)
                Spacer()
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(height: 120)
            }
            .ignoresSafeArea()
        )
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
                onScanResult(.cancelled)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }

            Spacer()

            Text("Scan Pairing Code")
                .font(.headline)
                .foregroundColor(.white)

            Spacer()

            // 闪光灯开关
            if scannerModel.hasTorch {
                Button {
                    scannerModel.toggleTorch()
                } label: {
                    Image(systemName: scannerModel.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
            }
        }
        .padding()
    }

    private var scanFrame: some View {
        ZStack {
            // 取景框边框
            RoundedRectangle(cornerRadius: QRScannerConfig.cornerRadius)
                .stroke(Color.accentColor, lineWidth: QRScannerConfig.lineWidth)

            // 四角装饰
            cornersOverlay

            // 扫描线动画
            if scannerModel.isScanning && !scannerModel.isProcessing {
                scanningLine
            }

            // 处理中指示器
            if scannerModel.isProcessing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            }
        }
    }

    private var cornersOverlay: some View {
        GeometryReader { geometry in
            let cornerSize: CGFloat = 30
            let thickness: CGFloat = 4

            ZStack {
                // 左上角
                Path { path in
                    path.move(to: CGPoint(x: 0, y: cornerSize))
                    path.addLine(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: cornerSize, y: 0))
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))

                // 右上角
                Path { path in
                    let width = geometry.size.width
                    path.move(to: CGPoint(x: width - cornerSize, y: 0))
                    path.addLine(to: CGPoint(x: width, y: 0))
                    path.addLine(to: CGPoint(x: width, y: cornerSize))
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))

                // 左下角
                Path { path in
                    let height = geometry.size.height
                    path.move(to: CGPoint(x: 0, y: height - cornerSize))
                    path.addLine(to: CGPoint(x: 0, y: height))
                    path.addLine(to: CGPoint(x: cornerSize, y: height))
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))

                // 右下角
                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    path.move(to: CGPoint(x: width - cornerSize, y: height))
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.addLine(to: CGPoint(x: width, y: height - cornerSize))
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: QRScannerConfig.scanAreaSize, height: QRScannerConfig.scanAreaSize)
    }

    private var scanningLine: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
                .shadow(color: .accentColor, radius: 4, x: 0, y: 0)
                .offset(y: scannerModel.scanLinePosition * (geometry.size.height - 2))
        }
        .frame(height: QRScannerConfig.scanAreaSize)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            Text("Position the QR code within the frame")
                .font(.subheadline)
                .foregroundColor(.white)

            Text("Format: VT1|accountId|deviceId|timestamp|signature")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func handleScanResult(_ result: QRScanResult) {
        switch result {
        case .success:
            // 延迟关闭，让用户看到成功反馈
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                dismiss()
                onScanResult(result)
            }

        case .error(let error):
            scannerModel.showError(error)
            // 重新开始扫描
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                scannerModel.resetScanning()
            }

        case .cancelled:
            dismiss()
            onScanResult(result)
        }
    }
}

// MARK: - 相机预览视图

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill

        view.layer = previewLayer
        view.wantsLayer = true

        // 更新 layer frame
        DispatchQueue.main.async {
            previewLayer.frame = view.bounds
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let previewLayer = nsView.layer as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = nsView.bounds
        }
    }
}

// MARK: - 扫描器模型

@MainActor
class QRScannerModel: ObservableObject {
    @Published var isScanning = false
    @Published var isProcessing = false
    @Published var scanLinePosition: CGFloat = 0
    @Published var isTorchOn = false
    @Published var hasTorch = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var shouldDismiss = false

    var captureSession = AVCaptureSession()
    private var videoOutput: AVCaptureVideoDataOutput?
    private var videoOutputQueue = DispatchQueue(label: "com.vibeterminal.qrscanner")
    private var scanningTimer: Timer?
    private var animationTimer: Timer?

    private var scanCompletion: ((QRScanResult) -> Void)?

    // 去重：避免重复扫描同一码
    private var lastScannedCode: String?
    private var lastScanTime: Date?

    func startScanning(completion: @escaping (QRScanResult) -> Void) {
        self.scanCompletion = completion
        self.isScanning = true
        self.startScanLineAnimation()

        Task {
            do {
                try await setupCamera()
            } catch {
                handleError(error)
            }
        }
    }

    func stopScanning() {
        isScanning = false
        animationTimer?.invalidate()
        animationTimer = nil
        scanningTimer?.invalidate()
        scanningTimer = nil

        captureSession.stopRunning()
    }

    func resetScanning() {
        isProcessing = false
        isScanning = true
        lastScannedCode = nil
        lastScanTime = nil
    }

    func toggleTorch() {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }

        do {
            try device.lockForConfiguration()
            if device.torchMode == .on {
                device.torchMode = .off
                isTorchOn = false
            } else {
                device.torchMode = .on
                isTorchOn = true
            }
            device.unlockForConfiguration()
        } catch {
            print("Failed to toggle torch: \(error)")
        }
    }

    func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
        shouldDismiss = (error as? QRScanError) == .cameraPermissionDenied
    }

    private func setupCamera() async throws {
        // 检查相机权限
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch authorizationStatus {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                throw QRScanError.cameraPermissionDenied
            }

        case .denied, .restricted:
            throw QRScanError.cameraPermissionDenied

        case .authorized:
            break

        @unknown default:
            throw QRScanError.cameraPermissionDenied
        }

        // 获取摄像头设备
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) else {
            throw QRScanError.cameraNotAvailable
        }

        // 检查是否有闪光灯
        hasTorch = camera.hasTorch

        // 配置会话
        captureSession.sessionPreset = .high

        let input = try AVCaptureDeviceInput(device: camera)
        captureSession.addInput(input)

        // 配置视频输出
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: videoOutputQueue)
        output.alwaysDiscardsLateVideoFrames = true
        captureSession.addOutput(output)

        self.videoOutput = output

        // 设置视频连接方向
        if let connection = output.connection(with: .video) {
            connection.videoOrientation = .portrait
        }

        // 启动会话
        captureSession.startRunning()
    }

    private func startScanLineAnimation() {
        animationTimer?.invalidate()

        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            if self.scanLinePosition >= 1 {
                self.scanLinePosition = 0
            } else {
                self.scanLinePosition += 0.02
            }
        }
    }

    private func processQRCode(_ code: String) {
        // 防止重复扫描
        if let lastCode = lastScannedCode,
           lastCode == code,
           let lastTime = lastScanTime,
           Date().timeIntervalSince(lastTime) < 2.0 {
            return
        }

        lastScannedCode = code
        lastScanTime = Date()
        isProcessing = true

        // 验证配对码格式
        let result = validatePairingCode(code)

        DispatchQueue.main.async {
            self.scanCompletion?(result)
        }
    }

    private func validatePairingCode(_ code: String) -> QRScanResult {
        let components = code.split(separator: "|").map { String($0) }

        // 基本格式验证
        guard components.count >= 4 else {
            return .error(.invalidPairingCodeFormat)
        }

        let version = components[0]
        guard version == "VT1" else {
            return .error(.invalidQRCodeFormat)
        }

        let accountId = components[1]
        let deviceId = components[2]

        // 验证时间戳
        guard let timestamp = TimeInterval(components[3]) else {
            return .error(.invalidPairingCodeFormat)
        }

        let now = Date().timeIntervalSince1970
        let age = now - timestamp

        // 验证时间有效性（5分钟内）
        guard age >= 0 && age < QRScannerConfig.codeValidityDuration else {
            return .error(.pairingCodeExpired)
        }

        // 可选：验证签名
        if components.count > 4 {
            let signature = components[4]
            if signature.isEmpty {
                return .error(.invalidPairingCodeFormat)
            }
        }

        return .success(accountId: accountId, deviceId: deviceId, code: code)
    }

    private func handleError(_ error: Error) {
        DispatchQueue.main.async {
            if let qrError = error as? QRScanError {
                self.showError(qrError)
            } else {
                self.showError(QRScanError.scanningFailed(error.localizedDescription))
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension QRScannerModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isScanning, !isProcessing else { return }

        // 将样本缓冲区转换为图像
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // 创建 Vision 请求
        let request = VNDetectBarcodesRequest { [weak self] request, error in
            guard let self = self else { return }

            if let error = error {
                print("QR detection error: \(error)")
                return
            }

            guard let observations = request.results as? [VNBarcodeObservation],
                  let firstObservation = observations.first,
                  let payload = firstObservation.payloadStringValue else {
                return
            }

            // 在主线程处理结果
            DispatchQueue.main.async {
                self.processQRCode(payload)
            }
        }

        // 配置识别类型为二维码
        request.symbologies = [.qr]

        // 创建图像请求处理器
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform Vision request: \(error)")
        }
    }
}

// MARK: - 扫描结果视图

struct QRScanSuccessView: View {
    let accountId: String
    let deviceId: String
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("Successfully Connected!")
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Account ID:")
                        .foregroundColor(.secondary)
                    Text(accountId)
                        .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Text("Device ID:")
                        .foregroundColor(.secondary)
                    Text(deviceId)
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            Button("Continue") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 350, height: 300)
    }
}

// MARK: - 预览

struct QRCodeScannerView_Previews: PreviewProvider {
    static var previews: some View {
        QRCodeScannerView { result in
            print("Scan result: \(result)")
        }
    }
}
