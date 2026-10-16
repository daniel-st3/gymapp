import SwiftUI
import CoreMotion
import HealthKit
import CoreML

/// Isolated compilation/signing probe. Deliberately never requests health/motion
/// authorization, starts a workout, captures samples, or invokes a model.
@main
struct MotionCapabilityProbe: App {
    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Motion capability probe")
                    Text("Capture is off. No samples or workouts are created.").foregroundStyle(.secondary)
                    Text("Motion hardware: \(CMMotionManager().isDeviceMotionAvailable ? "available" : "unavailable")")
                    Text("Batched motion: \(CMBatchedSensorManager.isDeviceMotionSupported ? "supported" : "unsupported")")
                    Text("HealthKit: \(HKHealthStore.isHealthDataAvailable() ? "available" : "unavailable")")
                }.padding()
            }.background(.black).preferredColorScheme(.dark).tint(.white)
        }
    }
}

// Type-check the intended session and local inference APIs without executing them.
func sessionForFutureOptInProbe(store: HKHealthStore) throws -> HKWorkoutSession {
    let configuration = HKWorkoutConfiguration()
    configuration.activityType = .traditionalStrengthTraining
    configuration.locationType = .indoor
    return try HKWorkoutSession(healthStore: store, configuration: configuration)
}
func localModelConfiguration() -> MLModelConfiguration {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .cpuOnly
    return configuration
}
