import SwiftUI
import AuthenticationServices

/// Zeigt `content` nur mit Konto; sonst die Anmeldung. Frisch angelegte
/// Konten bekommen die Profil-Einrichtung als Sheet.
struct OnlineGate<Content: View>: View {
    @EnvironmentObject var online: OnlineModel
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if online.isSignedIn {
                content
            } else {
                AuthView()
            }
        }
        .sheet(isPresented: $online.needsProfileSetup) {
            if let profile = online.profile {
                ProfileEditorSheet(profile: profile, mode: .setup)
            }
        }
    }
}

/// Konto erstellen / anmelden: Sign in with Apple (echt), Google, E-Mail.
struct AuthView: View {
    @EnvironmentObject var online: OnlineModel
    @Environment(\.colorScheme) private var colorScheme

    private enum Mode: String, CaseIterable { case register = "Registrieren", login = "Anmelden" }
    @State private var mode: Mode = .register
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("ONLINE-MODUS").eyebrow()
                    .padding(.bottom, 10)
                Text("Gemeinsam\nfokussieren.")
                    .font(Theme.Font.serif(34))
                    .tracking(-0.3)
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.bottom, 18)

                VStack(alignment: .leading, spacing: 10) {
                    benefit(icon: "dot.radiowaves.left.and.right", text: "Live sehen, wer gerade fokussiert")
                    benefit(icon: "map", text: "Fortschritte deiner Freunde auf der Karte")
                    benefit(icon: "bubble.left.and.bubble.right", text: "Anfeuern, Nachrichten & Kunstgrüße")
                    benefit(icon: "chart.bar", text: "Ausführliche Statistiken zu deinem Fokus")
                }
                .padding(.bottom, 26)

                // Apple — echter Systemdialog (Entitlement gesetzt).
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    handleApple(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.primaryButton, style: .continuous))
                .padding(.bottom, 12)

                googleButton
                    .padding(.bottom, 22)

                HStack(spacing: 12) {
                    Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
                    Text("oder mit E-Mail")
                        .font(Theme.Font.sans(12))
                        .foregroundStyle(Theme.Palette.muted3)
                        .fixedSize()
                    Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
                }
                .padding(.bottom, 18)

                modePicker
                    .padding(.bottom, 16)

                VStack(spacing: 12) {
                    if mode == .register {
                        field("Dein Name", text: $name, contentType: .name)
                    }
                    field("E-Mail", text: $email, contentType: .emailAddress, keyboard: .emailAddress)
                    secureField("Passwort", text: $password)
                }
                .padding(.bottom, 14)

                if let errorText {
                    Text(errorText)
                        .font(Theme.Font.sans(13))
                        .foregroundStyle(Theme.Palette.accent)
                        .padding(.bottom, 12)
                }

                PrimaryButton(title: busy ? "Einen Moment …"
                              : (mode == .register ? "Konto erstellen" : "Anmelden")) {
                    submitEmail()
                }
                .opacity(canSubmit && !busy ? 1 : 0.5)
                .disabled(!canSubmit || busy)

                Text("Der Online-Modus läuft aktuell auf einem lokalen Backend — Konten, Freunde und Coins bleiben auf diesem Gerät. Der Server-Anschluss ist vorbereitet (docs/ONLINE.md).")
                    .font(Theme.Font.sans(12))
                    .foregroundStyle(Theme.Palette.muted3)
                    .padding(.top, 16)
            }
            .padding(.horizontal, Theme.Pad.screenH)
            .padding(.top, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.Palette.paper)
    }

    // MARK: Bausteine

    private func benefit(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 24)
            Text(text)
                .font(Theme.Font.sans(14))
                .foregroundStyle(Theme.Palette.muted)
        }
    }

    private var googleButton: some View {
        Button {
            signInGoogle()
        } label: {
            HStack(spacing: 10) {
                Text("G")
                    .font(Theme.Font.sans(17, weight: .bold))
                    .foregroundStyle(Theme.Palette.accent)
                Text("Mit Google fortfahren")
                    .font(Theme.Font.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Theme.Palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.primaryButton, style: .continuous)
                    .stroke(Theme.Palette.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.primaryButton, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(Mode.allCases, id: \.self) { m in
                Button {
                    mode = m
                    errorText = nil
                } label: {
                    Text(m.rawValue)
                        .font(Theme.Font.sans(14, weight: .semibold))
                        .foregroundStyle(mode == m ? Theme.Palette.ink : Theme.Palette.muted3)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(mode == m ? Theme.Palette.surface : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.Palette.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func field(_ placeholder: String, text: Binding<String>,
                       contentType: UITextContentType? = nil,
                       keyboard: UIKeyboardType = .default) -> some View {
        TextField(placeholder, text: text)
            .textContentType(contentType)
            .keyboardType(keyboard)
            .textInputAutocapitalization(contentType == .name ? .words : .never)
            .autocorrectionDisabled()
            .font(Theme.Font.sans(15))
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(Theme.Palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.Palette.hairline2, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func secureField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .textContentType(.password)
            .font(Theme.Font.sans(15))
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(Theme.Palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.Palette.hairline2, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Aktionen

    private var canSubmit: Bool {
        let mailOK = email.contains("@") && email.contains(".")
        if mode == .register {
            return mailOK && password.count >= 6 && !name.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return mailOK && !password.isEmpty
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            run {
                try await online.signInExternal(provider: .apple,
                                                externalID: credential.user,
                                                displayName: name.isEmpty ? nil : name)
            }
        case .failure:
            errorText = "Sign in with Apple ist gerade nicht verfügbar. Nutze alternativ Google oder E-Mail."
        }
    }

    private func signInGoogle() {
        // Läuft lokal, bis das GoogleSignIn-SDK eingebunden ist (docs/ONLINE.md);
        // die stabile externe ID sorgt dafür, dass dasselbe Konto wiederkommt.
        run {
            try await online.signInExternal(provider: .google,
                                            externalID: "google.device.local",
                                            displayName: nil)
        }
    }

    private func submitEmail() {
        run {
            if mode == .register {
                try await online.createEmailAccount(email: email, password: password,
                                                    displayName: name.trimmingCharacters(in: .whitespaces))
            } else {
                try await online.signInEmail(email: email, password: password)
            }
        }
    }

    private func run(_ operation: @escaping () async throws -> Void) {
        errorText = nil
        busy = true
        Task {
            defer { busy = false }
            do { try await operation() }
            catch { errorText = error.localizedDescription }
        }
    }
}
