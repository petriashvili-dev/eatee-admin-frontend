import Foundation
import SwiftUI

/// Экран повторяет структуру RegistrationView основного приложения: логотип, switcher, input и Continue.
struct SignInView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var email = ""
    @State private var loading = false
    @State private var errorText: String?
    @FocusState private var focused: Bool
    /// Использует ту же регулярную проверку, что и основной iOS-проект.
    private var isValid: Bool { email.isEmail }
    var body: some View { GeometryReader { proxy in
        ScrollView(showsIndicators: false) { VStack(spacing: 0) {
            VStack(spacing: 0) { Image("logo").renderingMode(.template).resizable().scaledToFit().foregroundStyle(AppColor.textBase).frame(width: 183, height: 66).padding(.top, proxy.size.height < 780 ? 44 : 80); Text("Управляйте контентом, пользователями и качеством сервиса.").font(Typography.Font.medium(16)).foregroundStyle(AppColor.textBase.opacity(0.6)).multilineTextAlignment(.center).padding(.top, 16) }.frame(maxWidth: .infinity)
            VStack(spacing: 16) { EmailInputField(text: $email, isFocused: $focused); RegistrationContinueButton(isEnabled: isValid, isLoading: loading, action: signIn) }.padding(.top, 48)
            if let errorText { Text(errorText).font(Typography.Font.regular(14)).foregroundStyle(EAColor.danger).padding(.top, 16) }
            Spacer(minLength: 24)
        }.frame(minHeight: proxy.size.height, alignment: .top).padding(.horizontal, 16) }
    }.background(AppColor.background.ignoresSafeArea()) }
    private func signIn() {
        loading = true
        errorText = nil

        Task {
            do {
                try await session.signIn(login: email)
            } catch {
                errorText = error.userMessage
            }
            loading = false
        }
    }
}

private extension Error {
    var userMessage: String {
        if let authenticationError = self as? AdminAuthenticationError {
            switch authenticationError {
            case .unauthorized:
                return "Нет доступа к админке."
            case .invalidResponse:
                return "Не удалось выполнить вход. Попробуйте ещё раз."
            case .server(status: let status, message: let message):
                return "Возникла ошибка сервера. Попробуйте ещё раз."
            }
        }

        switch self {
        case let urlError as URLError where urlError.code == .notConnectedToInternet:
            return "Нет подключения к интернету."
        case is URLError:
            return "Не удалось подключиться к серверу. Попробуйте ещё раз."
        default:
            return "Не удалось выполнить вход. Попробуйте ещё раз."
        }
    }
}

private extension String {
    var isEmail: Bool {
        let pattern = "^(?:[a-z0-9!#$%&'*+\\/=?^_`{|}~-]+(?:\\.[a-z0-9!#$%&'*+\\/=?^_`{|}~-]+)*|\"(?:"
            + "[\\x01-\\x08\\x0b\\x0c\\x0e-\\x1f\\x21\\x23-\\x5b\\x5d-\\x7f]|\\[\\x01-\\x09\\x0b\\x0c\\x0e-\\x7f])*\")"
            + "@(?:(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?|\\[(?:(?:(2(5[0-5]|[0-4][0-9])"
            + "|1[0-9][0-9]|[1-9]?[0-9]))\\.){3}(?:(2(5[0-5]|[0-4][0-9])|1[0-9][0-9]|[1-9]?[0-9])|[a-z0-9-]*[a-z0-9]:(?:"
            + "[\\x01-\\x08\\x0b\\x0c\\x0e-\\x1f\\x21-\\x5a\\x53-\\x7f]|\\[\\x01-\\x09\\x0b\\x0c\\x0e-\\x7f])+)\\])$"

        return range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

private struct EmailInputField: View { @Binding var text: String; @FocusState.Binding var isFocused: Bool; var body: some View { HStack(spacing: 13) { Image(systemName: "envelope").font(.system(size: 22, weight: .medium)).foregroundStyle(AppColor.textBase.opacity(0.55)); TextField("", text: $text, prompt: Text("Введите e-mail").font(Typography.Font.semibold(16)).foregroundStyle(AppColor.textBase.opacity(0.5))).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().font(Typography.Font.semibold(16)).focused($isFocused); if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark").foregroundStyle(AppColor.textBase.opacity(0.6)) } } }.frame(height: 58).padding(.horizontal, 22).background(.white).clipShape(RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(isFocused ? AppColor.textBase.opacity(0.5) : AppColor.spbSky_3, lineWidth: 1.1)) } }
private struct RegistrationContinueButton: View { let isEnabled: Bool; let isLoading: Bool; let action: () -> Void; var body: some View { Button(action: action) { ZStack { Text("Продолжить").font(Typography.Font.semibold(15)).foregroundStyle(isEnabled ? AppColor.titleButton : EAColor.muted).opacity(isLoading ? 0 : 1); if isLoading { ProgressView() } }.frame(maxWidth: .infinity).frame(height: 52).background(isEnabled ? AppColor.base : AppColor.spbSky_3).clipShape(RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain).disabled(!isEnabled || isLoading) } }
