//
//  QRScannerSimpleController.swift
//  Vibing (iOS)
//
//  简单 QR 码扫描器 — AVFoundation 相机直接读取
//

import UIKit
import AVFoundation

class QRScannerSimpleController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let onResult: (String) -> Void
    private var hasDeliveredResult = false

    init(onResult: @escaping (String) -> Void) {
        self.onResult = onResult
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupOverlay()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession?.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            showError()
            return
        }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)

        captureSession = session
        previewLayer = preview
    }

    private func setupOverlay() {
        // Close button
        let closeBtn = UIButton(type: .system)
        closeBtn.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)), for: .normal)
        closeBtn.tintColor = .white
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeBtn)

        // Title
        let label = UILabel()
        label.text = L("login.qrScanCamera")
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        // Scan frame
        let frame = UIView()
        frame.layer.borderWidth = 2
        frame.layer.borderColor = UIColor(red: 106/255, green: 194/255, blue: 120/255, alpha: 1).cgColor
        frame.layer.cornerRadius = 16
        frame.layer.cornerCurve = .continuous
        frame.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(frame)

        NSLayoutConstraint.activate([
            closeBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            frame.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            frame.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            frame.widthAnchor.constraint(equalToConstant: 250),
            frame.heightAnchor.constraint(equalToConstant: 250),
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func showError() {
        let label = UILabel()
        label.text = "Camera not available"
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        label.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        label.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !hasDeliveredResult,
              let metadata = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = metadata.stringValue else { return }

        hasDeliveredResult = true
        captureSession?.stopRunning()

        // Haptic
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        onResult(value)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
}
