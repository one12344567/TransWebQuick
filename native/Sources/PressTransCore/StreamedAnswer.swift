/// Accumulates provider deltas while enforcing the answer limit in extended grapheme clusters.
public struct StreamedAnswer {
    public private(set) var text = ""

    private let characterLimit: Int
    private var characterUpperBound = 0

    public init(characterLimit: Int = 12_000) {
        precondition(characterLimit >= 0)
        self.characterLimit = characterLimit
    }

    /// Rejects an oversized delta without discarding the last valid answer.
    public mutating func append(_ delta: String) -> Bool {
        // Each new byte adds at most one character. Most fragments therefore don't require
        // a Unicode segmentation pass over the text already on screen.
        let bytes = delta.utf8.count
        if bytes <= characterLimit - characterUpperBound {
            text.append(delta)
            characterUpperBound += bytes
            return true
        }

        // Count after joining: a fragment can complete an emoji, accent or flag from the last one.
        let candidate = text + delta
        let count = candidate.count
        guard count <= characterLimit else { return false }
        text = candidate
        characterUpperBound = count
        return true
    }
}
