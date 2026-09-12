import Foundation

enum CommunityGroupManagementRules {
    static func canTransferOwnership(actorRole: String?, targetRole: String, isSelfTarget: Bool) -> Bool {
        actorRole == "owner" && targetRole == "admin" && !isSelfTarget
    }
}
