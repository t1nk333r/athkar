import AthkarCore
import Testing

@Test func periodRawValuesMatchPWA() {
    #expect(Period.allCases.map(\.rawValue) == ["morning", "evening"])
}
