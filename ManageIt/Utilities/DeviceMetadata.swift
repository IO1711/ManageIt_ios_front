import Foundation
import UIKit

struct DeviceMetadata {
    let installationId: UUID
    let suggestedName: String
    let platformName: String
    let platformVersion: String
    let modelName: String

    static func current(installationId: UUID) -> DeviceMetadata {
        DeviceMetadata(
            installationId: installationId,
            suggestedName: UIDevice.current.model,
            platformName: UIDevice.current.systemName,
            platformVersion: UIDevice.current.systemVersion,
            modelName: DeviceMetadata.machineIdentifier()
        )
    }

    private static func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)

        let bytes = withUnsafeBytes(of: &systemInfo.machine) { rawBuffer in
            Array(rawBuffer.prefix { $0 != 0 })
        }

        return String(decoding: bytes, as: UTF8.self)
    }
}
