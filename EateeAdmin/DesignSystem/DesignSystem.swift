import SwiftUI

extension Color { init(hex: String) { let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0; self.init(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255) } }

enum EAColor {
    static let accent = Color(red: 194/255, green: 230/255, blue: 73/255)
    static let background = Color(red: 242/255, green: 244/255, blue: 247/255)
    static let ink = Color(red: 33/255, green: 33/255, blue: 33/255)
    static let muted = Color(red: 143/255, green: 150/255, blue: 164/255)
    static let danger = Color(red: 235/255, green: 77/255, blue: 61/255)
}

// Перенесённые токены основного eatee-frontend.
enum AppColor {
    static let base = EAColor.accent
    static let titleButton = EAColor.ink
    static let spbSky = EAColor.background
    static let spbSky_3 = EAColor.muted.opacity(0.55)
    static let textBase = EAColor.ink
    static let background = EAColor.background
    struct Basic { static let base = Color.white }
}

enum Typography { enum Font {
    static func regular(_ size: CGFloat) -> SwiftUI.Font { .custom("Montserrat-Regular", size: size) }
    static func medium(_ size: CGFloat) -> SwiftUI.Font { .custom("Montserrat-Medium", size: size) }
    static func semibold(_ size: CGFloat) -> SwiftUI.Font { .custom("Montserrat-SemiBold", size: size) }
    static func bold(_ size: CGFloat) -> SwiftUI.Font { .custom("Montserrat-Bold", size: size) }
} }

/// Точный по размерам вариант основной кнопки из eatee-frontend.
struct PrimaryButton: View {
    let action: () -> Void; let title: String; var isEnabled = true
    var body: some View { Button(action: action) { Text(title).font(Typography.Font.semibold(15)).foregroundStyle(isEnabled ? AppColor.titleButton : EAColor.muted).frame(maxWidth: .infinity).frame(height: 52).background(isEnabled ? AppColor.base : AppColor.spbSky_3).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)) }.buttonStyle(.plain).disabled(!isEnabled) }
}

struct EAPrimaryButton: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Text(title).font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 17) }
            .foregroundStyle(EAColor.ink).background(EAColor.accent).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct EASurface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(16).background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white)).overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.black.opacity(0.045), lineWidth: 1)) }
}

/// Визуальная часть действий в шапке. Повторяет системную кнопку «Назад»:
/// только иконка и стандартная область касания, без собственной подложки.
struct HeaderActionIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(AppColor.textBase)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

/// Переиспользуемая кнопка шапки для действий, отличных от системного возврата.
struct HeaderActionButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppColor.textBase)
            }
                .buttonStyle(.glass)
        } else {
            Button(action: action) { HeaderActionIcon(systemName: systemName) }
                .buttonStyle(.plain)
        }
    }
}

/// Плейсхолдер для списков: сохраняет геометрию карточек до получения данных.
struct EASkeleton: View {
    var cornerRadius: CGFloat = 8
    @State private var isAnimating = false
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(EAColor.muted.opacity(0.16))
            .overlay {
                LinearGradient(colors: [.clear, .white.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                    .offset(x: isAnimating ? 240 : -240)
            }
            .clipped()
            .onAppear { withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) { isAnimating = true } }
            .accessibilityHidden(true)
    }
}

struct DishCardSkeleton: View {
    var body: some View { EASurface { HStack(spacing: 14) { EASkeleton(cornerRadius: 14).frame(width: 88, height: 88); VStack(alignment: .leading, spacing: 10) { EASkeleton().frame(height: 18); EASkeleton().frame(width: 150, height: 13); HStack(spacing: 10) { EASkeleton().frame(width: 62, height: 13); EASkeleton().frame(width: 54, height: 13) } }; Spacer() }.frame(height: 88) } }
}

struct AgentRunCardSkeleton: View {
    var body: some View { HStack(spacing: 14) { EASkeleton(cornerRadius: 15).frame(width: 46, height: 46); EASkeleton().frame(width: 104, height: 18); Spacer(); EASkeleton(cornerRadius: 16).frame(width: 86, height: 30) }.padding(16).background(.white).clipShape(RoundedRectangle(cornerRadius: 22)) }
}

struct EAAvatar: View {
    let name: String
    var body: some View {
        Text(name.prefix(1).uppercased()).font(.system(size: 18, weight: .bold)).foregroundStyle(EAColor.ink)
            .frame(width: 46, height: 46).background(EAColor.accent).clipShape(Circle())
    }
}

struct HomeAvatarView: View {
    let name: String
    var gender: String? = nil
    private var imageName: String {
        let normalized = gender?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["мужской", "male", "man"].contains(normalized) ? "avatarMale" : "avatarFemale"
    }
    var body: some View { Image(imageName).resizable().scaledToFill().frame(width: 46, height: 46).background(.white).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)) }
}

/// Тот же компонент, что и NavigationIconButton в основном eatee-frontend.
struct NavigationIconButton: View {
    let systemName: String; let action: () -> Void
    var body: some View { HeaderActionButton(systemName: systemName, action: action) }
}

/// Кнопка закрытия шитов: подложка-квадрат, в отличие от прозрачных HeaderActionButton.
struct HeaderCloseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(Typography.Font.bold(16))
                .foregroundStyle(EAColor.muted)
                .frame(width: 40, height: 40)
                .background(AppColor.spbSky)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Закрыть")
    }
}

/// Единая цветная иконка агента для карточек каталога и истории запусков.
struct AgentIcon: View {
    let agent: AgentKind; var size: CGFloat = 76; var cornerRadius: CGFloat = 20
    private var accent: Color { switch agent { case .audit: Color(hex: "#8AAD12"); case .generation: Color(hex: "#766CB7"); case .imageGeneration: Color(hex: "#D8783B") } }
    var body: some View { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(accent.opacity(0.13)).frame(width: size, height: size).overlay(Image(systemName: agent.icon).font(.system(size: size * 0.41, weight: .semibold)).foregroundStyle(accent)) }
}

/// Шапка полностью повторяет HomeHeaderView основного приложения, кроме кнопки настроек.
struct AdminHomeHeaderView: View {
    let userName: String
    var gender: String? = nil
    private var firstName: String { userName.split(separator: " ").first.map(String.init) ?? userName }
    var body: some View { HStack(spacing: 12) { HomeAvatarView(name: firstName, gender: gender); VStack(alignment: .leading, spacing: 4) { Text("Добро пожаловать,").font(Typography.Font.regular(14)).foregroundStyle(EAColor.muted); Text(firstName).font(Typography.Font.semibold(24)).foregroundStyle(EAColor.ink).lineLimit(1).minimumScaleFactor(0.75) }; Spacer() } }
}

/// Короткое подтверждение успешного действия. Само скрывается через секунду.
struct EASuccessToast: View {
    let title: String
    var body: some View {
        Label(title, systemImage: "checkmark.circle.fill")
            .font(Typography.Font.semibold(15))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(hex: "#638000"), in: Capsule())
            .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
            .accessibilityAddTraits(.isStaticText)
    }
}

private struct EASuccessToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isPresented {
                    EASuccessToast(title: title)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isPresented)
            .task(id: isPresented) {
                guard isPresented else { return }
                try? await Task.sleep(for: .seconds(1))
                isPresented = false
            }
    }
}

extension View {
    func eaSuccessToast(isPresented: Binding<Bool>, title: String = "Обновлено") -> some View {
        modifier(EASuccessToastModifier(isPresented: isPresented, title: title))
    }

    /// Общий современный bottom sheet для выбора значений в формах.
    func eaSelectionBottomSheet() -> some View {
        presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(.white)
    }
}
