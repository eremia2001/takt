import SwiftUI
import TaktCore
import WidgetKit

/// Stil „Schlicht“, Zustand „läuft“.
///
/// Klein: Projekt (und, wenn Platz ist, „Nächster Schritt“) oben, Dauer mit Stopp-Knopf,
/// darunter der Pausenstrich, ganz unten die Wechsel-Punkte und „Heute h:mm“.
/// Mittel (und Karte im großen Widget): links Projekt, nächster Schritt, Dauer, Stopp-Knopf und
/// Pausenstrich, rechts „Wechseln zu“; im mittleren Widget unten rechts geplanter Block, Budget
/// und Tagessumme (im großen stehen sie in dessen Fußzeile).
struct RunningView: View {
    let family: WidgetFamily
    let entry: TaktEntry
    let running: RunningState

    private var project: Project { running.project }
    private var showsFooter: Bool { family == .systemMedium }

    var body: some View {
        if family == .systemSmall {
            // „Nächster Schritt“ nur, wenn er in die Höhe passt.
            ViewThatFits(in: .vertical) {
                small(showsNextStep: true)
                small(showsNextStep: false)
            }
        } else {
            wide
        }
    }

    private func small(showsNextStep: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(twoLines: false)
            if showsNextStep, let step = entry.snapshot.runningNextStep {
                NextStepLine(text: step)
                    .padding(.leading, 14)
                    .padding(.top, 1)
            }
            Spacer(minLength: 4)
            HStack(alignment: .center, spacing: 4) {
                BigDuration(interval: entry.runningDuration)
                Spacer(minLength: 0)
                StopButton(color: project.color)
            }
            if let fraction = entry.breakFraction {
                BreakProgressBar(fraction: fraction, tint: project.color)
                    .padding(.top, 2)
            }
            HStack(spacing: 6) {
                SwitchDots(projects: entry.snapshot.switchTargets)
                Spacer(minLength: 0)
                TodayLabel(total: entry.todayTotal)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 20)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var wide: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                header(twoLines: true)
                if let step = entry.snapshot.runningNextStep {
                    NextStepLine(text: step)
                        .padding(.leading, 14)
                        .padding(.top, 2)
                        .layoutPriority(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 12) {
                        BigDuration(interval: entry.runningDuration)
                        StopButton(color: project.color)
                    }
                    if let fraction = entry.breakFraction {
                        BreakProgressBar(fraction: fraction, tint: project.color)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                if !entry.snapshot.switchTargets.isEmpty {
                    Text("Wechseln zu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    QuickStartList(projects: entry.snapshot.switchTargets, limit: WidgetSnapshot.maxSwitchTargets, isSwitch: true)
                }
                Spacer(minLength: 0)
                if showsFooter {
                    if let block = entry.plannedBlock {
                        PlannedLine(block: block, date: entry.date)
                    }
                    HStack(spacing: 6) {
                        if let budget = entry.budget { BudgetLabel(budget: budget) }
                        Spacer(minLength: 0)
                        TodayLabel(total: entry.todayTotal)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Farbpunkt + Projektname.
    private func header(twoLines: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            ProjectDot(color: project.color)
                .padding(.top, 5)
            ProjectName(name: project.name, twoLines: twoLines)
        }
    }
}
