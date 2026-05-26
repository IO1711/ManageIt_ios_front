import Foundation

struct LocationResponse: Codable, Equatable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let archived: Bool
}

struct LocationCreateRequest: Encodable, Equatable {
    let name: String
}

struct LocationUpdateRequest: Encodable, Equatable {
    let name: String
}

struct AuthorResponse: Codable, Equatable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let archived: Bool
}

struct AuthorCreateRequest: Encodable, Equatable {
    let name: String
}

struct OrganizationResponse: Codable, Equatable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let archived: Bool
}

struct OrganizationCreateRequest: Encodable, Equatable {
    let name: String
}
