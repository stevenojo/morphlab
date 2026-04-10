//
//  TimelineView.swift
//  Draggable segment timeline for multi-image morph sequences.
//

import UIKit

final class TimelineView: UIView {

    /// Normalized divider positions (each in 0…1) between segments.
    /// For N segments there are N−1 entries.
    var dividerPositions: [CGFloat] = [] {
        didSet { setNeedsDisplay() }
    }

    var totalDuration: TimeInterval = 10.0 {
        didSet { setNeedsDisplay() }
    }

    var onChanged: (() -> Void)?

    private static let palette: [UIColor] = [
        UIColor(red: 0.29, green: 0.46, blue: 0.65, alpha: 1),
        UIColor(red: 0.44, green: 0.33, blue: 0.58, alpha: 1),
        UIColor(red: 0.24, green: 0.50, blue: 0.49, alpha: 1),
        UIColor(red: 0.55, green: 0.39, blue: 0.29, alpha: 1),
        UIColor(red: 0.34, green: 0.54, blue: 0.39, alpha: 1),
        UIColor(red: 0.50, green: 0.30, blue: 0.45, alpha: 1),
    ]

    private var draggingIndex: Int?

    var segmentCount: Int { dividerPositions.count + 1 }

    private var boundaries: [CGFloat] { [0] + dividerPositions + [1] }

    var segmentDurations: [TimeInterval] {
        let b = boundaries
        return (0..<segmentCount).map { TimeInterval(b[$0 + 1] - b[$0]) * totalDuration }
    }

    func setSegments(_ count: Int) {
        guard count >= 1 else { dividerPositions = []; return }
        dividerPositions = count == 1 ? [] : (1..<count).map { CGFloat($0) / CGFloat(count) }
        setNeedsDisplay()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        isOpaque = false
        layer.cornerRadius = 6
        clipsToBounds = true
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned)))
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        guard segmentCount > 0 else { return }
        let barH = rect.height - 18
        let b = boundaries

        for i in 0..<segmentCount {
            let x0 = b[i] * rect.width, x1 = b[i + 1] * rect.width
            let r = CGRect(x: x0, y: 0, width: x1 - x0, height: barH)
            Self.palette[i % Self.palette.count].setFill()
            UIBezierPath(rect: r).fill()

            let label = "\(i + 1) → \(i + 2)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85)
            ]
            let sz = label.size(withAttributes: attrs)
            if r.width > sz.width + 8 {
                label.draw(at: CGPoint(x: r.midX - sz.width / 2,
                                       y: r.midY - sz.height / 2),
                           withAttributes: attrs)
            }
        }

        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: UIColor(white: 0.50, alpha: 1)
        ]
        for pos in dividerPositions {
            let x = pos * rect.width
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(x: x - 1.5, y: 0, width: 3, height: barH),
                         cornerRadius: 1.5).fill()
            let t = String(format: "%.1fs", pos * CGFloat(totalDuration))
            let tsz = t.size(withAttributes: timeAttrs)
            t.draw(at: CGPoint(x: min(max(x - tsz.width / 2, 0), rect.width - tsz.width),
                               y: barH + 3), withAttributes: timeAttrs)
        }

        "0s".draw(at: CGPoint(x: 2, y: barH + 3), withAttributes: timeAttrs)
        let end = String(format: "%.1fs", totalDuration)
        let esz = end.size(withAttributes: timeAttrs)
        end.draw(at: CGPoint(x: rect.width - esz.width - 2, y: barH + 3),
                 withAttributes: timeAttrs)
    }

    // MARK: Interaction

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        let norm = g.location(in: self).x / bounds.width
        switch g.state {
        case .began:
            let loc = g.location(in: self).x
            draggingIndex = dividerPositions.enumerated()
                .filter { abs($0.element * bounds.width - loc) < 24 }
                .min(by: { abs($0.element * bounds.width - loc) <
                           abs($1.element * bounds.width - loc) })?.offset
        case .changed:
            guard let i = draggingIndex else { return }
            let gap: CGFloat = 0.03
            let lo = (i > 0 ? dividerPositions[i - 1] : 0) + gap
            let hi = (i < dividerPositions.count - 1 ? dividerPositions[i + 1] : 1) - gap
            dividerPositions[i] = min(max(norm, lo), hi)
            onChanged?()
        default:
            draggingIndex = nil
        }
    }
}
