import SwiftUI

/// Sign-in.
///
/// No server field — the app is internal only, so `ServerConfig` already knows the
/// host and domain. Asking users for a server address is nothing but a support-call
/// generator.
///
/// The "Explore with sample data" button is not a nicety. App Review can't reach your
/// Exchange server, and an app that shows a login wall reviewers can't pass gets
/// rejected under Guideline 2.1. This button is your demo mode.
public struct SignInView: View {

    @State private var username = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var failure: String?
    @FocusState private var focus: Field?
    /// Server and domain live here as well as in Settings, because Settings is
    /// behind this screen — a first-time user with the wrong server would
    /// otherwise have no way to reach the field that fixes it.
    @State private var showsServerFields = ServerConfig.isCustomized
    @State private var host = ServerConfig.serverHost
    @State private var domain = ServerConfig.domain
    @Environment(Session.self) private var session: Session?

    private enum Field { case username, password, server, domain }

    /// Called with `nil` for demo mode, or credentials for a real connection.
    let onSignIn: (_ credentials: (username: String, password: String)?) -> Void

    public init(onSignIn: @escaping (_ credentials: (username: String, password: String)?) -> Void) {
        self.onSignIn = onSignIn
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    AppMark(size: 42)
                    Text("Task Perfect")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                }
                Text("Your Outlook tasks, on your phone")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.slate)
            }
            .padding(.bottom, 36)

            VStack(spacing: 0) {
                field("Username / e-mail", text: $username, field: .username)
                Divider().padding(.leading, 16)
                secureField("Password")
                if showsServerFields {
                    Divider().padding(.leading, 16)
                    field("Server", text: $host, field: .server)
                    Divider().padding(.leading, 16)
                    field("Domain", text: $domain, field: .domain)
                }
            }
            .background(Theme.Palette.paper)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.corner))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metrics.corner)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
            )
            .padding(.horizontal, 24)

            // The server line is a button, not a label. Someone whose mailbox
            // has moved needs to change it before they can sign in — and
            // Settings, where it also lives, is behind this screen.
            Button {
                withAnimation(.snappy(duration: 0.2)) { showsServerFields.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(showsServerFields
                         ? "Hide server settings"
                         : "Signing in to \(ServerConfig.domain) · Change server")
                    Image(systemName: showsServerFields ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.caption)
                .foregroundStyle(Theme.Palette.slate)
            }
            .padding(.top, 10)

            if showsServerFields, ServerConfig.isCustomized {
                Button("Reset to \(ServerConfig.defaultServerHost)") {
                    ServerConfig.resetToDefaults()
                    host = ServerConfig.serverHost
                    domain = ServerConfig.domain
                }
                .font(.caption)
                .foregroundStyle(Theme.Palette.ink)
                .padding(.top, 6)
            }

            if let failure = failure ?? session?.unlockError {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.overdue)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 10)
            }

            Button {
                submit()
            } label: {
                Group {
                    if isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Text("Sign in").fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Palette.ink)
            .disabled(username.isEmpty || password.isEmpty || isWorking)
            .padding(.horizontal, 24)
            .padding(.top, 20)

            Spacer()

            Button("Explore with sample data") {
                onSignIn(nil)
            }
            .font(.subheadline)
            .foregroundStyle(Theme.Palette.slate)
            .padding(.bottom, 28)
        }
        .background(Theme.Palette.canvas)
    }

    private func field(_ label: String, text: Binding<String>, field: Field) -> some View {
        TextField(label, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focus, equals: field)
            .submitLabel(.next)
            .onSubmit { focus = .password }
            .padding(16)
    }

    private func secureField(_ label: String) -> some View {
        SecureField(label, text: $password)
            .focused($focus, equals: .password)
            .submitLabel(.go)
            .onSubmit(submit)
            .padding(16)
    }

    private func submit() {
        guard !username.isEmpty, !password.isEmpty else { return }
        // Persist the connection details before attempting to use them, so a
        // failed sign-in doesn't discard the correction the user just typed.
        let cleanedHost = ServerConfig.normalizedHost(host)
        if !cleanedHost.isEmpty { ServerConfig.serverHost = cleanedHost }
        let cleanedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedDomain.isEmpty { ServerConfig.domain = cleanedDomain }
        host = ServerConfig.serverHost
        domain = ServerConfig.domain

        focus = nil
        failure = nil
        isWorking = true
        onSignIn((username: username, password: password))
    }
}

#Preview {
    SignInView { _ in }
}
