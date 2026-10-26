import Foundation

/// Which links in Claude's text may be opened: web links only, so the text can't launch other
/// apps, files or scripts.
public enum LinkPolicy {
    public static func isOpenable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// Whether a link stays a link: links are on, and it may be opened.
    public static func keeps(_ url: URL, linksEnabled: Bool) -> Bool {
        linksEnabled && isOpenable(url)
    }
}
