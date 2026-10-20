import Foundation
import Observation

/// Führt `apply` sofort aus und danach bei jeder Änderung der darin gelesenen
/// `@Observable`-Eigenschaften erneut – für Objekte außerhalb von SwiftUI-Ansichten
/// (z. B. Einstellungen → Kurzbefehl neu anmelden).
@MainActor
func observeContinuously(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking {
        apply()
    } onChange: {
        // `onChange` kommt vor der Änderung; erst nach dem Setzen neu auswerten.
        DispatchQueue.main.async {
            MainActor.assumeIsolated { observeContinuously(apply) }
        }
    }
}
