//
//  FocusInterfaceView.swift
//  NativeCameraKit
//

import UIKit
import AVFoundation

enum FocusBehavior {
    case customFocus(resetFocusWhenMotionDetected: Bool, resetFocus: () -> Void, focusFinished: () -> Void)
    case continuousAutoFocus

    var isSubjectAreaChangeMonitoringEnabled: Bool {
        switch self {
        case let .customFocus(resetFocusWhenMotionDetected, _, _):
            return resetFocusWhenMotionDetected
        case .continuousAutoFocus:
            return false
        }
    }

    var avFocusMode: AVCaptureDevice.FocusMode {
        switch self {
        case .customFocus:
            return .autoFocus
        case .continuousAutoFocus:
            return .continuousAutoFocus
        }
    }

    var exposureMode: AVCaptureDevice.ExposureMode {
        switch self {
        case .customFocus:
            return .autoExpose
        case .continuousAutoFocus:
            return .continuousAutoExposure
        }
    }
}

protocol FocusInterfaceViewDelegate: AnyObject {
    func focus(at touchPoint: CGPoint, focusBehavior: FocusBehavior)
}

/// Owns the focus gesture, reticle, and manual-focus reset lifetime.
final class FocusInterfaceView: UIView {
    weak var delegate: FocusInterfaceViewDelegate?

    private var resetFocusTimeout = 0
    private var resetFocusWhenMotionDetected = false
    private let focusView = UIView()
    private var hideFocusViewTimer: Timer?
    private var focusResetTimer: Timer?
    private var isWaitingForFocus = false
    private var isManualFocusActive = false
    private var generation = 0
    private var focusGestureRecognizer: UITapGestureRecognizer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        focusView.backgroundColor = .clear
        focusView.layer.borderColor = UIColor.yellow.cgColor
        focusView.layer.borderWidth = 1
        focusView.isHidden = true
        addSubview(focusView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        hideFocusViewTimer?.invalidate()
        focusResetTimer?.invalidate()
    }

    func update(focusMode: FocusMode) {
        if focusMode == .on, focusGestureRecognizer == nil {
            let gesture = UITapGestureRecognizer(target: self, action: #selector(focusAndExposeTap(_:)))
            addGestureRecognizer(gesture)
            focusGestureRecognizer = gesture
        } else if focusMode == .off, let focusGestureRecognizer {
            removeGestureRecognizer(focusGestureRecognizer)
            self.focusGestureRecognizer = nil
        }
    }

    func update(resetFocusTimeout: Int) { self.resetFocusTimeout = resetFocusTimeout }
    func update(resetFocusWhenMotionDetected: Bool) {
        self.resetFocusWhenMotionDetected = resetFocusWhenMotionDetected
    }

    func focusFinished() {
        guard isManualFocusActive, isWaitingForFocus else { return }
        isWaitingForFocus = false
        guard resetFocusTimeout > 0 else { return }
        let generation = generation
        focusResetTimer = Timer.scheduledTimer(withTimeInterval: Double(resetFocusTimeout) / 1_000, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                self.resetFocus()
            }
        }
    }

    func resetFocus() {
        guard isManualFocusActive else { return }
        invalidateFocusWork()
        isManualFocusActive = false
        delegate?.focus(at: localCenter, focusBehavior: .continuousAutoFocus)
        let generation = generation
        animateReticle(at: localCenter, size: 123) { [weak self] in
            guard let self, self.generation == generation else { return }
            self.hideFocusViewTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == generation else { return }
                    UIView.animate(withDuration: 0.2, animations: {
                        self.focusView.alpha = 0
                    }, completion: { [weak self] _ in
                        guard let self, self.generation == generation else { return }
                        self.focusView.isHidden = true
                    })
                }
            }
        }
    }

    func cancelPendingFocus() {
        invalidateFocusWork()
        if isManualFocusActive {
            isManualFocusActive = false
            delegate?.focus(at: localCenter, focusBehavior: .continuousAutoFocus)
        }
        focusView.layer.removeAllAnimations()
        focusView.isHidden = true
    }

    @objc func focusAndExposeTap(_ gesture: UIGestureRecognizer) {
        invalidateFocusWork()
        isWaitingForFocus = true
        isManualFocusActive = true
        let point = gesture.location(in: self)
        let generation = generation
        animateReticle(at: point, size: 73)
        delegate?.focus(
            at: point,
            focusBehavior: .customFocus(
                resetFocusWhenMotionDetected: resetFocusWhenMotionDetected,
                resetFocus: { [weak self] in
                    DispatchQueue.main.async {
                        guard let self, self.generation == generation else { return }
                        self.resetFocus()
                    }
                },
                focusFinished: { [weak self] in
                    DispatchQueue.main.async {
                        guard let self, self.generation == generation else { return }
                        self.focusFinished()
                    }
                }
            )
        )
    }

    private var localCenter: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    private func invalidateFocusWork() {
        generation += 1
        isWaitingForFocus = false
        focusResetTimer?.invalidate()
        focusResetTimer = nil
        hideFocusViewTimer?.invalidate()
        hideFocusViewTimer = nil
    }

    private func animateReticle(at point: CGPoint, size: CGFloat, completion: (() -> Void)? = nil) {
        focusView.layer.removeAllAnimations()
        focusView.alpha = 0
        focusView.isHidden = false
        focusView.frame = CGRect(x: point.x - size, y: point.y - size, width: size * 2, height: size * 2)
        UIView.animate(withDuration: 0.2, animations: {
            self.focusView.frame = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
            self.focusView.alpha = 1
        }, completion: { finished in
            if finished { completion?() }
        })
    }
}
