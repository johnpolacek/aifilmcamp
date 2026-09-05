import Foundation

extension UUID {
    /// Decodes a TEXT UUID column, treating a malformed value as a corrupt bundle.
    static func required(_ string: String) throws -> UUID {
        guard let value = UUID(uuidString: string) else { throw ProjectStoreError.invalidBundle }
        return value
    }
}
