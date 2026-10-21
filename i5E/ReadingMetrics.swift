import ContentKit
import SwiftUI

private struct ReadingMetricsKey: EnvironmentKey {
    static let defaultValue = ReadingMetrics.standard
}

extension EnvironmentValues {
    var readingMetrics: ReadingMetrics {
        get { self[ReadingMetricsKey.self] }
        set { self[ReadingMetricsKey.self] = newValue }
    }
}
