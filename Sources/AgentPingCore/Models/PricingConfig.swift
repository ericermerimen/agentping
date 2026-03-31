import Foundation

public struct TokenPricing: Codable, Equatable {
    public let input: Double      // per million tokens
    public let output: Double
    public let cacheRead: Double
    public let cacheWrite: Double

    public init(input: Double, output: Double, cacheRead: Double, cacheWrite: Double) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }
}

public struct ModelPricing: Codable, Equatable {
    public let model: String      // e.g. "opus", "sonnet", "haiku"
    public let provider: String   // "anthropic" or "bedrock"
    public let pricing: TokenPricing
    public let tieredThreshold: Int?  // e.g. 200000 for Sonnet
    public let tieredPricing: TokenPricing?  // rates above threshold

    public init(model: String, provider: String, pricing: TokenPricing, tieredThreshold: Int? = nil, tieredPricing: TokenPricing? = nil) {
        self.model = model
        self.provider = provider
        self.pricing = pricing
        self.tieredThreshold = tieredThreshold
        self.tieredPricing = tieredPricing
    }
}

public struct PricingConfig: Codable, Equatable {
    public let version: Int
    public let models: [ModelPricing]

    public static let configPath = "~/.agentping/pricing.json"

    public init(version: Int, models: [ModelPricing]) {
        self.version = version
        self.models = models
    }

    /// Load pricing config from disk, falling back to defaults.
    /// Writes defaults to disk on first load if the file doesn't exist.
    public static func load() -> PricingConfig {
        let expandedPath = NSString(string: configPath).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        if let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(PricingConfig.self, from: data) {
            return config
        }

        let fallback = defaults()

        // Write defaults to disk for user discoverability
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.agentPing.encode(fallback) {
            try? data.write(to: url)
        }

        return fallback
    }

    /// Built-in default pricing for all known models.
    public static func defaults() -> PricingConfig {
        PricingConfig(version: 1, models: [
            // Anthropic direct
            ModelPricing(model: "opus", provider: "anthropic",
                         pricing: TokenPricing(input: 15.0, output: 75.0, cacheRead: 1.50, cacheWrite: 18.75)),
            ModelPricing(model: "sonnet", provider: "anthropic",
                         pricing: TokenPricing(input: 3.0, output: 15.0, cacheRead: 0.30, cacheWrite: 3.75),
                         tieredThreshold: 200_000,
                         tieredPricing: TokenPricing(input: 6.0, output: 30.0, cacheRead: 0.60, cacheWrite: 7.50)),
            ModelPricing(model: "haiku", provider: "anthropic",
                         pricing: TokenPricing(input: 0.80, output: 4.0, cacheRead: 0.08, cacheWrite: 1.0)),
            // Bedrock
            ModelPricing(model: "opus", provider: "bedrock",
                         pricing: TokenPricing(input: 15.0, output: 75.0, cacheRead: 1.50, cacheWrite: 18.75)),
            ModelPricing(model: "sonnet", provider: "bedrock",
                         pricing: TokenPricing(input: 3.0, output: 15.0, cacheRead: 0.30, cacheWrite: 3.75)),
            ModelPricing(model: "haiku", provider: "bedrock",
                         pricing: TokenPricing(input: 0.80, output: 4.0, cacheRead: 0.08, cacheWrite: 1.0)),
        ])
    }

    /// Look up pricing for a given model ID string.
    /// Returns base pricing, optional tiered threshold, and optional tiered pricing.
    public func pricing(for modelId: String) -> (TokenPricing, tieredThreshold: Int?, tieredPricing: TokenPricing?) {
        let id = modelId.lowercased()

        // Determine provider from model ID
        let provider: String
        if id.hasPrefix("anthropic.") || id.hasPrefix("us.anthropic.") {
            provider = "bedrock"
        } else {
            provider = "anthropic"
        }

        // Determine model family
        let family: String
        if id.contains("opus") {
            family = "opus"
        } else if id.contains("haiku") {
            family = "haiku"
        } else {
            family = "sonnet" // default
        }

        // Find matching entry: prefer provider-specific, fall back to any match
        if let match = models.first(where: { $0.model == family && $0.provider == provider }) {
            return (match.pricing, tieredThreshold: match.tieredThreshold, tieredPricing: match.tieredPricing)
        }
        if let match = models.first(where: { $0.model == family }) {
            return (match.pricing, tieredThreshold: match.tieredThreshold, tieredPricing: match.tieredPricing)
        }

        // Ultimate fallback: Sonnet anthropic pricing
        return (TokenPricing(input: 3.0, output: 15.0, cacheRead: 0.30, cacheWrite: 3.75), tieredThreshold: nil, tieredPricing: nil)
    }
}
