import Foundation
import Testing
@testable import MuxyEyeCore

@Test func decodesActivityFixture() throws {
    let snapshot = try JSONDecoder().decode(ActivitySnapshot.self, from: Fixture.data("muxy/activity.json"))
    #expect(snapshot.revision == 645)
    #expect(snapshot.agents.count == 4)
    #expect(snapshot.agents[1].session == MuxySessionID("5602690846448319352"))
    #expect(snapshot.agents[1].state == .blocked)
    #expect(snapshot.agents[2].isClaude == false)
    #expect(snapshot.agents[3].state == .unknown)
    #expect(snapshot.events[0].kind == .completed)
    #expect(snapshot.events[0].read == false)
    #expect(snapshot.events[1].kind == .attention)
}

@Test func decodesSessionsProjectsBuildInfo() throws {
    let sessions = try JSONDecoder().decode([MuxySessionInfo].self, from: Fixture.data("muxy/session-list.json"))
    #expect(sessions[0].projectID == "7a51b05fcefd4051aef266dd91d24e48")
    #expect(sessions[0].directory == "/Users/user.sample/muxy-eye")
    let projects = try JSONDecoder().decode([MuxyProject].self, from: Fixture.data("muxy/project-list.json"))
    #expect(projects[1].kind == "worktree")
    #expect(projects[1].parentID == "87e09a7c0058453ca36e3cecaf09f332")
    let build = try JSONDecoder().decode(MuxyBuildInfo.self, from: Fixture.data("muxy/build-info.json"))
    #expect(build.isSupported)
}

@Test func decodesTopLevelProjectWithNullKind() throws {
    // Muxy 2.1.0 reports `"kind": null` for top-level projects; one such entry must not sink the list.
    let json = """
    [
      {"id": "p1", "name": "muxy-eye", "directory": "/Users/me/muxy-eye", "home": false, "parent_id": null, "kind": null, "color": "#f76b15", "icon": null},
      {"id": "w1", "name": "spike/m7", "directory": "/Users/me/muxy-eye-wt", "home": false, "parent_id": "p1", "kind": "worktree", "color": null, "icon": null}
    ]
    """
    let projects = try JSONDecoder().decode([MuxyProject].self, from: Data(json.utf8))
    #expect(projects.map(\.name) == ["muxy-eye", "spike/m7"])
    #expect(projects[0].kind == nil)
    #expect(projects[1].kind == "worktree")
}
