import SwiftUI
import Charts

struct TrainingProgressView: View {
    let store: PhoneStore
    @State private var weeks = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 150
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let summary = TrainingAnalytics(state: store.state, weekCount: weeks, now: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    LiftPageHeading(title: "Your progress", detail: "A clearer view of the work you’ve logged.")
                    Picker("Time range", selection: $weeks) {
                        Text("4 weeks").tag(4)
                        Text("12 weeks").tag(12)
                    }.pickerStyle(.segmented)
                    Text("\(summary.start.formatted(date: .abbreviated, time: .omitted)) – today · includes this week")
                        .font(.caption).foregroundStyle(.secondary)
                    if summary.sessions.isEmpty {
                        LiftSurface {
                            VStack(alignment: .leading, spacing: 12) {
                                Image(systemName: "chart.bar.xaxis").font(.title2.weight(.light)).accessibilityHidden(true)
                                Text(store.state.sessions.isEmpty ? "Your first workout starts the picture." : "No logged workouts in this range.").font(LiftType.heading)
                                Text("Log a set on Watch and finish the workout. Once it reaches your phone, it appears here.")
                                    .font(.callout).foregroundStyle(.secondary)
                            }.padding(20)
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16, alignment: .topLeading)], alignment: .leading, spacing: 22) {
                            LiftStat(value: String(summary.sessions.count), label: "Workouts with logged sets")
                            LiftStat(value: String(summary.setCount), label: "Sets logged")
                            LiftStat(value: String(summary.trainingDays), label: "Training days")
                            LiftStat(value: summary.medianMinutes.map { "\($0) min" } ?? "—", label: "Typical session elapsed")
                        }
                        activity(summary)
                        LiftSection(title: "Exercise records") {
                            LiftSurface {
                                if summary.exercises.isEmpty {
                                    Text("Add a variation ID and load convention when editing a routine to start matched records. Earlier logs stay unchanged.")
                                        .font(.callout).foregroundStyle(.secondary).padding(20)
                                }
                                ForEach(summary.exercises) { exercise in
                                    NavigationLink { ExerciseProgressView(exercise: exercise) } label: {
                                        LiftMenuRow(title: exercise.name, symbol: "chart.xyaxis.line",
                                                    detail: "\(exercise.results.count) recorded workouts · \(exercise.key.unit.rawValue) · \(exercise.key.convention.label)")
                                    }
                                    if exercise.id != summary.exercises.last?.id { Divider().padding(.horizontal, 18) }
                                }
                            }
                        }
                    }
                    LiftSurface {
                        DisclosureGroup("What these numbers include") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Only finished Little Lift sessions with at least one logged set are counted. Early finishes count the work actually logged. Weeks start on Monday in your current time zone.")
                                Text("Typical session is the median time from Start to Finish, including breaks. It is not active exercise or measured rest. Zero-length and over-six-hour sessions are excluded from this estimate (\(summary.excludedDurations) in this range).")
                                Text("\(summary.unmatchedSets) sets lack exact variation and load-convention metadata. They count toward activity but are not compared by name. Different units and machines stay separate.")
                                Text("\(summary.importedCount) imported records in this range remain in History, separate from these app-recorded results. \(summary.repCount) repetitions were logged in the included sessions.")
                                Text("Calculated on this iPhone. No analytics service, fitness score or medical assessment.")
                            }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                        }.padding(18)
                    }
                }.padding(24)
            }.background(.black).buttonStyle(.plain).modifier(LiftRootChrome())
                .animation(reduceMotion ? nil : LiftMotion.content, value: weeks)
        }
    }
    private func activity(_ summary: TrainingAnalytics) -> some View {
        LiftSection(title: "Weekly rhythm") {
            LiftSurface {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Sets logged").font(LiftType.heading)
                    Chart(summary.weeks) { week in
                        BarMark(x: .value("Week starting", week.start, unit: .weekOfYear), y: .value("Sets", week.sets))
                            .foregroundStyle(.white.opacity(0.85)).cornerRadius(3)
                            .accessibilityLabel(Text("Week of \(week.start.formatted(date: .abbreviated, time: .omitted))"))
                            .accessibilityValue(Text("\(week.sets) sets in \(week.workouts) workouts"))
                    }.chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
                        .chartXAxis { AxisMarks(values: summary.weeks.enumerated().filter {
                            typeSize.isAccessibilitySize ? ($0.offset == 0 || $0.offset == summary.weeks.count - 1) : (weeks == 4 || $0.offset.isMultiple(of: 3))
                        }.map { $0.element.start }) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                        .frame(height: chartHeight)
                    Text("This week is still in progress. Gaps mean no workouts were logged, not that no training took place.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }
        }
    }
}

private struct ExerciseProgressView: View {
    let exercise: TrainingAnalytics.Exercise
    @State private var selectedReps: Int?
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 170
    private var reps: Int { selectedReps ?? exercise.results.first?.entries.last?.reps ?? 1 }
    private var points: [(result: TrainingAnalytics.Result, set: CompletedSet)] {
        exercise.results.compactMap { result in
            result.bestSet(reps: reps, convention: exercise.key.convention).map { (result, $0) }
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                LiftPageHeading(title: exercise.name, detail: "\(exercise.key.unit.rawValue) · \(exercise.key.convention.label)")
                LiftSurface {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Compare sets of", selection: Binding(get: { reps }, set: { selectedReps = $0 })) {
                            ForEach(exercise.repetitionCounts, id: \.self) { Text("\($0) reps").tag($0) }
                        }.frame(minHeight: 44)
                        Text(exercise.key.convention == .assistance ? "Lowest assistance recorded at \(reps) reps per workout." : "Highest recorded load at \(reps) reps per workout.")
                            .font(.callout)
                        if points.count > 1 && exercise.key.convention != .bodyweight {
                            Chart(points.reversed(), id: \.result.id) { point in
                                PointMark(x: .value("Workout", point.result.session.startedAt), y: .value(exercise.key.unit.rawValue, point.set.weight))
                                    .foregroundStyle(.white).symbolSize(45)
                                    .accessibilityLabel(Text(point.result.session.startedAt.formatted(date: .abbreviated, time: .omitted)))
                                    .accessibilityValue(Text("\(WorkoutSession.number(point.set.weight)) \(exercise.key.unit.rawValue), \(point.set.reps) reps"))
                            }.chartXScale(range: .plotDimension(startPadding: 12, endPadding: 12))
                                .chartYAxis { AxisMarks(position: .leading) }.frame(height: chartHeight)
                        } else {
                            Text(exercise.key.convention == .bodyweight ? "Bodyweight records use zero external load. Review your logged repetitions below." : "One matching workout so far. A second will add a chart.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Same variation, unit, load convention and repetition count. This describes recorded sets; it does not estimate strength or explain why results changed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(20)
                }
                LiftSection(title: "The recorded sets") {
                    LiftSurface {
                        ForEach(points, id: \.result.id) { point in
                            NavigationLink { SessionDetailView(session: point.result.session) } label: {
                                LiftMenuRow(title: "\(WorkoutSession.number(point.set.weight)) \(exercise.key.unit.rawValue) × \(point.set.reps)", symbol: "arrow.up.right",
                                            detail: "\(point.result.session.startedAt.formatted(date: .abbreviated, time: .omitted)) · set \(point.set.setNumber) · open workout")
                            }
                            if point.result.id != points.last?.result.id { Divider().padding(.horizontal, 18) }
                        }
                    }
                }
                Text("Variation: \(exercise.key.comparisonID). Prescribed targets and all other sets remain in each original workout.")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }.padding(24)
        }.background(.black).buttonStyle(.plain).navigationTitle("Exercise record").navigationBarTitleDisplayMode(.inline)
    }
}
