//
//  ViewController.swift
//  MorphLab — Vision + Metal face morph.
//  Multi-image timeline with draggable segment timing.
//

import UIKit
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

final class ViewController: UIViewController {

    // MARK: - UI

    private let faceStrip = UIScrollView()
    private let faceStack = UIStackView()
    private let timelineView = TimelineView()
    private let timelineSection = UIStackView()     // hidden when < 2 faces
    private let durationSlider = UISlider()
    private let durationLabel = UILabel()
    private let previewView = UIImageView()
    private let statusLabel = UILabel()
    private let progress = UIProgressView(progressViewStyle: .default)

    private let pickVideoButton = UIButton(type: .system)
    private let pickAudioButton = UIButton(type: .system)
    private let renderButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)

    // MARK: - State

    private var faceImages: [UIImage] = []
    private var audioURL: URL?
    private var audioDuration: TimeInterval?
    private var lastExportURL: URL?

    private let renderer = MorphRenderer()
    private let outputSize = CGSize(width: 1080, height: 1080)
    private let fps: Int32 = 30

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "MorphLab"
        setupUI()
    }

    // MARK: - UI Setup

    private func setupUI() {
        overrideUserInterfaceStyle = .dark
        let bg = UIColor(red: 0.043, green: 0.047, blue: 0.063, alpha: 1)
        view.backgroundColor = bg
        styleNavBar(bg)

        let accent = UIColor(red: 0.35, green: 0.56, blue: 0.86, alpha: 1)

        // ── Face strip (horizontal scroll) ──
        faceStrip.showsHorizontalScrollIndicator = false
        faceStrip.alwaysBounceHorizontal = true

        faceStack.axis = .horizontal
        faceStack.spacing = 10
        faceStack.alignment = .top
        faceStack.translatesAutoresizingMaskIntoConstraints = false
        faceStrip.addSubview(faceStack)
        NSLayoutConstraint.activate([
            faceStack.topAnchor.constraint(equalTo: faceStrip.contentLayoutGuide.topAnchor),
            faceStack.leadingAnchor.constraint(equalTo: faceStrip.contentLayoutGuide.leadingAnchor),
            faceStack.trailingAnchor.constraint(equalTo: faceStrip.contentLayoutGuide.trailingAnchor),
            faceStack.bottomAnchor.constraint(equalTo: faceStrip.contentLayoutGuide.bottomAnchor),
            faceStack.heightAnchor.constraint(equalTo: faceStrip.frameLayoutGuide.heightAnchor),
        ])
        rebuildFaceStrip()

        // ── Timeline ──
        timelineView.onChanged = { [weak self] in self?.timelineDividersChanged() }

        durationSlider.minimumValue = 1
        durationSlider.maximumValue = 60
        durationSlider.value = 10
        durationSlider.tintColor = accent
        durationSlider.addTarget(self, action: #selector(durationChanged), for: .valueChanged)
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        durationLabel.textColor = UIColor(white: 0.55, alpha: 1)
        durationLabel.text = "10.0s"
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)

        let durationRow = UIStackView(arrangedSubviews: [durationSlider, durationLabel])
        durationRow.axis = .horizontal; durationRow.spacing = 10; durationRow.alignment = .center

        timelineSection.axis = .vertical
        timelineSection.spacing = 8
        timelineSection.addArrangedSubview(headerLabel("TIMELINE"))
        timelineSection.addArrangedSubview(timelineView)
        timelineSection.addArrangedSubview(durationRow)
        timelineSection.isHidden = true

        // ── Preview ──
        previewView.contentMode = .scaleAspectFit
        previewView.backgroundColor = UIColor(white: 0.05, alpha: 1)
        previewView.layer.cornerRadius = 10
        previewView.layer.borderWidth = 1
        previewView.layer.borderColor = UIColor(white: 0.15, alpha: 1).cgColor
        previewView.clipsToBounds = true

        // ── Buttons ──
        styleBtn(pickVideoButton, "Import Video", "film",     #selector(pickVideo))
        styleBtn(pickAudioButton, "Attach Audio", "waveform", #selector(pickAudio))
        stylePrimary(renderButton, "RENDER", accent, #selector(renderMorph))
        stylePrimary(shareButton,  "SHARE",  UIColor(white: 0.18, alpha: 1), #selector(share))
        renderButton.isEnabled = false
        shareButton.isEnabled = false

        // ── Status & progress ──
        statusLabel.text = "Add faces or import a video to begin."
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = UIColor(white: 0.45, alpha: 1)
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        progress.progressTintColor = accent
        progress.trackTintColor = UIColor(white: 0.12, alpha: 1)

        // ── Layout ──
        let inputRow  = hs(10, [pickVideoButton, pickAudioButton])
        let actionRow = hs(10, [renderButton, shareButton])

        let main = vs(0, [
            headerLabel("FACES"),   faceStrip,
            timelineSection,
            headerLabel("INPUT"),   inputRow,
            headerLabel("PREVIEW"), previewView,
            statusLabel, progress,  actionRow
        ])
        main.isLayoutMarginsRelativeArrangement = true
        main.layoutMargins = UIEdgeInsets(top: 16, left: 20, bottom: 20, right: 20)
        main.setCustomSpacing(10, after: main.arrangedSubviews[0])  // after FACES header
        main.setCustomSpacing(16, after: faceStrip)
        main.setCustomSpacing(20, after: timelineSection)
        main.setCustomSpacing(10, after: main.arrangedSubviews[3])  // after INPUT header
        main.setCustomSpacing(20, after: inputRow)
        main.setCustomSpacing(10, after: main.arrangedSubviews[5])  // after PREVIEW header
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
            faceStrip.heightAnchor.constraint(equalToConstant: 88),
            timelineView.heightAnchor.constraint(equalToConstant: 56),
            previewView.heightAnchor.constraint(equalTo: previewView.widthAnchor, multiplier: 9.0/16.0),
            renderButton.heightAnchor.constraint(equalToConstant: 48),
            shareButton.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    // MARK: - Face strip

    private func rebuildFaceStrip() {
        faceStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (i, img) in faceImages.enumerated() {
            let card = makeFaceCard(image: img, index: i)
            faceStack.addArrangedSubview(card)
        }

        // "+" add button
        let addBtn = UIButton(type: .system)
        var cfg = UIButton.Configuration.filled()
        cfg.image = UIImage(systemName: "plus")
        cfg.cornerStyle = .medium
        cfg.baseBackgroundColor = UIColor(white: 0.14, alpha: 1)
        cfg.baseForegroundColor = .white
        addBtn.configuration = cfg
        addBtn.addTarget(self, action: #selector(addFaceTapped), for: .touchUpInside)
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            addBtn.widthAnchor.constraint(equalToConstant: 68),
            addBtn.heightAnchor.constraint(equalToConstant: 68),
        ])
        faceStack.addArrangedSubview(addBtn)

        updateTimeline()
        updateReadyState()
    }

    private func makeFaceCard(image: UIImage, index: Int) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 8
        iv.layer.borderWidth = 1
        iv.layer.borderColor = UIColor(white: 0.25, alpha: 1).cgColor
        iv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iv)

        let badge = UILabel()
        badge.text = "\(index + 1)"
        badge.font = .systemFont(ofSize: 11, weight: .bold)
        badge.textColor = .white
        badge.backgroundColor = UIColor(white: 0, alpha: 0.55)
        badge.textAlignment = .center
        badge.layer.cornerRadius = 10
        badge.clipsToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(badge)

        let del = UIButton(type: .system)
        del.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        del.tintColor = UIColor(white: 0.6, alpha: 1)
        del.tag = index
        del.addTarget(self, action: #selector(removeFaceTapped), for: .touchUpInside)
        del.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(del)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 68),
            container.heightAnchor.constraint(equalToConstant: 88),
            iv.topAnchor.constraint(equalTo: container.topAnchor),
            iv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            iv.heightAnchor.constraint(equalToConstant: 68),
            badge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            badge.topAnchor.constraint(equalTo: iv.bottomAnchor, constant: 2),
            badge.widthAnchor.constraint(equalToConstant: 20),
            badge.heightAnchor.constraint(equalToConstant: 20),
            del.topAnchor.constraint(equalTo: container.topAnchor, constant: -2),
            del.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 2),
        ])
        return container
    }

    @objc private func addFaceTapped() {
        let alert = UIAlertController(title: "Add Face", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Choose Photo", style: .default) { [weak self] _ in
            self?.presentImagePicker()
        })
        alert.addAction(UIAlertAction(title: "Take Photo", style: .default) { [weak self] _ in
            self?.presentCamera()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = faceStack.arrangedSubviews.last
        present(alert, animated: true)
    }

    @objc private func removeFaceTapped(_ sender: UIButton) {
        guard sender.tag < faceImages.count else { return }
        faceImages.remove(at: sender.tag)
        rebuildFaceStrip()
    }

    // MARK: - Timeline

    private func updateTimeline() {
        let segmentCount = max(0, faceImages.count - 1)
        timelineSection.isHidden = segmentCount < 1
        if segmentCount >= 1 {
            timelineView.setSegments(segmentCount)
            timelineView.totalDuration = TimeInterval(durationSlider.value)
        }
    }

    private func timelineDividersChanged() {
        let durations = timelineView.segmentDurations
        let desc = durations.enumerated()
            .map { "\($0.offset + 1)→\($0.offset + 2): \(String(format: "%.1fs", $0.element))" }
            .joined(separator: "  ")
        statusLabel.text = desc
    }

    @objc private func durationChanged() {
        let val = durationSlider.value
        durationLabel.text = String(format: "%.1fs", val)
        timelineView.totalDuration = TimeInterval(val)
        timelineView.setNeedsDisplay()
    }

    private func updateReadyState() {
        renderButton.isEnabled = faceImages.count >= 2
        if faceImages.count < 2 {
            statusLabel.text = "Add faces or import a video to begin."
        } else {
            let segs = faceImages.count - 1
            statusLabel.text = "\(faceImages.count) faces, \(segs) morph segment\(segs == 1 ? "" : "s"). Tap Render."
        }
    }

    // MARK: - Pickers

    private func presentImagePicker() {
        var cfg = PHPickerConfiguration()
        cfg.filter = .images
        cfg.selectionLimit = 0   // unlimited selection
        let picker = PHPickerViewController(configuration: cfg)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentCamera() {
        let vc = CameraCaptureController()
        vc.prompt = "Capture Face \(faceImages.count + 1)"
        vc.modalPresentationStyle = .fullScreen
        vc.onCapture = { [weak self] image in
            guard let self, let img = image else { return }
            self.faceImages.append(img)
            self.rebuildFaceStrip()
        }
        present(vc, animated: true)
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

    // MARK: - Rendering

    @objc private func renderMorph() {
        guard faceImages.count >= 2 else { return }
        renderButton.isEnabled = false
        shareButton.isEnabled = false
        progress.setProgress(0, animated: false)

        let images = faceImages
        let segDurations = timelineView.segmentDurations
        let totalDur = timelineView.totalDuration

        statusLabel.text = "Detecting landmarks\u{2026}"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.renderChain(frames: images, segmentDurations: segDurations, totalDuration: totalDur)
        }
    }

    private func renderChain(frames: [UIImage],
                             segmentDurations: [TimeInterval],
                             totalDuration: TimeInterval) {
        let normalized = frames.map { $0.normalized(to: outputSize) }

        var allPoints: [[CGPoint]] = []
        var usable: [UIImage] = []
        var usableIndices: [Int] = []
        for (i, img) in normalized.enumerated() {
            if let pts = FaceLandmarks.detect(in: img) {
                allPoints.append(pts + FaceLandmarks.boundaryAnchors(for: outputSize))
                usable.append(img)
                usableIndices.append(i)
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

        let minCount = allPoints.map(\.count).min() ?? 0
        let pointsList = allPoints.map { Array($0.prefix(minCount)) }

        var mean = Array(repeating: CGPoint.zero, count: minCount)
        for pts in pointsList {
            for i in 0..<minCount {
                mean[i].x += pts[i].x
                mean[i].y += pts[i].y
            }
        }
        let n = CGFloat(pointsList.count)
        for i in 0..<minCount { mean[i].x /= n; mean[i].y /= n }
        let triangles = Delaunay.triangulate(points: mean, canvas: outputSize)

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

        let totalPairs = usable.count - 1

        // Calculate frames per segment from timeline durations.
        // If faces were skipped, redistribute proportionally among usable pairs.
        let framesPerSegment: [Int]
        if usable.count == frames.count && segmentDurations.count == totalPairs {
            framesPerSegment = segmentDurations.map { max(2, Int($0 * Double(fps))) }
        } else {
            let perPair = max(2, Int(totalDuration / Double(totalPairs) * Double(fps)))
            framesPerSegment = Array(repeating: perPair, count: totalPairs)
        }

        let totalFrameCount = framesPerSegment.reduce(0, +)

        DispatchQueue.main.async {
            self.statusLabel.text = "Rendering \(totalPairs) morph segment\(totalPairs == 1 ? "" : "s")\u{2026}"
        }

        var globalFrameIndex = 0

        for pair in 0..<totalPairs {
            let ptsA = pointsList[pair]
            let ptsB = pointsList[pair + 1]

            guard let texA = renderer.makeTexture(from: usable[pair]),
                  let texB = renderer.makeTexture(from: usable[pair + 1]) else {
                print("Pair \(pair): texture creation failed")
                continue
            }

            let framesForPair = framesPerSegment[pair]
            for i in 0..<framesForPair {
                let raw = Double(i) / Double(max(1, framesForPair - 1))
                let t = CGFloat(0.5 - 0.5 * cos(raw * .pi))

                if let pb = renderer.renderFrame(
                    texA: texA, texB: texB,
                    pointsA: ptsA, pointsB: ptsB,
                    triangles: triangles, t: t, size: outputSize
                ) {
                    exporter.append(pixelBuffer: pb, frameIndex: globalFrameIndex)
                    globalFrameIndex += 1
                }

                DispatchQueue.main.async {
                    self.progress.setProgress(Float(globalFrameIndex) / Float(totalFrameCount), animated: false)
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
                    self.statusLabel.text = "Export failed: \(error?.localizedDescription ?? "unknown")"
                    self.renderButton.isEnabled = true
                }
                return
            }
            self.handleExportedSilentVideo(silentURL)
        }
    }

    private func handleExportedSilentVideo(_ silentURL: URL) {
        guard let audioURL = self.audioURL else {
            DispatchQueue.main.async {
                self.lastExportURL = silentURL
                self.finishExport()
            }
            return
        }

        let finalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("morph-\(Int(Date().timeIntervalSince1970)).mp4")
        DispatchQueue.main.async { self.statusLabel.text = "Adding audio\u{2026}" }

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
}

// MARK: - PHPicker

extension ViewController: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }

        // Video?
        if let item = results.first?.itemProvider,
           item.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            item.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, _ in
                guard let self, let src = url else { return }
                let dst = FileManager.default.temporaryDirectory
                    .appendingPathComponent("input-\(UUID().uuidString).mov")
                try? FileManager.default.copyItem(at: src, to: dst)

                Task {
                    do {
                        let frames = try await VideoKeyframeExtractor.extractFrames(from: dst, count: 6)
                        await MainActor.run {
                            self.faceImages = frames
                            self.rebuildFaceStrip()
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

        // Images (multi-select)
        let providers = results.compactMap { $0.itemProvider }
        var loaded = 0
        for provider in providers {
            guard provider.canLoadObject(ofClass: UIImage.self) else { loaded += 1; continue }
            provider.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
                guard let self, let img = obj as? UIImage else { return }
                DispatchQueue.main.async {
                    self.faceImages.append(img)
                    loaded += 1
                    if loaded == providers.count {
                        self.rebuildFaceStrip()
                    }
                }
            }
        }
    }
}

// MARK: - Audio picker

extension ViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let didStart = url.startAccessingSecurityScopedResource()
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("morph-audio-\(UUID().uuidString).\(url.pathExtension)")
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            self.audioURL = dest
            statusLabel.text = "Audio attached: \(url.lastPathComponent)"

            // Auto-detect audio duration and set timeline
            let asset = AVURLAsset(url: dest)
            Task {
                let dur = try? await asset.load(.duration)
                if let dur, dur.seconds > 0 {
                    await MainActor.run {
                        let secs = Float(min(dur.seconds, 60))
                        self.audioDuration = TimeInterval(secs)
                        self.durationSlider.value = secs
                        self.durationLabel.text = String(format: "%.1fs", secs)
                        self.timelineView.totalDuration = TimeInterval(secs)
                        self.timelineView.setNeedsDisplay()
                        self.statusLabel.text = "Audio attached (\(String(format: "%.1fs", secs))): \(url.lastPathComponent)"
                    }
                }
            }
        } catch {
            statusLabel.text = "Couldn't read audio: \(error.localizedDescription)"
        }
        if didStart { url.stopAccessingSecurityScopedResource() }
    }
}

// MARK: - UIImage helpers

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
