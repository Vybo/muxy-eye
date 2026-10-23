import Foundation
import Testing
@testable import MuxyEyeCore

@Test func jsonValueRoundTripsAndSubscripts() throws {
    let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"a":{"b":[1,"x",true,null]}}"#.utf8))
    #expect(value["a"]?["b"]?.arrayValue?.count == 4)
    #expect(value["a"]?["b"]?.arrayValue?[1].stringValue == "x")
    #expect(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) == value)
}
