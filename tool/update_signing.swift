// Prepare and sign macOS update archives using CryptoKit (macOS 12 or newer).
// Usage from the repository root:
//   swift tool/update_signing.swift init
//   SPARKLE_PRIVATE_KEY="$(cat .secrets/SPARKLE_PRIVATE_KEY.txt)" swift tool/update_signing.swift verify-key
//   SPARKLE_PRIVATE_KEY="$(cat .secrets/SPARKLE_PRIVATE_KEY.txt)" swift tool/update_signing.swift sign build/release/twist-cast-VERSION-macos-universal.dmg
// Keep the ignored private key backed up; commit the public Updates.xcconfig file.
// Signing prints only the public signature; private key material is never printed.
import Foundation
import CryptoKit

func run() throws {
  let args = CommandLine.arguments
  let config = URL(fileURLWithPath: "macos/Runner/Configs/Updates.xcconfig")
  if args.count == 2 && args[1] == "init" {
    let secret = URL(fileURLWithPath: ".secrets/SPARKLE_PRIVATE_KEY.txt")
    guard !FileManager.default.fileExists(atPath: secret.path),
          !FileManager.default.fileExists(atPath: config.path) else {
      throw NSError(domain: "UpdateSigning", code: 1, userInfo: [NSLocalizedDescriptionKey: "Signing key already exists; do not rotate an installed updater's key."])
    }
    let key = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(at: secret.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    guard FileManager.default.createFile(atPath: secret.path,
      contents: Data((key.rawRepresentation.base64EncodedString() + "\n").utf8), attributes: [.posixPermissions: 0o600]) else {
      throw NSError(domain: "UpdateSigning", code: 2)
    }
    let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
    try ("// Public verification key for signed macOS updates.\nSPARKLE_PUBLIC_KEY = \(publicKey)\n")
      .write(to: config, atomically: true, encoding: .utf8)
    print("Created .secrets/SPARKLE_PRIVATE_KEY.txt and macos/Runner/Configs/Updates.xcconfig")
  } else if (args.count == 3 && args[1] == "sign") || (args.count == 2 && args[1] == "verify-key") {
    guard let encoded = ProcessInfo.processInfo.environment["SPARKLE_PRIVATE_KEY"],
          let raw = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)), raw.count == 32 else {
      throw NSError(domain: "UpdateSigning", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing or invalid SPARKLE_PRIVATE_KEY."])
    }
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    let expected = try String(contentsOf: config, encoding: .utf8)
      .components(separatedBy: "SPARKLE_PUBLIC_KEY = ").last?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard expected == key.publicKey.rawRepresentation.base64EncodedString() else {
      throw NSError(domain: "UpdateSigning", code: 4, userInfo: [NSLocalizedDescriptionKey: "Signing key does not match the application's public key."])
    }
    if args[1] == "verify-key" { print("macOS update signing key verified."); return }
    let data = try Data(contentsOf: URL(fileURLWithPath: args[2]), options: .mappedIfSafe)
    let signature = try key.signature(for: data)
    guard key.publicKey.isValidSignature(signature, for: data) else { throw NSError(domain: "UpdateSigning", code: 5) }
    print(signature.base64EncodedString())
  } else {
    throw NSError(domain: "UpdateSigning", code: 6, userInfo: [NSLocalizedDescriptionKey: "Use init, verify-key, or sign <dmg>."])
  }
}

do { try run() }
catch {
  FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
  exit(1)
}
