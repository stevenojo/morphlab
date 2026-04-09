//
//  CameraCaptureController.swift
//  Live selfie camera with photo capture. Returns a UIImage via completion.
//

import UIKit
import AVFoundation

final class CameraCaptureController: UIViewController {

    var onCapture: ((UIImage?) -> Void)?

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let captureButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let promptLabel = UILabel()
    private let countdownLabel = UILabel()

    var prompt: String = "Capture Face"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.stopRunning()
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video,
                                                    position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        session.commitConfiguration()
    }

    private func setupUI() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        promptLabel.text = prompt
        promptLabel.textColor = .white
        promptLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        promptLabel.textAlignment = .center
        promptLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(promptLabel)

        countdownLabel.textColor = .white
        countdownLabel.font = .systemFont(ofSize: 96, weight: .heavy)
        countdownLabel.textAlignment = .center
        countdownLabel.isHidden = true
        countdownLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(countdownLabel)

        var cfg = UIButton.Configuration.filled()
        cfg.title = "Capture"
        cfg.cornerStyle = .capsule
        cfg.baseBackgroundColor = .white
        cfg.baseForegroundColor = .black
        captureButton.configuration = cfg
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.addTarget(self, action: #selector(startCountdown), for: .touchUpInside)
        view.addSubview(captureButton)

        var cancelCfg = UIButton.Configuration.plain()
        cancelCfg.title = "Cancel"
        cancelCfg.baseForegroundColor = .white
        cancelButton.configuration = cancelCfg
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            promptLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            promptLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            countdownLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            countdownLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.widthAnchor.constraint(equalToConstant: 160),
            captureButton.heightAnchor.constraint(equalToConstant: 56),

            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    @objc private func cancelTapped() {
        onCapture?(nil)
        dismiss(animated: true)
    }

    @objc private func startCountdown() {
        captureButton.isHidden = true
        countdownLabel.isHidden = false
        runCountdown(from: 3)
    }

    private func runCountdown(from n: Int) {
        if n == 0 {
            countdownLabel.isHidden = true
            capture()
            return
        }
        countdownLabel.text = "\(n)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.runCountdown(from: n - 1)
        }
    }

    private func capture() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

extension CameraCaptureController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let img = UIImage(data: data) else {
            onCapture?(nil)
            dismiss(animated: true)
            return
        }
        // Front-camera photos on iPhone are already oriented but mirrored — flip
        // horizontally so the captured face matches what the user saw in preview.
        let mirrored: UIImage
        if let cg = img.cgImage {
            mirrored = UIImage(cgImage: cg, scale: img.scale, orientation: .leftMirrored)
        } else {
            mirrored = img
        }
        onCapture?(mirrored)
        dismiss(animated: true)
    }
}
