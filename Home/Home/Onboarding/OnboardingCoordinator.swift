import Foundation

// Drives the multi-step onboarding NavigationStack.
// Holds the scanner so all onboarding screens share one scan.
@Observable
class OnboardingCoordinator {
    var path: [OnboardingStep] = []
    let scanner = NetworkScanner()

    func push(_ step: OnboardingStep) {
        path.append(step)
    }
}

enum OnboardingStep: Hashable {
    case howManyPeople
    case scanning
    case assignDevices
}
