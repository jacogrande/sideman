import Foundation

enum CreditsMapper {
    static func extractWorkIDs(from recording: MBRecordingDetail) -> [String] {
        var ids = Set<String>()
        for relation in recording.relations {
            if let workID = relation.work?.id {
                ids.insert(workID)
            }
        }
        return Array(ids)
    }

    static func mapRelations(_ relations: [MBRelationship], sourceLevel: CreditSourceLevel) -> [CreditEntry] {
        relations.compactMap { relation in
            guard let artist = relation.artist else {
                return nil
            }

            let roleGroup = roleGroup(for: relation.type, attributes: relation.attributes)
            let instrument = instrumentValue(for: relation, roleGroup: roleGroup)
            let roleRaw = rawRole(type: relation.type, attributes: relation.attributes)

            return CreditEntry(
                personName: artist.name,
                personMBID: artist.id,
                roleRaw: roleRaw,
                roleGroup: roleGroup,
                sourceLevel: sourceLevel,
                instrument: instrument
            )
        }
    }

    static func mergeWithPrecedence(_ entries: [CreditEntry]) -> [CreditEntry] {
        var winnersByKey: [String: CreditEntry] = [:]

        for entry in entries {
            let key = dedupeKey(for: entry)
            if let existing = winnersByKey[key] {
                if entry.sourceLevel.sortRank < existing.sourceLevel.sortRank {
                    winnersByKey[key] = entry
                }
            } else {
                winnersByKey[key] = entry
            }
        }

        return winnersByKey.values.sorted { lhs, rhs in
            if lhs.roleGroup != rhs.roleGroup {
                return lhs.roleGroup.title < rhs.roleGroup.title
            }

            if lhs.personName != rhs.personName {
                return lhs.personName.localizedCaseInsensitiveCompare(rhs.personName) == .orderedAscending
            }

            return lhs.roleRaw.localizedCaseInsensitiveCompare(rhs.roleRaw) == .orderedAscending
        }
    }

    static func mergeDeduplicating(_ entries: [CreditEntry]) -> [CreditEntry] {
        var seen = Set<String>()
        var deduped: [CreditEntry] = []

        for entry in entries {
            let key = dedupeKey(for: entry)
            if seen.contains(key) {
                continue
            }
            seen.insert(key)
            deduped.append(entry)
        }

        return deduped.sorted { lhs, rhs in
            if lhs.roleGroup != rhs.roleGroup {
                return lhs.roleGroup.title < rhs.roleGroup.title
            }
            if lhs.personName != rhs.personName {
                return lhs.personName.localizedCaseInsensitiveCompare(rhs.personName) == .orderedAscending
            }
            return lhs.roleRaw.localizedCaseInsensitiveCompare(rhs.roleRaw) == .orderedAscending
        }
    }

    static func group(_ entries: [CreditEntry]) -> [CreditRoleGroup: [CreditEntry]] {
        var grouped: [CreditRoleGroup: [CreditEntry]] = [:]
        for group in CreditRoleGroup.displayOrder {
            grouped[group] = []
        }

        for entry in entries {
            grouped[entry.roleGroup, default: []].append(entry)
        }

        for group in CreditRoleGroup.displayOrder {
            grouped[group]?.sort { lhs, rhs in
                if lhs.personName != rhs.personName {
                    return lhs.personName.localizedCaseInsensitiveCompare(rhs.personName) == .orderedAscending
                }
                return lhs.roleRaw.localizedCaseInsensitiveCompare(rhs.roleRaw) == .orderedAscending
            }
        }

        return grouped
    }

    static func roleGroup(forRoleText value: String) -> CreditRoleGroup {
        roleGroup(for: value, attributes: [])
    }

    private static func dedupeKey(for entry: CreditEntry) -> String {
        let person = (entry.personMBID ?? entry.personName).lowercased()
        let role = entry.roleRaw.lowercased()
        let instrument = (entry.instrument ?? "").lowercased()
        return "\(person)|\(entry.roleGroup.rawValue)|\(role)|\(instrument)|\(entry.scope)"
    }

    private static func rawRole(type: String, attributes: [String]) -> String {
        if attributes.isEmpty {
            return type
        }

        return "\(type) (\(attributes.joined(separator: ", ")))"
    }

    private static func instrumentValue(for relation: MBRelationship, roleGroup: CreditRoleGroup) -> String? {
        guard roleGroup == .musicians else {
            return nil
        }

        if relation.type.localizedCaseInsensitiveContains("instrument") {
            return relation.attributes.first
        }

        if relation.type.localizedCaseInsensitiveContains("perform") {
            return relation.attributes.first
        }

        if relation.type.localizedCaseInsensitiveContains("vocal") {
            return "vocals"
        }

        return nil
    }

    private static func roleGroup(for type: String, attributes: [String]) -> CreditRoleGroup {
        let full = ([type] + attributes).joined(separator: " ").lowercased()

        if containsAny(full, ["composer", "lyricist", "writer", "songwriter", "librettist", "author", "arranger", "orchestrator"]) {
            return .writing
        }

        if containsAny(full, ["producer", "co-producer", "executive producer", "production", "programming", "programmer", "beatmaker"]) {
            return .production
        }

        if containsAny(full, ["engineer", "mix", "mastering", "recording", "assistant engineer", "audio editing", "editing"]) {
            return .engineering
        }

        if containsAny(full, ["perform", "instrument", "vocal", "guitar", "drum", "drums", "bass", "piano", "sax", "violin", "synth", "keyboard", "keyboards", "percussion", "flute", "cello", "mandolin", "banjo", "marimba", "glockenspiel", "trumpet", "trombone", "clarinet", "conductor"]) {
            return .musicians
        }

        return .misc
    }

    private static func containsAny(_ source: String, _ values: [String]) -> Bool {
        values.contains { source.contains($0) }
    }
}
