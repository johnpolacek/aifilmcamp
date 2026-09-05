import Foundation

struct UserFacingError: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String

    static func project(_ error: any Error) -> UserFacingError {
        UserFacingError(
            title: "Project Error",
            message: (error as? LocalizedError)?.errorDescription ?? "The project could not be created or opened."
        )
    }
}

