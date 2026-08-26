//
//  TextInjector.swift
//  VoiceFlow
//

import ApplicationServices
import AppKit
import Foundation
import OSLog

protocol KeyboardEventPosting {
    func post(text: String, to processIdentifier: pid_t) throws
    func post(text: String, to processIdentifier: pid_t, preferFrontmostSession: Bool) throws
}

extension KeyboardEventPosting {
    func post(text: String, to processIdentifier: pid_t, preferFrontmostSession: Bool) throws {
        try post(text: text, to: processIdentifier)
    }
}

protocol TextPasting: AnyObject {
    func paste(text: String) throws
    func paste(text: String, moveCaretToEndOfLine: Bool) throws
}

extension TextPasting {
    func paste(text: String, moveCaretToEndOfLine: Bool) throws {
        try paste(text: text)
    }
}

protocol TextInjecting: AnyObject {
    var isAccessibilityPermissionGranted: Bool { get }
    func requestAccessibilityPermission()
    func inject(text: String, into targetApp: NSRunningApplication?) throws
}

protocol TextInputAvailabilityChecking: AnyObject {
    func hasTextInput(in targetApp: NSRunningApplication) -> Bool
}

protocol ClipboardWriting: AnyObject {
    func copy(text: String) throws
}

final class SystemClipboardWriter: ClipboardWriting {
    enum ClipboardError: Error {
        case clearFailed
        case writeFailed
    }

    func copy(text: String) throws {
        guard NSPasteboard.general.clearContents() != 0 else {
            throw ClipboardError.clearFailed
        }
        guard NSPasteboard.general.setString(text, forType: .string) else {
            throw ClipboardError.writeFailed
        }
    }
}

protocol FocusedTextSelectionReading: AnyObject {
    func selectedText(in targetApp: NSRunningApplication?) throws -> String?
}

final class SystemTextPaster: TextPasting {
    private let clipboardWriter: ClipboardWriting
    private let pasteCommandPoster: PasteCommandPosting
    private let pasteboard: NSPasteboard
    private let restoreDelay: TimeInterval

    init(
        clipboardWriter: ClipboardWriting = SystemClipboardWriter(),
        pasteCommandPoster: PasteCommandPosting = CGEventPasteCommandPoster(),
        pasteboard: NSPasteboard = .general,
        restoreDelay: TimeInterval = 0.05
    ) {
        self.clipboardWriter = clipboardWriter
        self.pasteCommandPoster = pasteCommandPoster
        self.pasteboard = pasteboard
        self.restoreDelay = restoreDelay
    }

    func paste(text: String) throws {
        try paste(text: text, moveCaretToEndOfLine: false)
    }

    func paste(text: String, moveCaretToEndOfLine: Bool) throws {
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        try clipboardWriter.copy(text: text)
        do {
            try pasteCommandPoster.postPasteCommand()
            Thread.sleep(forTimeInterval: restoreDelay)
            if moveCaretToEndOfLine {
                try pasteCommandPoster.postEndOfLineCommand()
                Thread.sleep(forTimeInterval: restoreDelay)
            }
            snapshot.restore(to: pasteboard)
        } catch {
            snapshot.restore(to: pasteboard)
            throw error
        }
    }
}

private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            })
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        for itemData in items {
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }
}

protocol PasteCommandPosting {
    func postPasteCommand() throws
    func postEndOfLineCommand() throws
}

extension PasteCommandPosting {
    func postEndOfLineCommand() throws {}
}

