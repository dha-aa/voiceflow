import AppKit

struct InjectionContext {
    let targetApp: NSRunningApplication
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let isTerminalTarget: Bool
    let isFrontmostTarget: Bool
}

protocol TextInjectionStrategy {
    var name: String { get }
    func canHandle(context: InjectionContext) -> Bool
    func inject(text: String, context: InjectionContext) throws
}

enum StrategyError: Error {
    case noApplicableStrategy
}
