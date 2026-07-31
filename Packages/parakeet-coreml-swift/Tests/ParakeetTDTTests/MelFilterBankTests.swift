import XCTest
@testable import ParakeetTDT

/// Smoke tests for the Slaney mel filter bank construction.
final class MelFilterBankTests: XCTestCase {
    func testShape() {
        let (rows, bins) = MelFilterBank.build(
            sampleRate: 16_000,
            nFFT: 512,
            numMelFilters: 128
        )
        XCTAssertEqual(rows.count, 128)
        XCTAssertEqual(bins, 257)
        XCTAssertEqual(rows[0].count, 257)
    }

    func testFiltersArePositive() {
        let (rows, _) = MelFilterBank.build(
            sampleRate: 16_000,
            nFFT: 512,
            numMelFilters: 128
        )
        // Every filter should have at least one non-zero bin and no negatives.
        for (i, row) in rows.enumerated() {
            XCTAssertGreaterThan(
                row.reduce(0, +), 0.0,
                "filter \(i) has zero energy"
            )
            for v in row {
                XCTAssertGreaterThanOrEqual(v, 0.0)
            }
        }
    }

    func testHzMelRoundTrip() {
        for hz in [0.0, 100.0, 1000.0, 4000.0, 8000.0] {
            let back = MelFilterBank.melToHzSlaney(
                MelFilterBank.hzToMelSlaney(hz)
            )
            XCTAssertEqual(back, hz, accuracy: 1e-6)
        }
    }
}
