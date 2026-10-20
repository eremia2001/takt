import SwiftUI
import TaktCore
import WidgetKit

/// Stil „Schlicht“, Zustand „Pause“.
///
/// Klein: „Nichts läuft“ und „Heute h:mm“ oben, darunter bis zu drei Schnellstarts – mit
/// geplantem Block ersetzt dieser die dritte Zeile.
/// Mittel (und Karte im großen Widget): links „Nichts läuft“ und groß die Tagessumme, rechts die
/// Schnellstarts (im großen Widget steht der geplante Block in der Fußzeile).
/// Ein-Projekt-Widget: eine Zeile für das Projekt; läuft ein anderes, „Läuft: anderes Projekt“.
struct IdleView: View {
    let family: WidgetFamily
    let entry: TaktEntry

    private var showsPlanned: Bool { family != .systemLarge }

    var body: some View {
        let projects = quickStartProjects(entry, showsPlanned: showsPlanned)
        let block = showsPlanned ? entry.plannedBlock : nil
        if projects.isEmpty && block == nil {
            EmptyStateView(entry: entry)
        } else if family == .systemSmall {
            VStack(alignment: .leading, spacing: 0) {
                title
                TodayLabel(total: entry.todayTotal)
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                Spacer(minLength: 6)
                list(projects, block: block)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    title
                    if let budget = entry.budget {
                        BudgetLabel(budget: budget).padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                    // Beschriftung, damit die Tagessumme nicht als laufender Timer gelesen wird.
                    Text("Heute")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    BigDuration(interval: entry.todayTotal)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    list(projects, block: block)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var title: some View {
        Text(idleTitle(entry))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    private func list(_ projects: [Project], block: WidgetSnapshot.PlannedBlockInfo?) -> some View {
        VStack(spacing: 4) {
            QuickStartList(projects: projects)
            if let block {
                PlannedBlockRow(block: block, date: entry.date, look: .row)
            }
        }
    }
}

/// Keine Projekte (bzw. im Ein-Projekt-Widget: Projekt nicht mehr vorhanden).
struct EmptyStateView: View {
    let entry: TaktEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.isFixed ? "Projekt fehlt" : "Nichts läuft")
                .font(.subheadline)
            Text(entry.isFixed ? "Widget bearbeiten und ein Projekt wählen" : "Projekt in Takt anlegen")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
