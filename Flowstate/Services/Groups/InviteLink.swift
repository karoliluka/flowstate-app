import Foundation

/// Study group invites: https://<web host>/join/CODE once the web page is live, flowstate://join/CODE until then.
enum InviteLink {
    /// The invite web page (web/ on Vercel). With the Associated Domain, its links open the app directly.
    /// Set to nil to fall back to flowstate:// links plus the code to type in.
    static let webHost: String? = "flowstate.lukakaroli.si"

    static func url(for code: String) -> URL {
        if let webHost, let url = URL(string: "https://\(webHost)/join/\(code)") { return url }
        return URL(string: "flowstate://join/\(code)")!
    }

    static func shareMessage(groupName: String, code: String) -> String {
        if webHost != nil {
            return "Join my study group \"\(groupName)\" on flowstate: \(url(for: code).absoluteString)"
        }
        return "Join my study group \"\(groupName)\" on flowstate. Open \(url(for: code).absoluteString) or enter the code \(code) in flowstate → Groups."
    }

    /// The code from an opened link: flowstate://join/CODE or https://any-host/join/CODE.
    static func code(from url: URL) -> String? {
        let parts = ([url.host] + url.pathComponents).compactMap { $0 }.filter { $0 != "/" }
        guard let index = parts.firstIndex(where: { $0.lowercased() == "join" }), index + 1 < parts.count else { return nil }
        return normalizedCode(parts[index + 1])
    }

    /// Accepts whatever gets pasted or typed (Postel's law): a full link, a message containing
    /// one, or just the code, in any case and with stray spaces.
    static func code(fromText text: String) -> String? {
        for word in text.split(whereSeparator: { $0.isWhitespace || $0 == "\"" }) {
            let trimmed = word.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:()<>"))
            if let url = URL(string: trimmed), url.scheme != nil, let code = code(from: url) { return code }
        }
        return normalizedCode(text)
    }

    /// Codes are 8 letters and digits; anything else isn't one.
    static func normalizedCode(_ raw: String) -> String? {
        let code = raw.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard (6...12).contains(code.count), code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return code
    }
}