private struct CGEventPasteCommandPoster: PasteCommandPosting {
    func postPasteCommand() throws {
        guard let eventSource = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x09, keyDown: false) else {
            throw TextInjector.TextInjectionError.eventCreationFailed
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    func postEndOfLineCommand() throws {
        guard let eventSource = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x0E, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x0E, keyDown: false) else {
            throw TextInjector.TextInjectionError.eventCreationFailed
        }
        keyDown.flags = .maskControl
        keyUp.flags = .maskControl
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

final class TextInjector: TextInjecting, FocusedTextSelectionReading, TextInputAvailabilityChecking {
    private let keyboardEventPoster: KeyboardEventPosting
    private let textPaster: TextPasting
    private let permissionChecker: () -> Bool
    private let permissionRequester: () -> Void
    private let bundleIdentifierProvider: (NSRunningApplication) -> String?
    private let frontmostApplicationProvider: (NSRunningApplication) -> Bool

    var isAccessibilityPermissionGranted: Bool {
        permissionChecker()
    }

    init(
        keyboardEventPoster: KeyboardEventPosting = CGEventKeyboardEventPoster(),
        textPaster: TextPasting = SystemTextPaster(),
        permissionChecker: @escaping () -> Bool = { AXIsProcessTrusted() },
        bundleIdentifierProvider: @escaping (NSRunningApplication) -> String? = { $0.bundleIdentifier },
        frontmostApplicationProvider: @escaping (NSRunningApplication) -> Bool = { application in
            NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier
        },
        permissionRequester: @escaping () -> Void = {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    ) {
        self.keyboardEventPoster = keyboardEventPoster
        self.textPaster = textPaster
        self.permissionChecker = permissionChecker
        self.permissionRequester = permissionRequester
        self.bundleIdentifierProvider = bundleIdentifierProvider
        self.frontmostApplicationProvider = frontmostApplicationProvider
    }

    func requestAccessibilityPermission() {
        permissionRequester()
    }

    func hasTextInput(in targetApp: NSRunningApplication) -> Bool {
        guard targetApp.processIdentifier != 0,
              isAccessibilityPermissionGranted else {
            return false
        }
        if Self.usesFrontmostKeyboardEvents(for: targetApp.bundleIdentifier) {
            return true
        }
        guard let focusedElement = try? focusedElement(in: targetApp) else {
            return false
        }

        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXRoleAttribute as CFString,
            &roleValue
        )
        let role = roleResult == .success ? roleValue as? String : nil

        var enabledValue: CFTypeRef?
        let enabledResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXEnabledAttribute as CFString,
            &enabledValue
        )
        let isEnabled = enabledResult == .success ? enabledValue as? Bool : nil

        var value: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &value
        )
        let hasStringValue = valueResult == .success && value is String

        var isSettable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(
            focusedElement,
            kAXValueAttribute as CFString,
            &isSettable
        )
        let valueIsSettable = settableResult == .success ? isSettable.boolValue : nil

        var selectedRange: CFTypeRef?
        let hasSelectedTextRange = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        ) == .success

