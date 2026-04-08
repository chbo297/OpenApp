//
//  ModelProviderCentral.swift
//  OpenAPP
//

import Foundation

/// Model Provider 总站 — 所有 ModelProvider 实例的注册中心。
///
/// Providers are registered with a unique name (e.g., "bdllm", "anthropic")
/// and resolved by compound model references in the format "providerName/modelId".
///
/// Usage:
///   await ModelProviderCentral.default.register(name: "bdllm", provider: myProvider)
///   let result = await ModelProviderCentral.default.resolve(modelReference: "bdllm/Claude sonnet 4.6")
public actor ModelProviderCentral {

    // MARK: - ModelPolicy

    /// Specifies which model(s) an agent should use, with primary + fallback support.
    /// Model references use the "providerName/modelId" format.
    public struct ModelPolicy: Sendable {
        /// Primary model reference (e.g., "bdllm/Claude sonnet 4.6").
        public var primary: String
        /// Fallback model references, tried in order if primary fails.
        public var fallbacks: [String]

        public init(primary: String, fallbacks: [String] = []) {
            self.primary = primary
            self.fallbacks = fallbacks
        }
    }

    /// The default instance, used by most apps.
    public static let `default` = ModelProviderCentral()

    private var providers: [String: any ModelProvider] = [:]

    public init() {}

    // MARK: - Registration

    /// Register a provider under a given name.
    public func register(name: String, provider: any ModelProvider) {
        providers[name] = provider
        Logger.info("ModelProviderCentral", "registered: name=\(name), models=[\(provider.models.map(\.id).joined(separator: ", "))]")
    }

    /// Unregister a provider by name.
    public func unregister(name: String) {
        providers.removeValue(forKey: name)
        Logger.info("ModelProviderCentral", "unregistered: name=\(name)")
    }

    /// All registered provider names.
    public var registeredNames: [String] {
        StableSort.byName(Array(providers.keys))
    }

    /// Get a provider by name.
    public func provider(named name: String) -> (any ModelProvider)? {
        providers[name]
    }

    // MARK: - Resolution

    /// Resolve a compound model reference like "bdllm/Claude sonnet 4.6".
    ///
    /// The reference is split on the first "/" only, so model IDs containing "/"
    /// are supported (e.g., "provider/model/v2" resolves provider "provider" with model "model/v2").
    ///
    /// - Returns: A tuple of `(provider, model)` if both the provider name and model ID match,
    ///   or `nil` otherwise.
    public func resolve(modelReference: String) -> (provider: any ModelProvider, model: ModelConfiguration)? {
        let parts = modelReference.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else {
            Logger.warning("ModelProviderCentral", "resolve: invalid reference format '\(modelReference)', expected 'providerName/modelId'")
            return nil
        }

        let providerName = String(parts[0])
        let modelId = String(parts[1])

        guard let provider = providers[providerName] else {
            Logger.warning("ModelProviderCentral", "resolve: provider '\(providerName)' not found")
            return nil
        }

        guard let model = provider.models.first(where: { $0.id == modelId }) else {
            Logger.warning("ModelProviderCentral", "resolve: model '\(modelId)' not found in provider '\(providerName)', available=[\(provider.models.map(\.id).joined(separator: ", "))]")
            return nil
        }

        return (provider: provider, model: model)
    }

    /// Resolve the default provider and model (first provider alphabetically).
    /// Used as a fallback when no ModelPolicy is configured.
    public func resolveDefault() -> (provider: any ModelProvider, model: ModelConfiguration)? {
        guard let firstName = providers.keys.sorted().first,
              let provider = providers[firstName],
              let model = provider.models.first else { return nil }
        return (provider: provider, model: model)
    }

    /// Build a default ModelPolicy from all registered providers,
    /// ordered by `APIProtocol` case declaration order.
    ///
    /// - The first model of the first provider (by APIProtocol order) becomes `primary`.
    /// - All remaining models become `fallbacks`.
    /// - Returns `nil` if no providers are registered.
    public func defaultPolicy() -> ModelPolicy? {
        var allRefs: [String] = []

        for proto in APIProtocol.allCases {
            for (name, provider) in providers where provider.apiProtocol == proto {
                for model in provider.models {
                    allRefs.append("\(name)/\(model.id)")
                }
            }
        }

        guard let primary = allRefs.first else { return nil }
        return ModelPolicy(primary: primary, fallbacks: Array(allRefs.dropFirst()))
    }
}
