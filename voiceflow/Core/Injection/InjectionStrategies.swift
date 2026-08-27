import AppKit

struct TerminalPasteStrategy: TextInjectionStrategy {
    let name = "terminal_paste"
    private let textPaster: TextPasting

    init(textPaster: TextPasting) {
        self.textPaster = textPaster
    }

    func canHandle(context: InjectionContext) -> Bool {
        context.isTerminalTarget && context.isFrontmostTarget
    }

    func inject(text: String, context: InjectionContext) throws {
        guard context.isStillFrontmost() else {
            throw TextInjector.TextInjectionError.targetNoLongerFrontmost
        }
        try textPaster.paste(text: text, moveCaretToEndOfLine: true)
    }
}

struct AccessibilityValueStrategy: TextInjectionStrategy {
    let name: String

    init(name: String = "accessibility_api") {
        self.name = name
    }

    func canHandle(context: InjectionContext) -> Bool {
        true
    }

    func inject(text: String, context: InjectionContext) throws {
        try TextInjector.injectUsingAccessibilityAPI(text: text, into: context.targetApp)
    }
}

struct ClipboardPasteStrategy: TextInjectionStrategy {
    let name = "copy_then_command_v"
    private let textPaster: TextPasting

    init(textPaster: TextPasting) {
        self.textPaster = textPaster
    }

    func canHandle(context: InjectionContext) -> Bool {
        TextInjector.shouldUseClipboardPasteFallback(
            isTerminalTarget: context.isTerminalTarget,
            isFrontmostTarget: context.isFrontmostTarget
        )
    }

    func inject(text: String, context: InjectionContext) throws {
        guard context.isStillFrontmost() else {
            throw TextInjector.TextInjectionError.targetNoLongerFrontmost
        }
        try textPaster.paste(text: text, moveCaretToEndOfLine: false)
    }
}

struct KeyboardTypingStrategy: TextInjectionStrategy {
    let name = "keyboard_events"
    private let keyboardEventPoster: KeyboardEventPosting

    init(keyboardEventPoster: KeyboardEventPosting) {
        self.keyboardEventPoster = keyboardEventPoster
    }

    func canHandle(context: InjectionContext) -> Bool {
        true
    }

    func inject(text: String, context: InjectionContext) throws {
        try keyboardEventPoster.post(
            text: text,
            to: context.processIdentifier,
            preferFrontmostSession: context.isTerminalTarget && context.isFrontmostTarget
        )
    }
}
