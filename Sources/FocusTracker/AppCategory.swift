import Foundation

/// Maps a running app to a focus category by bundle id / name.
///
/// v1 limitation: browsers are categorized as `.neutral` because we can't
/// see the active tab without Accessibility permission. When tab-level
/// tracking lands, web domains can be categorized here instead.
enum AppCatalog {
    static func category(bundleId: String?, name: String) -> AppCategory {
        let b = (bundleId ?? "").lowercased()
        let n = name.lowercased()
        func has(_ needles: [String]) -> Bool {
            needles.contains { b.contains($0) || n.contains($0) }
        }

        // Order matters: deep-work check runs first so "Xcode" never trips an "x" rule.
        if has(["vscode", "visual studio code", "xcode", "jetbrains", "pycharm",
                "intellij", "webstorm", "goland", "clion", "rubymine",
                "sublime", "cursor", "zed", "nova", "neovim", "vim", "emacs",
                "iterm", "terminal", "warp", "alacritty", "kitty", "ghostty",
                "figma", "sketch", "framer", "obsidian", "logseq",
                "photoshop", "illustrator", "indesign", "affinity",
                "logic", "ableton", "final cut", "davinci", "premiere",
                "blender", "godot", "unity", "unreal"]) {
            return .deepWork
        }
        if has(["slack", "discord", "zoom", "teams", "telegram", "outlook",
                "whatsapp", "facetime", "webex", "skype", "signal"]) {
            return .communication
        }
        // Apple Mail / Messages need exact-ish matches to avoid false hits.
        if b == "com.apple.mail" || n == "mail" { return .communication }
        if b == "com.apple.mobilesms" || n == "messages" { return .communication }

        if has(["twitter", "x.com", "tweetbot", "reddit", "tiktok",
                "instagram", "facebook", "youtube", "netflix", "twitch",
                "hbo", "disney"]) {
            return .distraction
        }
        return .neutral
    }

    /// Categorizes a browser tab by its domain. Easy to extend — add hosts below.
    static func categoryForDomain(_ host: String) -> AppCategory {
        let h = host.lowercased()
        // Matches the domain itself or any subdomain of it.
        func eq(_ d: String) -> Bool { h == d || h.hasSuffix("." + d) }

        // Communication (specific subdomains first).
        if h == "mail.google.com" || h.hasPrefix("outlook.") || eq("slack.com")
            || eq("discord.com") || h == "web.whatsapp.com" || h == "teams.microsoft.com"
            || h == "calendar.google.com" || eq("messenger.com") || eq("front.com") {
            return .communication
        }
        // Distraction.
        if eq("twitter.com") || eq("x.com") || eq("reddit.com") || eq("youtube.com")
            || eq("tiktok.com") || eq("instagram.com") || eq("facebook.com") || eq("netflix.com")
            || eq("twitch.tv") || eq("9gag.com") || eq("hulu.com") || eq("primevideo.com")
            || eq("pinterest.com") || eq("threads.net") {
            return .distraction
        }
        // Deep work.
        if eq("github.com") || eq("gitlab.com") || eq("bitbucket.org") || eq("stackoverflow.com")
            || eq("stackexchange.com") || h == "developer.mozilla.org" || h.contains("readthedocs")
            || eq("figma.com") || eq("codesandbox.io") || eq("replit.com") || eq("notion.so")
            || eq("linear.app") || h.contains("atlassian.net") || eq("vercel.com") || eq("netlify.com")
            || h == "docs.google.com" || h == "colab.research.google.com" || eq("overleaf.com")
            || eq("claude.ai") || h == "chat.openai.com" || eq("chatgpt.com") || eq("leetcode.com")
            || h == "localhost" || h == "127.0.0.1" {
            return .deepWork
        }

        // Heuristic: catch random streaming / piracy / gaming / gambling / adult
        // sites by name pattern (watchluna.com, freemovies.cc, slots-vegas, …),
        // since they'll never be in the explicit lists above.
        func hasAny(_ needles: [String]) -> Bool { needles.contains { h.contains($0) } }
        if h.hasSuffix(".tv") || hasAny([
            "watch", "movie", "flix", "tube", "anime", "manga", "hentai", "cartoon",
            "putlocker", "123movie", "soap2day", "fmovies", "gomovies", "yesmovies",
            "solarmovie", "primewire", "couchtuner", "lookmovie", "sflix", "hdtoday", "myflixer",
            "porn", "xxx", "xnxx", "xvideos", "redtube", "onlyfans", "nsfw", "camgirl",
            "casino", "gambl", "poker", "slots", "roulette", "bet365", "betting", "sportsbook",
            "game", "gaming",
        ]) {
            return .distraction
        }
        return .neutral
    }
}
