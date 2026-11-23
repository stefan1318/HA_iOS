import Foundation

@main
enum Dev4ManifestTest {
    static func main() throws {
        func client(_ home: String, _ id: String, grants: [String], layout: String = "compact",
                    controls: [String]? = nil) throws -> StevoraManifest {
            var device: [String: Any] = ["entity_id": id, "name": home, "layout": layout,
                                         "available_controls": ["brightness", "toggle"]]
            if let controls { device["controls"] = controls }
            let payload: [String: Any] = [
                "schema_version": "1.0", "installation_id": home, "revision": UInt32.max,
                "rooms": [["id": home, "name": home]], "mappings": [home: [id]], "entities": [device],
                "controllable_entities": grants
            ]
            return try JSONDecoder().decode(StevoraManifest.self, from: JSONSerialization.data(withJSONObject: payload))
        }

        let id = "light.fixture"
        let home = try client("alpha", id, grants: [id])
        precondition(home.permits("toggle", entityID: id))
        precondition(!home.permits("color", entityID: id))
        let readOnly = try client("alpha", id, grants: [])
        let info = try client("alpha", id, grants: [id], layout: "info")
        let empty = try client("alpha", id, grants: [id], controls: [])
        let custom = try client("alpha", id, grants: [id], controls: ["brightness", "color"])
        let other = try client("beta", "light.different", grants: ["light.different"])
        for fixture in [readOnly, info, empty, custom, other] {
            precondition(!fixture.permits("toggle", entityID: id))
        }
        precondition(custom.permits("brightness", entityID: id) && !custom.permits("color", entityID: id))
        print("PASS: Dev4 manifest permissions, layouts, overrides, unsigned revision and separate homes")
    }
}
