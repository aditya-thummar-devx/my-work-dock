import Lottie
import SwiftUI

extension LottieColor {
    /// A SwiftUI colour as the sRGB numbers the app's tints are defined in (Lottie reads device RGB unless told otherwise).
    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(r: c.redComponent, g: c.greenComponent, b: c.blueComponent, a: c.alphaComponent)
    }
}

private enum BuddyLottieConfig {
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    /// The render server runs the animation: the app does nothing between frames (unlike SwiftUI, which wakes it for every one).
    static let live = LottieConfiguration(renderingEngine: .coreAnimation, colorSpace: srgb, reducedMotionOption: .standardMotion)
    /// Draws one frame into a bitmap; the Core Animation engine's layers only show while they play.
    static let still = LottieConfiguration(renderingEngine: .mainThread, colorSpace: srgb, reducedMotionOption: .standardMotion)
    static let tintKeypath = AnimationKeypath(keypath: "**.tint.Color")
}

/// A buddy animation playing, drawn by Lottie's Core Animation engine. Tint, speed and loop mode follow the SwiftUI side.
struct LottieBuddy: NSViewRepresentable {
    var asset: BuddyAsset
    var tint: Color
    var speed = 1.0
    var loops = LottieLoopMode.loop

    /// Lottie takes its main-thread engine instead when a file uses something the Core Animation engine cannot draw (and only logs
    /// it); that would wake the app for every frame. True when this file is drawn by the render server.
    @MainActor static func usesCoreAnimation(_ asset: BuddyAsset) -> Bool {
        guard let animation = asset.animation, let layer = LottieAnimationView(animation: animation, configuration: BuddyLottieConfig.live).layer else { return false }
        func types(_ l: CALayer) -> [String] { [String(describing: type(of: l))] + (l.sublayers ?? []).flatMap(types) }
        let all = types(layer)
        return all.contains("CoreAnimationLayer") && !all.contains("MainThreadAnimationLayer")
    }

    func makeNSView(context: Context) -> Host { Host(size: asset.size) }

    func updateNSView(_ host: Host, context: Context) { host.show(self) }

    /// The composition's own size: without this SwiftUI sizes the view before the animation is loaded, to nothing.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Host, context: Context) -> CGSize? { asset.size }

    final class Host: NSView {
        private var animationView: LottieAnimationView?
        private var shown: LottieBuddy?
        private var size: CGSize

        init(size: CGSize) {
            self.size = size
            super.init(frame: NSRect(origin: .zero, size: size))
            wantsLayer = true
        }

        required init?(coder: NSCoder) { nil }

        override var intrinsicContentSize: NSSize { size }

        /// Clicks fall through to the notch's own tap gesture.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// The animation fills this view. (An autoresizing mask would grow it by the whole new size when SwiftUI sizes this view up
        /// from nothing, and the buddy would sit in the corner at twice its size.)
        override func resizeSubviews(withOldSize oldSize: NSSize) { animationView?.frame = bounds }

        func show(_ buddy: LottieBuddy) {
            if shown?.asset != buddy.asset || shown?.loops != buddy.loops { replace(with: buddy) }
            if shown?.tint != buddy.tint {
                animationView?.setValueProvider(ColorValueProvider(LottieColor(buddy.tint)), keypath: BuddyLottieConfig.tintKeypath)
            }
            if shown?.speed != buddy.speed { animationView?.animationSpeed = buddy.speed }
            shown = buddy
        }

        private func replace(with buddy: LottieBuddy) {
            animationView?.removeFromSuperview()
            animationView = nil
            shown = nil // the new view takes tint and speed again
            guard let animation = buddy.asset.animation else { return }
            let view = LottieAnimationView(animation: animation, configuration: BuddyLottieConfig.live)
            view.loopMode = buddy.loops
            view.frame = bounds
            view.setValueProvider(ColorValueProvider(LottieColor(buddy.tint)), keypath: BuddyLottieConfig.tintKeypath)
            addSubview(view)
            view.play()
            animationView = view
            size = animation.size
            invalidateIntrinsicContentSize()
        }
    }
}

/// A buddy at rest: the first frame of its animation, drawn once into an image. Still, Reduce Motion, a sleeping screen and snapshots
/// show this (ImageRenderer cannot draw AppKit views, and nothing needs to run for a frame that does not move).
@MainActor
enum BuddyStill {
    private static var images: [String: NSImage] = [:]

    static func image(_ asset: BuddyAsset, tint: Color) -> NSImage? {
        let c = NSColor(tint).usingColorSpace(.sRGB) ?? .black
        let key = "\(asset.file) \(c.redComponent) \(c.greenComponent) \(c.blueComponent) \(c.alphaComponent)"
        if let image = images[key] { return image }
        guard let animation = asset.animation else { return nil }
        let view = LottieAnimationView(animation: animation, configuration: BuddyLottieConfig.still)
        view.frame = CGRect(origin: .zero, size: animation.size)
        view.setValueProvider(ColorValueProvider(LottieColor(tint)), keypath: BuddyLottieConfig.tintKeypath)
        view.currentProgress = 0
        view.layoutSubtreeIfNeeded()
        let scale = 3 // sharp on a 2x display and on a 3x one
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(animation.size.width) * scale, pixelsHigh: Int(animation.size.height) * scale,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = animation.size
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: animation.size)
        image.addRepresentation(rep)
        images[key] = image
        return image
    }
}

/// `BuddyStill` as a view.
struct BuddyStillView: View {
    var asset: BuddyAsset
    var tint: Color

    var body: some View {
        if let image = BuddyStill.image(asset, tint: tint) { Image(nsImage: image) }
    }
}
