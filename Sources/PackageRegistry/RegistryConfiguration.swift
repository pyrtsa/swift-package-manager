//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import PackageModel

public struct RegistryConfiguration: Hashable {
    public enum Version: Int, Codable {
        case v1 = 1
    }

    public static let version: Version = .v1

    public var defaultRegistry: Registry?
    public var scopedRegistries: [PackageIdentity.Scope: Registry]
    public var registryAuthentication: [String: Authentication]
    public var security: Security?

    public init() {
        self.defaultRegistry = nil
        self.scopedRegistries = [:]
        self.registryAuthentication = [:]
        self.security = nil
    }

    public mutating func merge(_ other: RegistryConfiguration) {
        if let defaultRegistry = other.defaultRegistry {
            self.defaultRegistry = defaultRegistry
        }

        for (scope, registry) in other.scopedRegistries {
            self.scopedRegistries[scope] = registry
        }

        for (registry, authentication) in other.registryAuthentication {
            self.registryAuthentication[registry] = authentication
        }
    }

    public func registry(for package: PackageIdentity) -> Registry? {
        guard let registryIdentity = package.registry else {
            return .none
        }
        return self.registry(for: registryIdentity.scope)
    }

    public func registry(for scope: PackageIdentity.Scope) -> Registry? {
        self.scopedRegistries[scope] ?? self.defaultRegistry    
    }

    public var explicitlyConfigured: Bool {
        self.defaultRegistry != nil || !self.scopedRegistries.isEmpty
    }

    public func authentication(for registryURL: URL) -> Authentication? {
        guard let host = registryURL.host else { return nil }
        return self.registryAuthentication[host]
    }

    public func signing(for package: PackageIdentity, registry: Registry) throws -> Security.Signing {
        guard let registryIdentity = package.registry else {
            throw StringError("Only package identity in <scope>.<name> format is supported: '\(package)'")
        }

        let global = self.security?.default.signing
        let registryOverrides = registry.url.host.flatMap { host in self.security?.registryOverrides[host]?.signing }
        let scopeOverrides = self.security?.scopeOverrides[registryIdentity.scope]?.signing
        let packageOverrides = self.security?.packageOverrides[package]?.signing

        var signing = Security.Signing.default
        if let global = global {
            signing.merge(global)
        }
        if let registryOverrides = registryOverrides {
            signing.merge(registryOverrides)
        }
        if let scopeOverrides = scopeOverrides {
            signing.merge(scopeOverrides)
        }
        if let packageOverrides = packageOverrides {
            signing.merge(packageOverrides)
        }

        return signing
    }
}

extension RegistryConfiguration {
    public struct Authentication: Hashable, Codable {
        public var type: AuthenticationType
        public var loginAPIPath: String?

        public init(type: AuthenticationType, loginAPIPath: String? = nil) {
            self.type = type
            self.loginAPIPath = loginAPIPath
        }
    }

    public enum AuthenticationType: String, Hashable, Codable {
        case basic
        case token
    }
}

extension RegistryConfiguration {
    public struct Security: Hashable {
        public var `default`: Global
        public var registryOverrides: [String: RegistryOverride]
        public var scopeOverrides: [PackageIdentity.Scope: ScopePackageOverride]
        public var packageOverrides: [PackageIdentity: ScopePackageOverride]

        public init() {
            self.default = Global()
            self.registryOverrides = [:]
            self.scopeOverrides = [:]
            self.packageOverrides = [:]
        }

        public struct Global: Hashable, Codable {
            public var signing: Signing?

            public init() {
                self.signing = nil
            }
        }

        public struct RegistryOverride: Hashable, Codable {
            public var signing: Signing?

            public init() {
                self.signing = nil
            }
        }

        public struct Signing: Hashable, Codable {
            static let `default`: Signing = {
                var signing = Signing()
                signing.onUnsigned = .prompt
                signing.onUntrustedCertificate = .prompt
                signing.trustedRootCertificatesPath = nil
                signing.includeDefaultTrustedRootCertificates = true

                var validationChecks = Signing.ValidationChecks()
                validationChecks.certificateExpiration = .disabled
                validationChecks.certificateRevocation = .disabled
                signing.validationChecks = validationChecks

                return signing
            }()

