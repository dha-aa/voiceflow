import XCTest
@testable import voiceflow

@MainActor
final class OnboardingTests: XCTestCase {
    func test_onboardingStartsAtWelcomeWithoutCompletingSetup() {
        let defaults = UserDefaults(suiteName: "onboarding-welcome-\(UUID().uuidString)")!
        let permissionManager = FakePermissionManager()
        let model = OnboardingModel(
            permissionManager: permissionManager,
            userDefaults: defaults
        )

        XCTAssertEqual(model.step, .welcome)
        XCTAssertTrue(model.isFirstLaunch)
        XCTAssertFalse(defaults.bool(forKey: VoiceFlowOnboardingDefaults.completedKey))
        XCTAssertEqual(permissionManager.statusCallCount, VoiceFlowPermission.allCases.count)
    }

    func test_onboardingRequestsRequiredPermissionsInOrderThenShowsScreenContextInformation() async {
        let defaults = UserDefaults(suiteName: "onboarding-order-\(UUID().uuidString)")!
        let permissionManager = FakePermissionManager()
        let model = OnboardingModel(
            permissionManager: permissionManager,
            userDefaults: defaults
        )

        model.beginPermissions()
        XCTAssertEqual(model.step, .permission(.microphone))

        await model.grantCurrentPermission()
        XCTAssertEqual(model.step, .permission(.accessibility))

        await model.grantCurrentPermission()
        XCTAssertEqual(model.step, .permission(.screenRecording))
        XCTAssertEqual(permissionManager.requestedPermissions, [.microphone, .accessibility])

        model.skipCurrentPermission()
        XCTAssertEqual(model.step, .complete)
    }

    func test_deniedPermissionCanBeSkippedAndAppearsInCompletionSummary() async {
        let defaults = UserDefaults(suiteName: "onboarding-denied-\(UUID().uuidString)")!
        let permissionManager = FakePermissionManager(permissionsToGrant: [])
        let model = OnboardingModel(
            permissionManager: permissionManager,
            userDefaults: defaults
        )

        model.beginPermissions()
        await model.grantCurrentPermission()

        XCTAssertTrue(model.lastRequestFailed)
        XCTAssertEqual(model.currentPermission, .microphone)

        model.skipCurrentPermission()
        XCTAssertEqual(model.currentPermission, .accessibility)
        model.skipCurrentPermission()
        XCTAssertEqual(model.currentPermission, .screenRecording)
        model.skipCurrentPermission()

        XCTAssertEqual(model.step, .complete)
        XCTAssertEqual(model.requiredPermissionsMissing, [.microphone, .accessibility])
        XCTAssertFalse(defaults.bool(forKey: VoiceFlowOnboardingDefaults.completedKey))
    }

    func test_screenRecordingIsExplainedButNeverRequestedInCurrentVersion() async {
        let defaults = UserDefaults(suiteName: "onboarding-screen-\(UUID().uuidString)")!
        let permissionManager = FakePermissionManager(
            permissionsToGrant: [.microphone, .accessibility]
        )
        let model = OnboardingModel(
            permissionManager: permissionManager,
            userDefaults: defaults
        )

        model.beginPermissions()
        await model.grantCurrentPermission()
        await model.grantCurrentPermission()
        XCTAssertEqual(model.currentPermission, .screenRecording)

        await model.grantCurrentPermission()

        XCTAssertEqual(model.currentPermission, .screenRecording)
        XCTAssertEqual(permissionManager.requestedPermissions, [.microphone, .accessibility])
        XCTAssertFalse(VoiceFlowPermission.screenRecording.isRequiredForCurrentVersion)
    }

    func test_completedOnboardingRestoresCompleteStateAndDoesNotReappear() {
        let defaults = UserDefaults(suiteName: "onboarding-complete-\(UUID().uuidString)")!
        let permissionManager = FakePermissionManager()
        let model = OnboardingModel(
            permissionManager: permissionManager,
            userDefaults: defaults
        )

        model.finish()
        let relaunchedModel = OnboardingModel(
            permissionManager: permissionManager,
            userDefaults: defaults
        )

        XCTAssertFalse(relaunchedModel.isFirstLaunch)
        XCTAssertEqual(relaunchedModel.step, .complete)
        XCTAssertFalse(OnboardingWindowController.shouldShowOnLaunch(userDefaults: defaults))
    }

    func test_skipSetupPersistsCompletionAndCallsFinishCallback() {
        let defaults = UserDefaults(suiteName: "onboarding-skip-\(UUID().uuidString)")!
        let permissionManager = FakePermissionManager()
        var finished = false
        let model = OnboardingModel(
            permissionManager: permissionManager,
            userDefaults: defaults,
            onFinished: { finished = true }
        )

        model.skipSetup()

        XCTAssertTrue(finished)
        XCTAssertTrue(defaults.bool(forKey: VoiceFlowOnboardingDefaults.completedKey))
    }
}

@MainActor
private final class FakePermissionManager: VoiceFlowPermissionManaging {
    private var grantedPermissions: Set<VoiceFlowPermission>
    private let permissionsToGrant: Set<VoiceFlowPermission>
    private(set) var requestedPermissions: [VoiceFlowPermission] = []
    private(set) var statusCallCount = 0

    init(permissionsToGrant: Set<VoiceFlowPermission> = [.microphone, .accessibility]) {
        self.permissionsToGrant = permissionsToGrant
        self.grantedPermissions = []
    }

    func status(for permission: VoiceFlowPermission) -> VoiceFlowPermissionStatus {
        statusCallCount += 1
        if permission == .screenRecording {
            return .notRequired
        }
        return grantedPermissions.contains(permission) ? .granted : .notGranted
    }

    func request(_ permission: VoiceFlowPermission) async -> Bool {
        requestedPermissions.append(permission)
        if permissionsToGrant.contains(permission) {
            grantedPermissions.insert(permission)
            return true
        }
        return false
    }

    func openSystemSettings(for permission: VoiceFlowPermission) {}
}