        return Self.isSupportedTextInput(
            role: role,
            hasStringValue: hasStringValue,
            valueIsSettable: valueIsSettable,
            hasSelectedTextRange: hasSelectedTextRange,
            isEnabled: isEnabled
        )
    }

    static func isSupportedTextInput(
        role: String?,
        hasStringValue: Bool,
        valueIsSettable: Bool?,
        hasSelectedTextRange: Bool,
        isEnabled: Bool?
    ) -> Bool {
        guard isEnabled != false else {
            return false
        }

        if valueIsSettable == false {
            return false
        }

        if hasSelectedTextRange {
            return true
        }

        if valueIsSettable == true {
            return hasStringValue
        }

        guard hasStringValue else {
            return false
        }

        // Some standard controls expose a string AXValue but do not answer
        // the settable query reliably. Their role is a safer signal than
        // treating every string-valued accessibility element as editable.
        return [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            "AXSearchField",
            "AXSecureTextField",
            "AXTokenField"
        ].contains(role)
    }

    func selectedText(in targetApp: NSRunningApplication?) throws -> String? {
        guard let targetApp else {
            throw TextInjectionError.targetApplicationUnavailable
        }
        guard targetApp.processIdentifier > 0 else {
            throw TextInjectionError.targetApplicationUnavailable
        }
        guard isAccessibilityPermissionGranted else {
            requestAccessibilityPermission()
            throw TextInjectionError.accessibilityPermissionDenied
        }

        let focusedElement = try focusedElement(in: targetApp)
        var selectedValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        )
        if result == .success,
           let selectedText = selectedValue as? String,
           let nonEmptyText = Self.nonEmptySelectedText(selectedText) {
            return nonEmptyText
        }

        // Some native and web-backed controls expose AXValue and
        // AXSelectedTextRange but omit AXSelectedText. Derive the selection
        // from the same UTF-16 range used by the injection path.
        var currentValue: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &currentValue
        )
        guard valueResult == .success,
              let currentText = currentValue as? String else {
            return nil
        }

        let range = try selectedTextRange(
            in: focusedElement,
            textLength: (currentText as NSString).length
        )
        return Self.selectedText(from: currentText, range: range)
    }

    static func usesFrontmostKeyboardEvents(for bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "io.alacritty",
            "com.mitchellh.ghostty",
            "net.kovidgoyal.kitty",
            "org.wezfurlong.wezterm"
        ].contains(bundleIdentifier)
    }

    static func shouldUseClipboardPasteFallback(
        isTerminalTarget: Bool,
        isFrontmostTarget: Bool
    ) -> Bool {
        isFrontmostTarget && !isTerminalTarget
    }

    static func endCaretLocation(
        existingText: String,
        selectedRange: NSRange,
        replacement: String
    ) -> Int {
        let textLength = (existingText as NSString).length
        let location = min(max(selectedRange.location, 0), textLength)
        let length = min(max(selectedRange.length, 0), textLength - location)
        return textLength - length + (replacement as NSString).length
    }

    static func selectedText(from value: String, range: NSRange) -> String? {
        let value = value as NSString
        guard range.location >= 0,
              range.length > 0,
              range.location <= value.length,
              range.length <= value.length - range.location else {
            return nil
        }
        return nonEmptySelectedText(value.substring(with: range))
    }

    private static func nonEmptySelectedText(_ text: String) -> String? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    func inject(text: String, into targetApp: NSRunningApplication?) throws {
        guard !text.isEmpty else {
            throw TextInjectionError.emptyText
        }
        guard let targetApp else {
            throw TextInjectionError.targetApplicationUnavailable
        }

        let processIdentifier = targetApp.processIdentifier
        guard processIdentifier > 0 else {
            throw TextInjectionError.targetApplicationUnavailable
        }

        let accessibilityTrusted = self.isAccessibilityPermissionGranted
        VoiceFlowLog.pipeline.info("text_injection_target process_id=\(processIdentifier, privacy: .public) bundle_identifier=\(targetApp.bundleIdentifier ?? "<unknown>", privacy: .public) accessibility_trusted=\(accessibilityTrusted, privacy: .public)")

        guard accessibilityTrusted else {
            VoiceFlowLog.pipeline.error("text_injection_permission_missing process_id=\(processIdentifier, privacy: .public) bundle_identifier=\(targetApp.bundleIdentifier ?? "<unknown>", privacy: .public)")
            requestAccessibilityPermission()
            throw TextInjectionError.accessibilityPermissionDenied
        }

        let isTerminalTarget = Self.usesFrontmostKeyboardEvents(for: bundleIdentifierProvider(targetApp))
        let isFrontmostTarget = frontmostApplicationProvider(targetApp)
        if isTerminalTarget && isFrontmostTarget {
            do {
                try textPaster.paste(text: text, moveCaretToEndOfLine: true)
                VoiceFlowLog.pipeline.info("text_injection_method_succeeded method=terminal_paste")
                return
            } catch {
                VoiceFlowLog.pipeline.error("text_injection_method_failed method=terminal_paste error=\(String(describing: error), privacy: .public)")
            }
        }

        if accessibilityTrusted {
            do {
                try injectUsingAccessibilityAPI(text: text, into: targetApp)
                VoiceFlowLog.pipeline.info("text_injection_method_succeeded method=accessibility_api")
                return
            } catch {
                VoiceFlowLog.pipeline.error("text_injection_method_failed method=accessibility_api error=\(String(describing: error), privacy: .public)")
            }
        }

        if Self.shouldUseClipboardPasteFallback(
            isTerminalTarget: isTerminalTarget,
            isFrontmostTarget: isFrontmostTarget
        ) {
            do {
                try textPaster.paste(text: text, moveCaretToEndOfLine: false)
                VoiceFlowLog.pipeline.info("text_injection_method_succeeded method=clipboard_paste_fallback")
                return
            } catch {
                VoiceFlowLog.pipeline.error("text_injection_method_failed method=clipboard_paste_fallback error=\(String(describing: error), privacy: .public)")
            }
        }

        do {
            let useFrontmostSession = isTerminalTarget && isFrontmostTarget
            try keyboardEventPoster.post(
                text: text,
                to: processIdentifier,
                preferFrontmostSession: useFrontmostSession
            )
            VoiceFlowLog.pipeline.info("text_injection_method_succeeded method=keyboard_events frontmost_session=\(useFrontmostSession, privacy: .public)")
        } catch {
            do {
                try injectUsingAccessibilityAPI(text: text, into: targetApp)
                VoiceFlowLog.pipeline.info("text_injection_method_succeeded method=accessibility_api_fallback")
            } catch let fallbackError as TextInjectionError {
                throw fallbackError
            } catch {
                throw TextInjectionError.injectionFailed(underlying: error)
            }
        }
    }

    private func injectUsingAccessibilityAPI(
        text: String,
        into targetApp: NSRunningApplication
    ) throws {
        guard isAccessibilityPermissionGranted else {
            requestAccessibilityPermission()
            throw TextInjectionError.accessibilityPermissionDenied
        }

        let focusedElement = try focusedElement(in: targetApp)
        var currentValue: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &currentValue
        )
        guard valueResult == .success else {
            throw TextInjectionError.focusedValueUnavailable(status: valueResult)
        }

        let existingText = currentValue as? String ?? ""
        let existingNSString = existingText as NSString
        let selectedRange = try selectedTextRange(in: focusedElement, textLength: existingNSString.length)
        let replacementRange = NSRange(
            location: selectedRange.location,
            length: selectedRange.length
        )
        let updatedText = existingNSString.replacingCharacters(in: replacementRange, with: text)
        guard AXUIElementSetAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            updatedText as CFTypeRef
        ) == .success else {
            throw TextInjectionError.accessibilityValueUpdateFailed
        }

        var caret = CFRange(
            location: Self.endCaretLocation(
                existingText: existingText,
                selectedRange: selectedRange,
                replacement: text
            ),
            length: 0
        )
        if let caretValue = AXValueCreate(.cfRange, &caret) {
            _ = AXUIElementSetAttributeValue(
                focusedElement,
                kAXSelectedTextRangeAttribute as CFString,
                caretValue
            )
        }
    }

    private func focusedElement(in targetApp: NSRunningApplication) throws -> AXUIElement {
        let applicationElement = AXUIElementCreateApplication(targetApp.processIdentifier)
        var focusedValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusedResult == .success, let focusedValue else {
            throw TextInjectionError.focusedElementUnavailable(status: focusedResult)
        }
        return focusedValue as! AXUIElement
    }

    private func selectedTextRange(
        in focusedElement: AXUIElement,
        textLength: Int
    ) throws -> NSRange {
        var selectedValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedValue
        )
        guard result == .success,
              let selectedValue,
              CFGetTypeID(selectedValue) == AXValueGetTypeID() else {
            return NSRange(location: textLength, length: 0)
        }

        var range = CFRange(location: textLength, length: 0)
        guard AXValueGetValue(
            selectedValue as! AXValue,
            .cfRange,
            &range
        ), range.location >= 0, range.length >= 0,
              range.location <= textLength,
              range.length <= textLength - range.location else {
            throw TextInjectionError.focusedSelectionUnavailable(status: result)
        }
        return NSRange(location: range.location, length: range.length)
    }

    enum TextInjectionError: Error {
        case emptyText
        case targetApplicationUnavailable
        case accessibilityPermissionDenied
        case focusedElementUnavailable(status: AXError)
        case focusedValueUnavailable(status: AXError)
        case accessibilityValueUpdateFailed
        case focusedSelectionUnavailable(status: AXError)
        case injectionFailed(underlying: Error)

        var category: String {
            switch self {
            case .emptyText: "empty_text"
            case .targetApplicationUnavailable: "target_application_unavailable"
            case .accessibilityPermissionDenied: "accessibility_permission_denied"
            case .focusedElementUnavailable: "focused_element_unavailable"
            case .focusedValueUnavailable: "focused_value_unavailable"
            case .accessibilityValueUpdateFailed: "accessibility_value_update_failed"
            case .focusedSelectionUnavailable: "focused_selection_unavailable"
            case .injectionFailed: "injection_failed"
            }
        }
    }
}