            public var onUnsigned: OnUnsignedAction?
            public var onUntrustedCertificate: OnUntrustedCertificateAction?
            public var trustedRootCertificatesPath: String?
            public var includeDefaultTrustedRootCertificates: Bool?
            public var validationChecks: ValidationChecks?

            public init() {
                self.onUnsigned = nil
                self.onUntrustedCertificate = nil
                self.trustedRootCertificatesPath = nil
                self.includeDefaultTrustedRootCertificates = nil
                self.validationChecks = nil
            }

            mutating func merge(_ other: Signing) {
                if let onUnsigned = other.onUnsigned {
                    self.onUnsigned = onUnsigned
                }
                if let onUntrustedCertificate = other.onUntrustedCertificate {
                    self.onUntrustedCertificate = onUntrustedCertificate
                }
                if let trustedRootCertificatesPath = other.trustedRootCertificatesPath {
                    self.trustedRootCertificatesPath = trustedRootCertificatesPath
                }
                if let includeDefaultTrustedRootCertificates = other.includeDefaultTrustedRootCertificates {
                    self.includeDefaultTrustedRootCertificates = includeDefaultTrustedRootCertificates
                }
                if let validationChecks = other.validationChecks {
                    self.validationChecks?.merge(validationChecks)
                }
            }

            mutating func merge(_ other: ScopePackageOverride.Signing) {
                if let trustedRootCertificatesPath = other.trustedRootCertificatesPath {
                    self.trustedRootCertificatesPath = trustedRootCertificatesPath
                }
                if let includeDefaultTrustedRootCertificates = other.includeDefaultTrustedRootCertificates {
                    self.includeDefaultTrustedRootCertificates = includeDefaultTrustedRootCertificates
                }
            }

            public enum OnUnsignedAction: String, Hashable, Codable {
                case error
                case prompt
                case warn
                case silentAllow
            }

            public enum OnUntrustedCertificateAction: String, Hashable, Codable {
                case error
                case prompt
                case warn
                case silentTrust
            }

            public struct ValidationChecks: Hashable, Codable {
                public var certificateExpiration: CertificateExpirationCheck?
                public var certificateRevocation: CertificateRevocationCheck?

                public init() {
                    self.certificateExpiration = nil
                    self.certificateRevocation = nil
                }

                mutating func merge(_ other: ValidationChecks) {
                    if let certificateExpiration = other.certificateExpiration {
                        self.certificateExpiration = certificateExpiration
                    }
                    if let certificateRevocation = other.certificateRevocation {
                        self.certificateRevocation = certificateRevocation
                    }
                }

                public enum CertificateExpirationCheck: String, Hashable, Codable {
                    case enabled
                    case disabled
                }

                public enum CertificateRevocationCheck: String, Hashable, Codable {
                    case strict
                    case allowSoftFail
                    case disabled
                }
            }
        }

        public struct ScopePackageOverride: Hashable, Codable {
            public var signing: Signing?

            public init() {
                self.signing = nil
            }

            public struct Signing: Hashable, Codable {
                public var trustedRootCertificatesPath: String?
                public var includeDefaultTrustedRootCertificates: Bool?

                public init() {
                    self.trustedRootCertificatesPath = nil
                    self.includeDefaultTrustedRootCertificates = nil
                }

                mutating func merge(_ other: Signing) {
                    if let trustedRootCertificatesPath = other.trustedRootCertificatesPath {
                        self.trustedRootCertificatesPath = trustedRootCertificatesPath
                    }
                    if let includeDefaultTrustedRootCertificates = other.includeDefaultTrustedRootCertificates {
                        self.includeDefaultTrustedRootCertificates = includeDefaultTrustedRootCertificates
                    }
                }
            }
        }
    }
}

// MARK: - Codable

extension RegistryConfiguration: Codable {
    private enum CodingKeys: String, CodingKey {
        case registries
        case authentication
        case security
        case version
    }

    fileprivate struct ScopeCodingKey: CodingKey, Hashable {
        static let `default` = ScopeCodingKey(stringValue: "[default]")

        var stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }

