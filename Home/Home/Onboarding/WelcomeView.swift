import SwiftUI

struct WelcomeView: View {
    @State private var coordinator = OnboardingCoordinator()

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "house.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                VStack(spacing: 12) {
                    Text("Welcome to Home")
                        .font(.largeTitle.bold())
                    Text("Know who's home by scanning your WiFi for household devices.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }

                VStack(alignment: .leading, spacing: 14) {
                    FeatureRow(icon: "person.2.fill",  text: "Set up your household members")
                    FeatureRow(icon: "wifi",           text: "Scan your local network")
                    FeatureRow(icon: "bell.fill",      text: "See who's home at a glance")
                }
                .padding(.horizontal, 40)

                Spacer()

                VStack(spacing: 8) {
                    Button {
                        coordinator.push(.howManyPeople)
                    } label: {
                        Text("Get Started")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Text("Requires local network access.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
            .navigationDestination(for: OnboardingStep.self) { step in
                switch step {
                case .howManyPeople: HowManyPeopleView()
                case .scanning:     ScanningView()
                case .assignDevices: DeviceAssignmentView()
                }
            }
        }
        .environment(coordinator)
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.blue).frame(width: 24)
            Text(text)
        }
    }
}
