import SwiftUI
import UIKit

/// Card-intro анимация, перенесённая из SplashToRegistrationView основного приложения.
struct AdminSplashView: View {
    let onFinished: () -> Void
    @State private var visible = Array(repeating: false, count: 6)
    @State private var exiting = false
    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                AppColor.background.ignoresSafeArea()

                ForEach(0..<6, id: \.self) { index in
                    let card = SplashCard.deck[index]
                    FoodCardView(card: card, side: card.width * proxy.size.width)
                        .position(
                            x: center.x + card.offset.width * proxy.size.width,
                            y: center.y + card.offset.height * proxy.size.height
                        )
                        .rotationEffect(.degrees(card.rotation))
                        .scaleEffect(visible[index] && !exiting ? 1 : 0.85)
                        .opacity(visible[index] && !exiting ? 1 : 0)
                        .animation(.easeOut(duration: 0.35), value: visible[index])
                        .animation(.easeInOut(duration: 0.6), value: exiting)
                }

                VStack(spacing: 0) {
                    Image("logo")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(AppColor.textBase)
                        .frame(width: 183, height: 66)

                    Text("[admin]")
                        .font(Typography.Font.medium(20))
                        .tracking(1.2)
                        .foregroundStyle(AppColor.textBase)
                        .padding(.top, 8)

                    Text("Всё под контролем")
                        .font(Typography.Font.medium(16))
                        .foregroundStyle(AppColor.textBase.opacity(0.6))
                        .padding(.top, 12)
                }
                .opacity(exiting ? 0 : 1)
                .animation(.easeInOut(duration: 0.45), value: exiting)
            }
        }
        .onAppear {
            for index in 0..<6 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.08) {
                    visible[index] = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.95) {
                withAnimation { exiting = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.62, execute: onFinished)
            }
        }
    }
}

private struct SplashCard { let image: String; let width: CGFloat; let rotation: Double; let offset: CGSize; static let deck = [SplashCard(image: "oatmealBerries", width: 0.30, rotation: -16.32, offset: .init(width: -0.245, height: -0.343)), SplashCard(image: "strawberryLemonade", width: 0.40, rotation: 1.95, offset: .init(width: -0.02, height: -0.293)), SplashCard(image: "carbonara", width: 0.36, rotation: 28.94, offset: .init(width: 0.124, height: -0.362)), SplashCard(image: "belgianWaffles", width: 0.40, rotation: -9, offset: .init(width: -0.47, height: 0.365)), SplashCard(image: "uzbekPlov", width: 0.30, rotation: 4, offset: .init(width: 0.06, height: 0.275)), SplashCard(image: "matchaLatte", width: 0.34, rotation: 9, offset: .init(width: 0.50, height: 0.365))] }
private struct FoodCardView: View { let card: SplashCard; let side: CGFloat; var body: some View { ZStack { RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(hex: "#EAE8F1")).frame(width: side * 0.94, height: side * 0.94).rotationEffect(.degrees(7)); Image(card.image).resizable().scaledToFill().frame(width: side, height: side).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)) } } }