    fileprivate struct PackageCodingKey: CodingKey, Hashable {
        var stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let version = try container.decode(Version.RawValue.self, forKey: .version)
        switch Version(rawValue: version) {
        case .v1:
            let nestedContainer = try container.nestedContainer(keyedBy: ScopeCodingKey.self, forKey: .registries)

            self.defaultRegistry = try nestedContainer.decodeIfPresent(Registry.self, forKey: .default)

            var scopedRegistries: [PackageIdentity.Scope: Registry] = [:]
            for key in nestedContainer.allKeys where key != .default {
                let scope = try PackageIdentity.Scope(validating: key.stringValue)
                scopedRegistries[scope] = try nestedContainer.decode(Registry.self, forKey: key)
            }
            self.scopedRegistries = scopedRegistries

            self.registryAuthentication = try container.decodeIfPresent(
                [String: Authentication].self,
                forKey: .authentication
            ) ?? [:]
            self.security = try container.decodeIfPresent(Security.self, forKey: .security) ?? nil
        case nil:
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "invalid version: \(version)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(Self.version, forKey: .version)

        var registriesContainer = container.nestedContainer(keyedBy: ScopeCodingKey.self, forKey: .registries)

        try registriesContainer.encodeIfPresent(self.defaultRegistry, forKey: .default)

        for (scope, registry) in self.scopedRegistries {
            let key = ScopeCodingKey(stringValue: scope.description)
            try registriesContainer.encode(registry, forKey: key)
        }

        try container.encode(self.registryAuthentication, forKey: .authentication)
        try container.encodeIfPresent(self.security, forKey: .security)
    }
}

extension PackageRegistry.Registry: Codable {
    private enum CodingKeys: String, CodingKey {
        case url
        case supportsAvailability
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try container.decode(URL.self, forKey: .url)
        self.supportsAvailability = try container.decodeIfPresent(Bool.self, forKey: .supportsAvailability) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.url, forKey: .url)
        try container.encode(self.supportsAvailability, forKey: .supportsAvailability)
    }
}

extension RegistryConfiguration.Security: Codable {
    private enum CodingKeys: String, CodingKey {
        case `default`
        case registryOverrides
        case scopeOverrides
        case packageOverrides
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.default = try container.decodeIfPresent(Global.self, forKey: .default) ?? Global()
        self.registryOverrides = try container.decodeIfPresent(
            [String: RegistryOverride].self,
            forKey: .registryOverrides
        ) ?? [:]

        let scopeOverridesContainer = try container.decodeIfPresent(
            [String: ScopePackageOverride].self,
            forKey: .scopeOverrides
        ) ?? [:]
        var scopeOverrides: [PackageIdentity.Scope: ScopePackageOverride] = [:]
        for (key, scopeOverride) in scopeOverridesContainer {
            let scope = try PackageIdentity.Scope(validating: key)
            scopeOverrides[scope] = scopeOverride
        }
        self.scopeOverrides = scopeOverrides

        let packageOverridesContainer = try container.decodeIfPresent(
            [String: ScopePackageOverride].self,
            forKey: .packageOverrides
        ) ?? [:]
        var packageOverrides: [PackageIdentity: ScopePackageOverride] = [:]
        for (key, packageOverride) in packageOverridesContainer {
            let packageIdentity = PackageIdentity.plain(key)
            guard packageIdentity.isRegistry else {
                throw DecodingError.dataCorruptedError(
                    forKey: .packageOverrides,
                    in: container,
                    debugDescription: "invalid package identifier: '\(key)'"
                )
            }
            packageOverrides[packageIdentity] = packageOverride
        }
        self.packageOverrides = packageOverrides
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.default, forKey: .default)
        try container.encode(self.registryOverrides, forKey: .registryOverrides)

        var scopeOverridesContainer = container.nestedContainer(
            keyedBy: RegistryConfiguration.ScopeCodingKey.self,
            forKey: .scopeOverrides
        )
        for (scope, scopeOverride) in self.scopeOverrides {
            let key = RegistryConfiguration.ScopeCodingKey(stringValue: scope.description)
            try scopeOverridesContainer.encode(scopeOverride, forKey: key)
        }

        var packageOverridesContainer = container.nestedContainer(
            keyedBy: RegistryConfiguration.PackageCodingKey.self,
            forKey: .packageOverrides
        )
        for (packageIdentity, packageOverride) in self.packageOverrides {
            let key = RegistryConfiguration.PackageCodingKey(stringValue: packageIdentity.description)
            try packageOverridesContainer.encode(packageOverride, forKey: key)
        }
    }
}