private struct CGEventKeyboardEventPoster: KeyboardEventPosting {
    private let chunkSize = 20

    func post(text: String, to processIdentifier: pid_t) throws {
        try post(text: text, to: processIdentifier, preferFrontmostSession: false)
    }

    func post(text: String, to processIdentifier: pid_t, preferFrontmostSession: Bool) throws {
        guard let eventSource = CGEventSource(stateID: .combinedSessionState) else {
            throw TextInjector.TextInjectionError.eventSourceUnavailable
        }

        let characters = Array(text)
        for startIndex in stride(from: 0, to: characters.count, by: chunkSize) {
            let endIndex = min(startIndex + chunkSize, characters.count)
            let chunk = String(characters[startIndex..<endIndex])
            let utf16 = Array(chunk.utf16)

            guard let keyDown = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: 0,
                keyDown: true
            ), let keyUp = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: 0,
                keyDown: false
            ) else {
                throw TextInjector.TextInjectionError.eventCreationFailed
            }

            utf16.withUnsafeBufferPointer { buffer in
                keyDown.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: buffer.baseAddress
                )
            }
            if preferFrontmostSession {
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            } else {
                keyDown.postToPid(processIdentifier)
                keyUp.postToPid(processIdentifier)
            }
        }
    }
}

private extension TextInjector.TextInjectionError {
    static var eventSourceUnavailable: Self {
        .injectionFailed(underlying: EventPosterError.eventSourceUnavailable)
    }

    static var eventCreationFailed: Self {
        .injectionFailed(underlying: EventPosterError.eventCreationFailed)
    }
}

private enum EventPosterError: Error {
    case eventSourceUnavailable
    case eventCreationFailed
}
