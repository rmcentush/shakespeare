enum SmartQuotes {
    static func smarten(_ text: String, contextBefore: Character? = nil) -> String {
        guard !text.isEmpty else { return text }

        var result = ""
        result.reserveCapacity(text.count)

        let characters = Array(text)
        for index in characters.indices {
            let character = characters[index]
            let previousCharacter = result.last ?? contextBefore

            if isDoubleQuote(character) {
                let quote = shouldOpenDoubleQuote(
                    in: characters,
                    at: index,
                    previousCharacter: previousCharacter
                ) ? "\u{201c}" : "\u{201d}"
                result.append(quote)
            } else if isSingleQuote(character) {
                let quote = shouldOpenSingleQuote(
                    in: characters,
                    at: index,
                    previousCharacter: previousCharacter
                ) ? "\u{2018}" : "\u{2019}"
                result.append(quote)
            } else {
                result.append(character)
            }
        }

        return result
    }

    private static func shouldOpenDoubleQuote(
        in characters: [Character],
        at index: Int,
        previousCharacter: Character?
    ) -> Bool {
        guard let nextCharacter = nextCharacter(in: characters, at: index) else {
            return isOpeningQuoteContext(previousCharacter)
        }
        guard !nextCharacter.isWhitespace else { return false }

        return isOpeningQuoteContext(previousCharacter)
    }

    private static func shouldOpenSingleQuote(
        in characters: [Character],
        at index: Int,
        previousCharacter: Character?
    ) -> Bool {
        if previousCharacter?.isLetter == true || previousCharacter?.isNumber == true { return false }
        guard let nextCharacter = nextCharacter(in: characters, at: index) else {
            return isOpeningQuoteContext(previousCharacter)
        }
        guard !nextCharacter.isWhitespace else { return false }

        if nextCharacter.isNumber { return false }
        if startsWithApostropheElision(characters.suffix(from: index + 1)) { return false }

        return isOpeningQuoteContext(previousCharacter)
    }

    private static func nextCharacter(in characters: [Character], at index: Int) -> Character? {
        let nextIndex = index + 1
        guard nextIndex < characters.count else { return nil }
        return characters[nextIndex]
    }

    private static func isDoubleQuote(_ character: Character) -> Bool {
        character == "\"" || character == "\u{201c}" || character == "\u{201d}"
    }

    private static func isSingleQuote(_ character: Character) -> Bool {
        character == "'" || character == "\u{2018}" || character == "\u{2019}"
    }

    private static func isOpeningQuoteContext(_ character: Character?) -> Bool {
        guard let character else { return true }
        if character.isWhitespace { return true }
        if "([{<-\u{2013}\u{2014}\u{201c}\u{2018}".contains(character) { return true }
        return false
    }

    private static func startsWithApostropheElision(_ suffix: ArraySlice<Character>) -> Bool {
        let text = String(suffix).lowercased()
        if text.range(of: #"^[a-z]'"#, options: .regularExpression) != nil {
            return true
        }

        return [
            "tis",
            "twas",
            "twere",
            "cause",
            "cuz",
            "em",
            "til",
            "bout",
            "round",
        ].contains { text.hasPrefix($0) }
    }
}
