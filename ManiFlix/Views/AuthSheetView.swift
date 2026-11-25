import SwiftUI

struct AuthSheetView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var prefs = AppPreferences.shared
    @Environment(\.dismiss) private var dismiss

    @State private var isRegisterMode = false
    @State private var username = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isBusy = false
    @State private var errorText: String?

    var body: some View {
        NavigationView {
            Form {
                if appState.isLoggedIn, let user = appState.currentUser {
                    Section("Thông tin tài khoản") {
                        HStack {
                            Text("Tên hiển thị")
                            Spacer()
                            Text(user.displayName ?? user.username)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Tên đăng nhập")
                            Spacer()
                            Text("@\(user.username)")
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Lịch sử xem")
                            Spacer()
                            Text("\(appState.history.count) phim")
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Phim đã lưu")
                            Spacer()
                            Text("\(appState.favorites.count) phim")
                                .foregroundColor(.secondary)
                        }
                    }

                    Section {
                        Button {
                            Task {
                                isBusy = true
                                await appState.refreshLibrary()
                                isBusy = false
                                Haptics.notify(.success)
                            }
                        } label: {
                            HStack {
                                Text("Đồng bộ dữ liệu ngay")
                                Spacer()
                                if isBusy { ProgressView().scaleEffect(0.8) }
                            }
                        }

                        Button("Đăng xuất", role: .destructive) {
                            appState.logout()
                            dismiss()
                        }
                    }
                } else {
                    Section {
                        Picker("Chế độ", selection: $isRegisterMode) {
                            Text("Đăng nhập").tag(false)
                            Text("Đăng ký").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }

                    Section {
                        TextField("Tên đăng nhập", text: $username)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)

                        if isRegisterMode {
                            TextField("Tên hiển thị", text: $displayName)
                        }

                        SecureField("Mật khẩu", text: $password)
                    }

                    if let err = errorText {
                        Section {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    Section {
                        Button {
                            Task { await submit() }
                        } label: {
                            HStack {
                                Spacer()
                                if isBusy {
                                    ProgressView()
                                } else {
                                    Text(isRegisterMode ? "Tạo tài khoản" : "Đăng nhập")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(prefs.accentPreset.color)
                                }
                                Spacer()
                            }
                        }
                        .disabled(isBusy || username.isEmpty || password.isEmpty)
                    }
                }
            }
            .navigationTitle("Tài khoản")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func submit() async {
        isBusy = true
        errorText = nil
        do {
            let res: AuthResponse
            if isRegisterMode {
                res = try await ManiFlixAPI.shared.register(
                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    displayName: displayName.isEmpty ? username : displayName
                )
            } else {
                res = try await ManiFlixAPI.shared.login(
                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )
            }
            if let token = res.token, !token.isEmpty {
                await appState.handleAuthSuccess(token: token, user: res.user)
                dismiss()
            } else {
                errorText = res.error ?? "Không thể xác thực tài khoản."
            }
        } catch {
            errorText = error.localizedDescription
        }
        isBusy = false
    }
}
