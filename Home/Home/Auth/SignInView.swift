import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @AppStorage("hasCompletedAuth") private var hasCompletedAuth = false
    @AppStorage("authUserID")       private var authUserID       = ""
    @AppStorage("authUserName")     private var authUserName     = ""
    @AppStorage("authUserEmail")    private var authUserEmail    = ""
    @AppStorage("authProvider")     private var authProvider     = ""

    @Environment(\.colorScheme) private var colorScheme
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "house.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.blue)

                Text("Home")
                    .font(.largeTitle.bold())

                Text("Track who's home on your WiFi.\nSign in to save your setup, or skip to continue as a guest.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 14) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    switch result {
                    case .success(let auth):
                        guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else {
                            errorMessage = "Unexpected credential type."
                            return
                        }
                        authUserID   = cred.user
                        authProvider = "apple"
                        if let name = cred.fullName {
                            let full = [name.givenName, name.familyName]
                                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                            if !full.isEmpty { authUserName = full }
                        }
                        if authUserName.isEmpty { authUserName = "Apple User" }
                        if let email = cred.email { authUserEmail = email }
                        hasCompletedAuth = true

                    case .failure(let error):
                        let code = (error as? ASAuthorizationError)?.code
                        // Code 1001 = user cancelled — don't show an error for that
                        if code != .canceled {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                Button("Skip") {
                    authUserID       = "guest"
                    authUserName     = "Guest"
                    authProvider     = "guest"
                    hasCompletedAuth = true
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 52)
        }
    }
}
