//
//  RuntimeShaderCompiler.swift
//  Wallpaper
//
//  Compiles Metal shaders at runtime for live editing.
//
//  Created by Jake Bromberg on 12/22/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Metal
import Foundation

/// Compiles Metal shaders at runtime with configurable preprocessor directives.
///
/// This allows toggling shader features without passing runtime parameters,
/// enabling zero-cost feature flags that are resolved at compile time.
public final class RuntimeShaderCompiler {
    private let device: MTLDevice
    private var shaderSource: String
    private var library: MTLLibrary?

    /// Tracks which directives are currently enabled
    private var enabledDirectives: Set<String> = []

    /// All known directives in the shader source
    private(set) var availableDirectives: [String] = []

    public init(device: MTLDevice, shaderSource: String) {
        self.device = device
        self.shaderSource = shaderSource
        self.availableDirectives = parseDirectives(from: shaderSource)
        self.enabledDirectives = Set(availableDirectives) // All enabled by default
    }

    /// Loads shader source from a file in the bundle.
    public convenience init?(device: MTLDevice, shaderName: String, bundle: Bundle) {
        guard let url = bundle.url(forResource: shaderName, withExtension: "metal"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        self.init(device: device, shaderSource: source)
    }

    /// Whether a specific directive is enabled.
    public func isDirectiveEnabled(_ name: String) -> Bool {
        enabledDirectives.contains(name)
    }

    /// Sets whether a directive is enabled and recompiles if needed.
    public func setDirective(_ name: String, enabled: Bool) {
        let wasEnabled = enabledDirectives.contains(name)
        if enabled {
            enabledDirectives.insert(name)
        } else {
            enabledDirectives.remove(name)
        }

        // Mark library as needing recompilation if state changed
        if wasEnabled != enabled {
            library = nil
        }
    }

    /// Compiles the shader with current directive settings.
    public func compile() throws -> MTLLibrary {
        if let library = library {
            return library
        }

        let modifiedSource = applyDirectives(to: shaderSource)

        let options = MTLCompileOptions()
        options.fastMathEnabled = true

        do {
            let lib = try device.makeLibrary(source: modifiedSource, options: options)
            self.library = lib
            return lib
        } catch {
            throw CompilerError.compilationFailed(error.localizedDescription)
        }
    }

    /// Gets a function from the compiled library.
    public func makeFunction(name: String) throws -> MTLFunction {
        let lib = try compile()
        guard let function = lib.makeFunction(name: name) else {
            throw CompilerError.functionNotFound(name)
        }
        return function
    }

    // MARK: - Private Helpers

    /// Parses shader source to find all #define directives that look like feature toggles.
    private func parseDirectives(from source: String) -> [String] {
        var directives: [String] = []
        let lines = source.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Look for #define DIRECTIVE_NAME pattern (no value, just a flag)
            if trimmed.hasPrefix("#define ") {
                let rest = trimmed.dropFirst("#define ".count)
                let parts = rest.components(separatedBy: .whitespaces)
                if let name = parts.first, !name.isEmpty {
                    // Skip defines with values (like NOISE_OCTAVES 4)
                    let restAfterName = rest.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
                    if restAfterName.isEmpty || restAfterName.hasPrefix("//") {
                        directives.append(name)
                    }
                }
            }
        }

        return directives
    }

    /// Applies current directive settings by commenting/uncommenting #define lines.
    private func applyDirectives(to source: String) -> String {
        var lines = source.components(separatedBy: "\n")

        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            // Handle enabled directive that might be commented
            for directive in availableDirectives {
                if enabledDirectives.contains(directive) {
                    // Should be enabled - uncomment if needed
                    if trimmed.hasPrefix("// #define \(directive)") || trimmed.hasPrefix("//#define \(directive)") {
                        lines[i] = lines[i].replacingOccurrences(of: "// #define \(directive)", with: "#define \(directive)")
                        lines[i] = lines[i].replacingOccurrences(of: "//#define \(directive)", with: "#define \(directive)")
                    }
                } else {
                    // Should be disabled - comment if needed
                    if trimmed.hasPrefix("#define \(directive)") && !trimmed.hasPrefix("// ") {
                        lines[i] = lines[i].replacingOccurrences(of: "#define \(directive)", with: "// #define \(directive)")
                    }
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Errors

    public enum CompilerError: LocalizedError {
        case compilationFailed(String)
        case functionNotFound(String)

        public var errorDescription: String? {
            switch self {
            case .compilationFailed(let message):
                return "Shader compilation failed: \(message)"
            case .functionNotFound(let name):
                return "Function '\(name)' not found in shader library"
            }
        }
    }
}
