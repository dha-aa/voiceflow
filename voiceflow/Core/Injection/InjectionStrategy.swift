import AppKit

struct InjectionContext {
    let targetApp: NSRunningApplication
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let isTerminalTarget: Bool
    let isFrontmostTarget: Bool
    let isStillFrontmost: () -> Bool

    init(
        targetApp: NSRunningApplication,
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        isTerminalTarget: Bool,
        isFrontmostTarget: Bool,
        isStillFrontmost: @escaping () -> Bool = { true }
    ) {
        self.targetApp = targetApp
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.isTerminalTarget = isTerminalTarget
        self.isFrontmostTarget = isFrontmostTarget
        self.isStillFrontmost = isStillFrontmost
    }
}

protocol TextInjectionStrategy {
    var name: String { get }
    func canHandle(context: InjectionContext) -> Bool
    func inject(text: String, context: InjectionContext) throws
}

enum StrategyError: Error {
    case noApplicableStrategy
}
