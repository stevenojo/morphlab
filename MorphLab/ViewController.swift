//
//  ViewController.swift
//  MorphLab — Vision + Metal face morph.
//  Supports: two photos, live camera capture, video input (chained morphs), audio mux.
//

import UIKit
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

final class ViewController: UIViewController {

    // MARK: UI
    private let imageViewA = UIImageView()
    private let imageViewB = UIImageView()
    private let previewView = UIImageView()
    private let statusLabel = UILabel()
    private let progress = UIProgressView(progressViewStyle: .default)

    private let pickAButton = UIButton(type: .system)
    private let pickBButton = UIButton(type: .system)
    private let cameraAButton = UIButton(type: .system)
    private let cameraBButton = UIButton(type: .system)
    private let pickVideoButton = UIButton(type: .system)
    private let pickAudioButton = UIButton(type: .system)
    private let renderButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)

    // MARK: State
    private var imageA: UIImage?
    private var imageB: UIImage?
    private var videoFrames: [UIImage] = []      // populated when user picks a video
    private var audioURL: URL?
    private var lastExportURL: URL?

    private let renderer = MorphRenderer()
    private var pickingSlot: Int = 0

    private let outputSize = CGSize(width: 1080, height: 1080)
    private let framesPerPair = 90
    private let fps: Int32 = 30

    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "MorphLab"
        setupUI()
    }

    private func setupUI() {
        overrideUserInterfaceStyle = .dark
        let bg = UIColor(red: 0.043, green: 0.047, blue: 0.063, alpha: 1)
        view.backgroundColor = bg
        styleNavBar(bg)

        let accent = UIColor(red: 0.35, green: 0.56, blue: 0.86, alpha: 1)

        // ── Image views ──
        for iv in [imageViewA, imageViewB] {
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            iv.backgroundColor = UIColor(white: 0.10, alpha: 1)
            iv.layer.cornerRadius = 8
            iv.layer.borderWidth = 1
            iv.layer.borderColor = UIColor(white: 0.20, alpha: 1).cgColor
        }

        // ── Preview ──
        previewView.contentMode = .scaleAspectFit
        previewView.backgroundColor = UIColor(white: 0.05, alpha: 1)
        previewView.layer.cornerRadius = 10
        previewView.layer.borderWidth = 1
        previewView.layer.borderColor = UIColor(white: 0.15, alpha: 1).cgColor
        previewView.clipsToBounds = true

        // ── Buttons ──
        styleBtn(pickAButton,     "Photo",  "photo",    #selector(pickA))
        styleBtn(pickBButton,     "Photo",  "photo",    #selector(pickB))
        styleBtn(cameraAButton,   "Camera", "camera",   #selector(snapA))
        styleBtn(cameraBButton,   "Camera", "camera",   #selector(snapB))
        styleBtn(pickVideoButton, "Video",  "film",     #selector(pickVideo))
        styleBtn(pickAudioButton, "Audio",  "waveform", #selector(pickAudio))
        stylePrimary(renderButton, "RENDER", accent,                        #selector(renderMorph))
        stylePrimary(shareButton,  "SHARE",  UIColor(white: 0.18, alpha: 1), #selector(share))
        renderButton.isEnabled = false
        shareButton.isEnabled = false

        // ── Status & progress ──
        statusLabel.text = "Select two faces or import a video."
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = UIColor(white: 0.45, alpha: 1)
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center

        progress.progressTintColor = accent
        progress.trackTintColor = UIColor(white: 0.12, alpha: 1)

        // ── Layout ──
        let colA = vs(6, [imageViewA, pickAButton, cameraAButton])
        let colB = vs(6, [imageViewB, pickBButton, cameraBButton])
        let facesRow = hs(10, [colA, colB])

        let inputRow  = hs(10, [pickVideoButton, pickAudioButton])
        let actionRow = hs(10, [renderButton, shareButton])

        let main = vs(0, [
            headerLabel("FACES"),   facesRow,
            headerLabel("INPUT"),   inputRow,
            headerLabel("PREVIEW"), previewView,
            statusLabel, progress,  actionRow
        ])
        main.isLayoutMarginsRelativeArrangement = true
        main.layoutMargins = UIEdgeInsets(top: 16, left: 20, bottom: 20, right: 20)
        main.setCustomSpacing(10, after: main.arrangedSubviews[0])
        main.setCustomSpacing(24, after: facesRow)
        main.setCustomSpacing(10, after: main.arrangedSubviews[2])
        main.setCustomSpacing(24, after: inputRow)
        main.setCustomSpacing(10, after: main.arrangedSubviews[4])
        main.setCustomSpacing(12, after: previewView)
        main.setCustomSpacing(6,  after: statusLabel)
        main.setCustomSpacing(16, after: progress)

        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        main.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(main)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            main.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            main.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            main.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            main.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            main.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            imageViewA.heightAnchor.constraint(equalTo: imageViewA.widthAnchor, multiplier: 1.2),
            imageViewB.heightAnchor.constraint(equalTo: imageViewB.widthAnchor, multiplier: 1.2),
            previewView.heightAnchor.constraint(equalTo: previewView.widthAnchor, multiplier: 9.0/16.0),
            renderButton.heightAnchor.constraint(equalToConstant: 48),
            shareButton.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    // MARK: - UI helpers

    private func styleNavBar(_ bg: UIColor) {
        let a = UINavigationBarAppearance()
        a.configureWithOpaqueBackground()
        a.backgroundColor = bg
        a.titleTextAttributes = [.foregroundColor: UIColor.white,
                                 .font: UIFont.systemFont(ofSize: 17, weight: .bold)]
        navigationController?.navigationBar.standardAppearance = a
        navigationController?.navigationBar.scrollEdgeAppearance = a
        navigationController?.navigationBar.compactAppearance = a
    }

    private func headerLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.attributedText = NSAttributedString(string: text, attributes: [
            .kern: 2.0,
            .font: UIFont.systemFont(ofSize: 11, weight: .heavy),
            .foregroundColor: UIColor(white: 0.40, alpha: 1)
        ])
        return l
    }

    private func styleBtn(_ btn: UIButton, _ title: String, _ icon: String, _ action: Selector) {
        var c = UIButton.Configuration.filled()
        c.title = title
        c.image = UIImage(systemName: icon)
        c.imagePadding = 6
        c.cornerStyle = .medium
        c.baseBackgroundColor = UIColor(white: 0.14, alpha: 1)
        c.baseForegroundColor = .white
        c.buttonSize = .medium
        btn.configuration = c
        btn.addTarget(self, action: action, for: .touchUpInside)
    }

    private func stylePrimary(_ btn: UIButton, _ title: String, _ color: UIColor, _ action: Selector) {
        var c = UIButton.Configuration.filled()
        c.title = title
        c.cornerStyle = .medium
        c.baseBackgroundColor = color
        c.baseForegroundColor = .white
        c.buttonSize = .large
        c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
            var out = a; out.font = UIFont.systemFont(ofSize: 15, weight: .bold); return out
        }
        btn.configuration = c
        btn.addTarget(self, action: action, for: .touchUpInside)
    }

    private func vs(_ spacing: CGFloat, _ views: [UIView]) -> UIStackView {
        let s = UIStackView(arrangedSubviews: views)
        s.axis = .vertical; s.spacing = spacing; return s
    }

    private func hs(_ spacing: CGFloat, _ views: [UIView]) -> UIStackView {
        let s = UIStackView(arrangedSubviews: views)
        s.axis = .horizontal; s.spacing = spacing; s.distribution = .fillEqually; return s
    }

    private func updateReadyState() {
        let pairReady = (imageA != nil && imageB != nil)
        let videoReady = videoFrames.count >= 2
        renderButton.isEnabled = pairReady || videoReady
        if videoReady {
            statusLabel.text = "Video loaded (\(videoFrames.count) keyframes). Tap Render."
        } else if pairReady {
            statusLabel.text = "Ready. Tap Render."
        }
    }

    // MARK: Pickers

    @objc private func pickA() { pickingSlot = 0; presentImagePicker() }
    @objc private func pickB() { pickingSlot = 1; presentImagePicker() }
    @objc private func snapA() { pickingSlot = 0; presentCamera(prompt: "Capture Face A") }
    @objc private func snapB() { pickingSlot = 1; presentCamera(prompt: "Capture Face B") }

    private func presentImagePicker() {
        var cfg = PHPickerConfiguration()
        cfg.filter = .images
        cfg.selectionLimit = 1
        let picker = PHPickerViewController(configuration: cfg)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentCamera(prompt: String) {
        let vc = CameraCaptureController()
        vc.prompt = prompt
        vc.modalPresentationStyle = .fullScreen
        vc.onCapture = { [weak self] image in
            guard let self, let img = image else { return }
            self.assignCapturedImage(img)
        }
        present(vc, animated: true)
    }

    private func assignCapturedImage(_ img: UIImage) {
        if pickingSlot == 0 {
            imageA = img
            imageViewA.image = img
        } else {
            imageB = img
            imageViewB.image = img
        }
        videoFrames.removeAll() // pair mode overrides video mode
        updateReadyState()
    }

    @objc private func pickVideo() {
        var cfg = PHPickerConfiguration()
        cfg.filter = .videos
        cfg.selectionLimit = 1
        let picker = PHPickerViewController(configuration: cfg)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func pickAudio() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio, .movie, .mpeg4Movie])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    @objc private func share() {
        guard let url = lastExportURL,
              FileManager.default.fileExists(atPath: url.path) else {
            statusLabel.text = "No video to share."
            return
        }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = shareButton
        present(vc, animated: true)
    }

    // MARK: Rendering

    @objc private func renderMorph() {
        renderButton.isEnabled = false
        shareButton.isEnabled = false
        progress.setProgress(0, animated: false)

        // Decide between pair mode and video chain mode
        let frames: [UIImage]
        if videoFrames.count >= 2 {
            frames = videoFrames
        } else if let a = imageA, let b = imageB {
            frames = [a, b]
        } else {
            return
        }

        statusLabel.text = "Detecting landmarks…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.renderChain(frames: frames)
        }
    }

    /// Renders a morph across an ordered list of 2+ images by chaining pairwise morphs
    /// into a single video. Then optionally muxes audio on top.
    private func renderChain(frames: [UIImage]) {
        // Normalize all frames to the output canvas
        let normalized = frames.map { $0.normalized(to: outputSize) }

        // Detect landmarks per frame (drop frames with no face)
        var allPoints: [[CGPoint]] = []
        var usable: [UIImage] = []
        for (i, img) in normalized.enumerated() {
            if let pts = FaceLandmarks.detect(in: img) {
                allPoints.append(pts + FaceLandmarks.boundaryAnchors(for: outputSize))
                usable.append(img)
            } else {
                print("Frame \(i): no face, skipping")
            }
        }
        guard usable.count >= 2 else {
            DispatchQueue.main.async {
                self.statusLabel.text = "Couldn't find faces in enough frames."
                self.renderButton.isEnabled = true
            }
            return
        }

        // All landmark arrays must have matching counts to triangulate consistently.
        // Vision returns a consistent count when the same landmark regions are present,
        // but some frames may be missing a region. Trim to the min count.
        let minCount = allPoints.map(\.count).min() ?? 0
        let pointsList = allPoints.map { Array($0.prefix(minCount)) }

        // Build a single stable triangulation from the mean of ALL frame points
        var mean = Array(repeating: CGPoint.zero, count: minCount)
        for pts in pointsList {
            for i in 0..<minCount {
                mean[i].x += pts[i].x
                mean[i].y += pts[i].y
            }
        }
        let n = CGFloat(pointsList.count)
        for i in 0..<minCount {
            mean[i].x /= n
            mean[i].y /= n
        }
        let triangles = Delaunay.triangulate(points: mean, canvas: outputSize)

        // Open exporter
        let silentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("morph-silent-\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: silentURL)

        let exporter = VideoExporter(url: silentURL, size: outputSize, fps: fps)
        do { try exporter.start() } catch {
            DispatchQueue.main.async {
                self.statusLabel.text = "Export failed: \(error)"
                self.renderButton.isEnabled = true
            }
            return
        }

        DispatchQueue.main.async {
            self.statusLabel.text = "Rendering \(usable.count - 1) morph segments…"
        }

        var globalFrameIndex = 0
        let totalPairs = usable.count - 1

        for pair in 0..<totalPairs {
            let ptsA = pointsList[pair]
            let ptsB = pointsList[pair + 1]

            guard let texA = renderer.makeTexture(from: usable[pair]),
                  let texB = renderer.makeTexture(from: usable[pair + 1]) else {
                print("Pair \(pair): texture creation failed")
                continue
            }

            for i in 0..<framesPerPair {
                let raw = Double(i) / Double(framesPerPair - 1)
                let t = CGFloat(0.5 - 0.5 * cos(raw * .pi))

                if let pb = renderer.renderFrame(
                    texA: texA, texB: texB,
                    pointsA: ptsA, pointsB: ptsB,
                    triangles: triangles, t: t, size: outputSize
                ) {
                    exporter.append(pixelBuffer: pb, frameIndex: globalFrameIndex)
                    globalFrameIndex += 1
                }

                let globalProgress = (Double(pair) + raw) / Double(totalPairs)
                DispatchQueue.main.async {
                    self.progress.setProgress(Float(globalProgress), animated: false)
                    if i % 8 == 0, let p = self.renderer.lastPreview {
                        self.previewView.image = p
                    }
                }
            }
        }

        guard globalFrameIndex > 0 else {
            DispatchQueue.main.async {
                self.statusLabel.text = "Rendering failed — no frames produced."
                self.renderButton.isEnabled = true
            }
            return
        }

        exporter.finish { [weak self] success, error in
            guard let self else { return }
            guard success else {
                DispatchQueue.main.async {
                    self.statusLabel.text = "Export failed: \(error?.localizedDescription ?? "unknown error")"
                    self.renderButton.isEnabled = true
                }
                return
            }
            self.handleExportedSilentVideo(silentURL)
        }
    }

    private func handleExportedSilentVideo(_ silentURL: URL) {
        // If no audio chosen, we're done.
        guard let audioURL = self.audioURL else {
            DispatchQueue.main.async {
                self.lastExportURL = silentURL
                self.finishExport()
            }
            return
        }

        let finalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("morph-\(Int(Date().timeIntervalSince1970)).mp4")
        DispatchQueue.main.async { self.statusLabel.text = "Adding audio…" }

        AudioMuxer.mux(videoURL: silentURL, audioURL: audioURL, outputURL: finalURL) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let url):
                    self.lastExportURL = url
                case .failure(let err):
                    print("Audio mux failed: \(err). Falling back to silent video.")
                    self.lastExportURL = silentURL
                }
                self.finishExport()
            }
        }
    }

    private func finishExport() {
        statusLabel.text = "Done. Tap Share."
        progress.setProgress(1, animated: true)
        renderButton.isEnabled = true
        shareButton.isEnabled = true
    }
}

// MARK: PHPicker
extension ViewController: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let item = results.first?.itemProvider else { return }

        // Video?
        if item.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            item.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, _ in
                guard let self, let src = url else { return }
                // Copy to temp because the provided URL is deleted when the closure returns
                let dst = FileManager.default.temporaryDirectory
                    .appendingPathComponent("input-\(UUID().uuidString).mov")
                try? FileManager.default.copyItem(at: src, to: dst)

                Task {
                    do {
                        let frames = try await VideoKeyframeExtractor.extractFrames(from: dst, count: 6)
                        await MainActor.run {
                            self.videoFrames = frames
                            self.imageA = frames.first
                            self.imageB = frames.last
                            self.imageViewA.image = frames.first
                            self.imageViewB.image = frames.last
                            self.updateReadyState()
                        }
                    } catch {
                        await MainActor.run {
                            self.statusLabel.text = "Couldn't read video: \(error.localizedDescription)"
                        }
                    }
                }
            }
            return
        }

        // Image
        guard item.canLoadObject(ofClass: UIImage.self) else { return }
        item.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
            guard let self, let img = obj as? UIImage else { return }
            DispatchQueue.main.async {
                self.videoFrames.removeAll()
                if self.pickingSlot == 0 {
                    self.imageA = img
                    self.imageViewA.image = img
                } else {
                    self.imageB = img
                    self.imageViewB.image = img
                }
                self.updateReadyState()
            }
        }
    }
}

// MARK: Audio picker
extension ViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        // Copy immediately so security-scoped access doesn't expire later
        let didStart = url.startAccessingSecurityScopedResource()
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("morph-audio-\(UUID().uuidString).\(url.pathExtension)")
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            self.audioURL = dest
            statusLabel.text = "Audio attached: \(url.lastPathComponent)"
        } catch {
            statusLabel.text = "Couldn't read audio: \(error.localizedDescription)"
        }
        if didStart { url.stopAccessingSecurityScopedResource() }
    }
}

// MARK: UIImage helpers
extension UIImage {
    func normalized(to size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let scale = max(size.width / self.size.width, size.height / self.size.height)
            let w = self.size.width * scale
            let h = self.size.height * scale
            let rect = CGRect(x: (size.width - w)/2, y: (size.height - h)/2, width: w, height: h)
            self.draw(in: rect)
        }
    }
}
