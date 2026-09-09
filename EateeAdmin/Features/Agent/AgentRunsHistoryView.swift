import SwiftUI
import UIKit

struct AgentRunsHistoryView: View {
    @EnvironmentObject private var repository: APIAgentsRepository
    @State private var runs: [AgentRun] = []
    @State private var selectedRun: AgentRun?
    @State private var page = 0
    @State private var hasMore = true
    @State private var isLoading = false
    var body: some View { ScrollView { LazyVStack(spacing: 12) { if runs.isEmpty && isLoading { ForEach(0..<5, id: \.self) { _ in AgentRunCardSkeleton() } }; ForEach(runs) { run in Button { selectedRun = run } label: { AgentRunCard(run: run) }.buttonStyle(.plain).onAppear { if run.id == runs.last?.id { Task { await loadNextPage() } } } }; if isLoading && !runs.isEmpty { ProgressView().padding(.vertical, 10) } }.padding(20) }.refreshable { await reload() }.background(AppColor.background.ignoresSafeArea()).navigationTitle("История запусков").navigationBarTitleDisplayMode(.inline).task { await reload() }.sheet(item: $selectedRun) { AgentRunDetailsSheet(run: $0) } }
    private func reload() async { page = 0; hasMore = true; runs = []; await loadNextPage() }
    private func loadNextPage() async { guard hasMore, !isLoading else { return }; isLoading = true; defer { isLoading = false }; guard let result = try? await repository.runs(agent: nil, page: page, limit: 10) else { return }; runs.append(contentsOf: result.items); hasMore = result.hasMore; page += 1 }
}

private struct AgentRunCard: View {
    let run: AgentRun
    private var accent: Color { switch run.status { case .running: AppColor.base; case .completed: Color(hex: "#8AAD12"); case .failed: EAColor.danger } }
    private var icon: String { switch run.status { case .running: "arrow.triangle.2.circlepath"; case .completed: "checkmark"; case .failed: "exclamationmark" } }
    var body: some View { HStack(spacing: 14) { AgentIcon(agent: run.agent, size: 46, cornerRadius: 15); Text(run.agent.title).font(Typography.Font.semibold(17)).lineLimit(1).layoutPriority(1); Spacer(minLength: 8); Label(statusTitle, systemImage: icon).font(Typography.Font.semibold(12)).lineLimit(1).fixedSize(horizontal: true, vertical: false).foregroundStyle(run.status == .running ? EAColor.ink : accent).padding(.horizontal, 8).padding(.vertical, 8).background(accent.opacity(run.status == .running ? 0.48 : 0.13)).clipShape(Capsule()) }.padding(16).background(.white).clipShape(RoundedRectangle(cornerRadius: 22)).shadow(color: .black.opacity(0.04), radius: 6, y: 3).contentShape(RoundedRectangle(cornerRadius: 22)) }
    private var statusTitle: String { if run.status == .completed { return duration ?? "Готово" }; return run.status.title }
    private var duration: String? { guard run.status == .completed, let finishedAt = run.finishedAt else { return nil }; let seconds = max(0, Int(finishedAt.timeIntervalSince(run.startedAt))); if seconds < 60 { return "\(seconds) сек" }; let minutes = seconds / 60; if minutes < 60 { return "\(minutes) мин" }; let hours = minutes / 60; let remainingMinutes = minutes % 60; return remainingMinutes == 0 ? "\(hours) ч" : "\(hours) ч \(remainingMinutes) мин" }
}

private struct AgentRunDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let run: AgentRun
    @State private var showsFullError = false
    @State private var detent: PresentationDetent = .medium
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 20) { HStack { VStack(alignment: .leading, spacing: 4) { Text(run.agent.title).font(Typography.Font.bold(24)); Text(run.status.title).font(Typography.Font.medium(14)).foregroundStyle(EAColor.muted) }; Spacer(); HeaderCloseButton { dismiss() } }; details; if let error = run.errorMessage { errorCard(error) } }.padding(24) }.presentationDetents([.medium, .large], selection: $detent) }
    private var details: some View {
        VStack(spacing: 0) {
            row("Запущен", russianDate(run.startedAt))
            row("Завершён", run.finishedAt.map(russianDate) ?? "Выполняется")
            row("Инициатор", run.initiatedBy)

            switch run.agent {
            case .audit:
                row("Проверено блюд", run.checkedDishesCount.map(String.init) ?? "—")
                row("Создано элементов проверки", run.reviewItemsCreatedCount.map(String.init) ?? "—")
            case .generation:
                row("Создано черновиков", run.createdDraftsCount.map(String.init) ?? "—")
            case .imageGeneration:
                EmptyView()
            }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
    private func row(_ title: String, _ value: String) -> some View { HStack { Text(title).font(Typography.Font.regular(14)).foregroundStyle(EAColor.muted); Spacer(); Text(value).font(Typography.Font.semibold(14)).multilineTextAlignment(.trailing) }.padding(16).overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.05)).frame(height: 1) } }
    private func russianDate(_ date: Date) -> String { let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ru_RU"); formatter.dateFormat = "d MMMM yyyy, HH:mm"; return formatter.string(from: date) }
    private func errorCard(_ error: String) -> some View { VStack(alignment: .leading, spacing: 10) { HStack { Text("Ошибка").font(Typography.Font.semibold(15)).foregroundStyle(EAColor.danger); Spacer(); if showsFullError { Button { UIPasteboard.general.string = error } label: { Label("Скопировать", systemImage: "doc.on.doc").font(Typography.Font.semibold(13)).foregroundStyle(EAColor.ink) }.buttonStyle(.plain) } }; Text(error).font(Typography.Font.regular(15)).foregroundStyle(EAColor.ink).lineLimit(showsFullError ? nil : 3).fixedSize(horizontal: false, vertical: true).textSelection(.enabled); Button(showsFullError ? "Свернуть" : "Показать полный текст") { withAnimation { showsFullError.toggle(); detent = showsFullError ? .large : .medium } }.font(Typography.Font.semibold(14)).foregroundStyle(EAColor.danger) }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(EAColor.danger.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 16)) }
}
