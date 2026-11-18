import PressTransCore

func checkStreamedAnswer() {
    // Check the limit against Swift's grapheme segmentation, including at fragment boundaries.
    let fragments = ["中", "e", "\u{301}", "🇨", "🇳", "👩", "\u{200D}", "💻", "\r", "\n", "!", ""]
    for limit in 0...8 {
        var actual = StreamedAnswer(characterLimit: limit)
        var expected = ""
        for fragment in fragments {
            let candidate = expected + fragment
            let accepted = candidate.count <= limit
            precondition(actual.append(fragment) == accepted)
            if accepted { expected = candidate }
            precondition(actual.text == expected)
        }
    }
    var full = StreamedAnswer()
    let text = String(repeating: "译", count: 12_000)
    precondition(full.append(text))
    precondition(!full.append("。") && full.text == text)
}
