import XCTest
@testable import SpoftyApp

final class CreditsMapperTests: XCTestCase {
    func testMapRelationsAssignsRoleGroups() {
        let relations = [
            MBRelationship(type: "instrument", targetType: "artist", attributes: ["guitar"], artist: MBArtist(id: "a1", name: "Player"), work: nil),
            MBRelationship(type: "producer", targetType: "artist", attributes: [], artist: MBArtist(id: "a2", name: "Producer"), work: nil),
            MBRelationship(type: "composer", targetType: "artist", attributes: [], artist: MBArtist(id: "a3", name: "Writer"), work: nil),
            MBRelationship(type: "mix", targetType: "artist", attributes: [], artist: MBArtist(id: "a4", name: "Mixer"), work: nil)
        ]

        let mapped = CreditsMapper.mapRelations(relations, sourceLevel: .recording)

        XCTAssertEqual(mapped.count, 4)
        XCTAssertEqual(mapped.first(where: { $0.personName == "Player" })?.roleGroup, .musicians)
        XCTAssertEqual(mapped.first(where: { $0.personName == "Producer" })?.roleGroup, .production)
        XCTAssertEqual(mapped.first(where: { $0.personName == "Writer" })?.roleGroup, .writing)
        XCTAssertEqual(mapped.first(where: { $0.personName == "Mixer" })?.roleGroup, .engineering)
    }

    func testMergeWithPrecedenceKeepsRecordingEntryOverRelease() {
        let recordingEntry = CreditEntry(
            personName: "Jane Doe",
            personMBID: "person-1",
            roleRaw: "producer",
            roleGroup: .production,
            sourceLevel: .recording,
            instrument: nil
        )

        let releaseEntry = CreditEntry(
            personName: "Jane Doe",
            personMBID: "person-1",
            roleRaw: "producer",
            roleGroup: .production,
            sourceLevel: .release,
            instrument: nil
        )

        let merged = CreditsMapper.mergeWithPrecedence([releaseEntry, recordingEntry])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.sourceLevel, .recording)
    }

    func testExtractWorkIDsReturnsUniqueValues() {
        let recording = MBRecordingDetail(
            id: "rec",
            title: "Track",
            relations: [
                MBRelationship(type: "performance", targetType: "work", attributes: [], artist: nil, work: MBWorkReference(id: "w1", title: "Work 1")),
                MBRelationship(type: "performance", targetType: "work", attributes: [], artist: nil, work: MBWorkReference(id: "w1", title: "Work 1")),
                MBRelationship(type: "performance", targetType: "work", attributes: [], artist: nil, work: MBWorkReference(id: "w2", title: "Work 2"))
            ],
            releases: []
        )

        let ids = Set(CreditsMapper.extractWorkIDs(from: recording))

        XCTAssertEqual(ids, Set(["w1", "w2"]))
    }
}
