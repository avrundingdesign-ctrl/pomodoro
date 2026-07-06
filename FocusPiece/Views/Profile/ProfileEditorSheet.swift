import SwiftUI
import PhotosUI

/// Profil einrichten (nach Konto-Erstellung) bzw. bearbeiten:
/// Foto, Name, Nutzername, Stadt, Bio.
struct ProfileEditorSheet: View {
    enum Mode { case setup, edit }

    @EnvironmentObject var online: OnlineModel
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    private let original: UserProfile

    @State private var displayName: String
    @State private var handle: String
    @State private var bio: String
    @State private var city: City
    @State private var photoData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var errorText: String?
    @State private var busy = false

    init(profile: UserProfile, mode: Mode) {
        self.mode = mode
        self.original = profile
        _displayName = State(initialValue: profile.displayName)
        _handle = State(initialValue: profile.handle)
        _bio = State(initialValue: profile.bio)
        _city = State(initialValue: profile.city)
        _photoData = State(initialValue: profile.photoData)
    }

    private var handleOK: Bool {
        handle == original.handle || online.isHandleAvailable(handle)
    }
    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && LocalBackend.isValidHandle(handle.lowercased()) && handleOK
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    photoPicker
                        .padding(.top, 10)

                    VStack(alignment: .leading, spacing: 14) {
                        labeled("Name") {
                            TextField("Dein Name", text: $displayName)
                                .textInputAutocapitalization(.words)
                        }
                        labeled("Nutzername") {
                            HStack(spacing: 4) {
                                Text("@").foregroundStyle(Theme.Palette.muted3)
                                TextField("nutzername", text: $handle)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .onChange(of: handle) { _, new in
                                        handle = new.lowercased()
                                    }
                            }
                        }
                        if !handleOK {
                            note("Dieser Nutzername ist bereits vergeben.")
                        } else if !handle.isEmpty && !LocalBackend.isValidHandle(handle) {
                            note("3–20 Zeichen, nur Kleinbuchstaben, Zahlen und Punkte.")
                        }
                        labeled("Stadt") {
                            Menu {
                                ForEach(City.catalog) { c in
                                    Button("\(c.name), \(c.country)") { city = c }
                                }
                            } label: {
                                HStack {
                                    Text("\(city.name), \(city.country)")
                                        .foregroundStyle(Theme.Palette.ink)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.Palette.muted3)
                                }
                            }
                        }
                        labeled("Über dich") {
                            TextField("Woran arbeitest du?", text: $bio, axis: .vertical)
                                .lineLimit(2...4)
                        }
                    }

                    if let errorText {
                        note(errorText)
                    }

                    PrimaryButton(title: busy ? "Speichern …" : "Profil speichern") { save() }
                        .opacity(canSave && !busy ? 1 : 0.5)
                        .disabled(!canSave || busy)
                }
                .padding(.horizontal, Theme.Pad.screenH)
                .padding(.bottom, 30)
            }
            .background(Theme.Palette.paper)
            .navigationTitle(mode == .setup ? "Profil einrichten" : "Profil bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if mode == .edit {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { dismiss() }
                    }
                }
            }
        }
    }

    private var photoPicker: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            VStack(spacing: 10) {
                AvatarView(profile: previewProfile, size: 96)
                Text(photoData == nil ? "Foto hinzufügen" : "Foto ändern")
                    .font(Theme.Font.sans(13, weight: .medium))
                    .foregroundStyle(Theme.Palette.accent)
            }
        }
        .buttonStyle(.plain)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let raw = try? await item.loadTransferable(type: Data.self) {
                    photoData = AvatarImage.downscaled(raw)
                }
            }
        }
    }

    private var previewProfile: UserProfile {
        var p = original
        p.displayName = displayName.isEmpty ? original.displayName : displayName
        p.photoData = photoData
        return p
    }

    private func labeled<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(Theme.Font.sans(11, weight: .semibold))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Palette.muted3)
            content()
                .font(Theme.Font.sans(15))
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Theme.Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.Palette.hairline2, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.sans(12))
            .foregroundStyle(Theme.Palette.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        var updated = original
        updated.displayName = displayName.trimmingCharacters(in: .whitespaces)
        updated.handle = handle
        updated.bio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.city = city
        updated.photoData = photoData
        busy = true
        errorText = nil
        Task {
            defer { busy = false }
            do {
                try await online.saveProfile(updated)
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
