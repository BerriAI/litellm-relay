import SwiftUI
import AppKit

/// Renders a coding-agent brand logo from a bundled SVG resource, with a
/// graceful rounded-square fallback chip when the resource is missing or
/// fails to load.
///
/// SVG resources are shipped as SwiftPM resources and resolved via
/// `Bundle.module`. The lobehub SVGs declare `width="1em" height="1em"`
/// with a `0 0 24 24` viewBox, so `NSImage(contentsOf:)` can report a
/// zero size; we always assign an explicit `image.size` after loading.
struct AgentIcon: View {

    // MARK: Stored properties

    /// SVG basename WITHOUT extension, e.g. "claudecode-color". `nil` => fallback chip.
    let resource: String?
    /// Text shown in the fallback chip, e.g. "DR".
    let fallback: String
    /// Rendered edge length in points.
    var size: CGFloat = 26

    // MARK: Init

    init(resource: String?, fallback: String, size: CGFloat = 26) {
        self.resource = resource
        self.fallback = fallback
        self.size = size
    }

    // MARK: Body

    var body: some View {
        if let resource, let image = AgentIcon.loadImage(resource: resource, size: size) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            fallbackChip
        }
    }

    // MARK: Fallback

    private var fallbackChip: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(Color.primary.opacity(0.12))
            .overlay(
                Text(fallback)
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundColor(.primary.opacity(0.85))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(size * 0.12)
            )
            .frame(width: size, height: size)
    }

    // MARK: Image loading + cache

    /// Thread-safe cache of loaded, sized `NSImage`s keyed by "resource@size".
    private static let cacheLock = NSLock()
    private static var cache: [String: NSImage] = [:]

    /// Loads and sizes an SVG from `Bundle.module`, caching the result.
    /// Returns `nil` on any missing-resource / load failure; never crashes.
    static func loadImage(resource: String, size: CGFloat) -> NSImage? {
        let key = "\(resource)@\(size)"

        cacheLock.lock()
        if let cached = cache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let url = Bundle.module.url(forResource: resource, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }

        // lobehub SVGs use 1em sizing and can report a 0x0 size; force an
        // explicit render size so the image is actually visible.
        image.size = NSSize(width: size, height: size)

        cacheLock.lock()
        cache[key] = image
        cacheLock.unlock()

        return image
    }
}
