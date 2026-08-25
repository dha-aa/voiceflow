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

final class TextInjector: TextInjecting, FocusedTextSelectionReading, TextInputAvailabilityChecking {
    private let keyboardEventPoster: KeyboardEventPosting
    private let permissionChecker: () -> Bool
    private let permissionRequester: () -> Void

    var isAccessibilityPermissionGranted: Bool {
        permissionChecker()
    }

    init(
        keyboardEventPoster: KeyboardEventPosting = CGEventKeyboardEventPoster(),
        permissionChecker: @escaping () -> Bool = { AXIsProcessTrusted() },
        permissionRequester: @escaping () -> Void = {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    ) {
        self.keyboardEventPoster = keyboardEventPoster
        self.permissionChecker = permissionChecker
        self.permissionRequester = permissionRequester
    }

    func requestAccessibilityPermission() {
        permissionRequester()
    }

    func hasTextInput(in targetApp: NSRunningApplication) -> Bool {
        guard targetApp.processIdentifier != 0,
              isAccessibilityPermissionGranted,
              let focusedElement = try? focusedElement(in: targetApp) else {
            return false
        }

        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXRoleAttribute as CFString,
            &roleValue
        )
        if roleResult == .success,
           let role = roleValue as? String,
           [
               kAXTextFieldRole as String,
               kAXTextAreaRole as String,
               "AXSearchField",
               kAXComboBoxRole as String
           ].contains(role) {
            return true
        }

        var value: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &value
        )
        guard valueResult == .success else {
            return false
        }
        guard (value as? String) != nil else {
            return false
        }

        var selectedRange: CFTypeRef?
        return AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        ) == .success
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

        if accessibilityTrusted {
            do {
                try injectUsingAccessibilityAPI(text: text, into: targetApp)
                VoiceFlowLog.pipeline.info("text_injection_method_succeeded method=accessibility_api")
                return
            } catch {
                VoiceFlowLog.pipeline.error("text_injection_method_failed method=accessibility_api error=\(String(describing: error), privacy: .public)")
            }
        }

        do {
            try keyboardEventPoster.post(text: text, to: processIdentifier)
            VoiceFlowLog.pipeline.info("text_injection_method_succeeded method=keyboard_events")
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
            location: selectedRange.location + (text as NSString).length,
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
            keyDown.postToPid(processIdentifier)
            keyUp.postToPid(processIdentifier)
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
