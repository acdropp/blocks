import AppKit
import Combine
import GoogleSignIn

@MainActor
final class AuthManager: ObservableObject {
    static let scopes = [
        "https://www.googleapis.com/auth/tasks",
        "https://www.googleapis.com/auth/calendar.events",
    ]

    @Published private(set) var email: String?
    @Published private(set) var errorMessage: String?

    func restorePreviousSignIn() async {
        print("[Auth] Restoring previous sign-in")
        await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
                if let error {
                    print("[Auth] Restore failed (expected if never signed in): \(error.localizedDescription)")
                    continuation.resume()
                    return
                }
                print("[Auth] Restore succeeded: \(user?.profile?.email ?? "no email")")
                self?.email = user?.profile?.email
                continuation.resume()
            }
        }
    }

    func signIn() {
        print("[Auth] Starting sign-in")
        errorMessage = nil
        guard let window = NSApplication.shared.keyWindow else {
            print("[Auth] Sign-in failed: no key window to present from")
            errorMessage = "No window available to present sign-in."
            return
        }
        GIDSignIn.sharedInstance.signIn(
            withPresenting: window,
            hint: nil,
            additionalScopes: Self.scopes
        ) { [weak self] result, error in
            if let error {
                print("[Auth] Sign-in failed: \(error.localizedDescription)")
                self?.errorMessage = error.localizedDescription
                return
            }
            print("[Auth] Sign-in succeeded: \(result?.user.profile?.email ?? "no email")")
            self?.email = result?.user.profile?.email
        }
    }

    func signOut() {
        print("[Auth] Signing out")
        GIDSignIn.sharedInstance.signOut()
        email = nil
        errorMessage = nil
    }

    func validAccessToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            print("[Auth] No signed-in user; can't provide access token")
            throw AuthError.notSignedIn
        }
        return try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { refreshedUser, error in
                if let error {
                    print("[Auth] Token refresh failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }
                guard let token = refreshedUser?.accessToken.tokenString else {
                    continuation.resume(throwing: AuthError.notSignedIn)
                    return
                }
                continuation.resume(returning: token)
            }
        }
    }
}

enum AuthError: LocalizedError {
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in to Google."
        }
    }
}
