import Foundation
import Testing
@testable import WorkoutCore

struct GymRecoveryTests {
    @Test func screenshotNotationAndWrappedNamesKeepExplicitTargets() throws {
        let source = """
        ChatGPT
        Pierna
        1. Prensa de
        piernas
        3 series x 10–12 repeticiones
        Peso: 40 kg
        Descanso: 90 segundos
        2. Curl femoral
        2 sets × 12
        Carga: 15 kg
        Descanso: 60 s
        """
        let draft = try SmartWorkoutImport.extract(source)
        #expect(draft.hasRecognizedPrescription)
        #expect(draft.title == "Pierna")
        #expect(draft.exercises.map(\.name) == ["Prensa de piernas", "Curl femoral"])
        #expect(draft.exercises.map(\.sets) == ["3", "2"])
        #expect(draft.exercises[0].reps.isEmpty)
        #expect(draft.exercises[0].repetitionChoices == [10, 12])
        #expect(draft.exercises.map(\.weight) == ["40", "15"])
        #expect(draft.exercises.map(\.rest) == ["90", "60"])
        #expect(draft.source == source)
        let inline = try SmartWorkoutImport.extract("Pierna\nPrensa 3 series × 10 20 kg descanso 60 s")
        #expect(try inline.validated().totalSets == 3)
        #expect(inline.exercises[0].name == "Prensa")
    }
    @Test func partialNumberedExerciseIsNeverSilentlyDropped() throws {
        for text in [
            "Pierna\n1. Prensa 3 x 10 40 kg descanso 90 s\n2. Curl femoral\n3. Gemelos 2 x 12 20 kg descanso 60 s",
            "1. Prensa\n2. Curl femoral 3 x 10 15 kg descanso 90 s\n3. Gemelos 2 x 12 20 kg descanso 60 s"
        ] {
            let draft = try SmartWorkoutImport.extract(text)
            #expect(draft.exercises.map(\.name) == ["Prensa", "Curl femoral", "Gemelos"])
            #expect(draft.hasRecognizedPrescription)
            #expect(throws: WorkoutError.self) { try draft.validated() }
        }
    }
    @Test func chatHeadingAndProseDoNotBecomeAReadyWorkout() throws {
        for text in ["Hoy toca pierna.", "ChatGPT\nPregunta lo que quieras", "Pierna\n1. Prensa\n2. Curl", ""] {
            let draft = try SmartWorkoutImport.extract(text)
            #expect(!draft.hasRecognizedPrescription)
            #expect(throws: WorkoutError.self) { try draft.validated() }
        }
    }
    @Test func existingJSONAndTimedTextStillOpenPreview() throws {
        #expect(try SmartWorkoutImport.extract(PlanImport.example).hasRecognizedPrescription)
        #expect(try SmartWorkoutImport.extract("Caminar 10 minutos").hasRecognizedPrescription)
    }
}
