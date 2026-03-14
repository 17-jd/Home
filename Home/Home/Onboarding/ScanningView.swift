import SwiftUI

struct ScanningView: View {
    @Environment(OnboardingCoordinator.self) private var coordinator
    @AppStorage("subnetBase") private var subnetBase = ""

    var body: some View {
        let scanner = coordinator.scanner

        VStack(spacing: 0) {
            // Status header
            VStack(spacing: 10) {
                if scanner.isScanning {
                    ProgressView().scaleEffect(1.4).padding(.bottom, 4)
                    Text("Scanning \(subnetBase).1–254…")
                        .font(.headline)
                    Text("Takes about 5–10 seconds")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else if scanner.results.isEmpty {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 48)).foregroundStyle(.orange)
                    Text("No devices found")
                        .font(.headline)
                    Text("Make sure you're on WiFi, then try again.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48)).foregroundStyle(.green)
                    Text("Found \(scanner.results.count) devices")
                        .font(.headline)
                    Text("Now assign them to household members.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .padding(.horizontal)

            if scanner.isScanning {
                ProgressView(value: scanner.progress)
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            }

            // Live device list as they're found
            List(scanner.results) { result in
                HStack {
                    Image(systemName: "display.and.arrow.down")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.hostname ?? result.ip)
                            .font(.headline)
                        if result.hostname != nil {
                            Text(result.ip)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            .animation(.easeInOut, value: scanner.results.count)

            // Bottom buttons
            if !scanner.isScanning {
                VStack(spacing: 8) {
                    if !scanner.results.isEmpty {
                        Button {
                            coordinator.push(.assignDevices)
                        } label: {
                            Text("Assign Devices →")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    Button {
                        Task { await startScan() }
                    } label: {
                        Text(scanner.results.isEmpty ? "Try Again" : "Rescan")
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .padding(.top, 8)
            }
        }
        .navigationTitle("Finding Devices")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(scanner.isScanning)
        .task { await startScan() }
    }

    private func startScan() async {
        if subnetBase.isEmpty {
            subnetBase = NetworkScanner.detectSubnet()
        }
        await coordinator.scanner.scan(subnet: subnetBase)
    }
}
