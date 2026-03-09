//
//  AnalyticsEventMacro.swift
//  AnalyticsMacros
//
//  Macro implementation that synthesizes the `properties` computed property
//  for AnalyticsEvent conforming types by iterating stored properties and
//  converting their names to snake_case.
//
//  Created by Claude on 01/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - Macro Implementation

public struct AnalyticsEventMacro: MemberMacro, ExtensionMacro {

    // MARK: - MemberMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Ensure we're attached to a struct
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw AnalyticsEventMacroError.notAStruct
        }

        // Get all stored properties (excluding static and computed)
        let storedProperties = structDecl.memberBlock.members.compactMap { member -> (name: String, hasDefault: Bool)? in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  varDecl.bindingSpecifier.tokenKind == .keyword(.let) || varDecl.bindingSpecifier.tokenKind == .keyword(.var),
                  !varDecl.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) else {
                return nil
            }

            // Check if it's a stored property (no accessor block or only has initializer)
            guard let binding = varDecl.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                return nil
            }

            // Skip computed properties (those with get/set accessors)
            if let accessor = binding.accessorBlock {
                // If it has accessors, it's computed
                switch accessor.accessors {
                case .accessors:
                    return nil
                case .getter:
                    return nil
                }
            }

            let hasDefault = binding.initializer != nil
            return (identifier.identifier.text, hasDefault)
        }

        // Filter out 'name' property since it's static
        let eventProperties = storedProperties.filter { $0.name != "name" }

        // Check if struct already has an explicit 'name' property
        let hasExplicitName = structDecl.memberBlock.members.contains { member in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  varDecl.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }),
                  let binding = varDecl.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                return false
            }
            return identifier.identifier.text == "name"
        }

        var declarations: [DeclSyntax] = []

        // Generate `name` property if not explicitly provided
        if !hasExplicitName {
            let typeName = structDecl.name.text
            let snakeCaseName = typeName.convertedToSnakeCase()
            declarations.append(
                """
                public static let name: String = \"\(raw: snakeCaseName)\"
                """
            )
        }

        // Generate `properties` computed property
        if eventProperties.isEmpty {
            declarations.append(
                """
                public var properties: [String: Any]? { nil }
                """
            )
        } else {
            var dictEntries: [String] = []
            for prop in eventProperties {
                let snakeCase = prop.name.convertedToSnakeCase()
                dictEntries.append("        \"\(snakeCase)\": \(prop.name)")
            }
            let entriesText = dictEntries.joined(separator: ",\n")

            declarations.append(
                """
                public var properties: [String: Any]? {
                    [
                \(raw: entriesText)
                    ]
                }
                """
            )
        }

        return declarations
    }

    // MARK: - ExtensionMacro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Only add conformance if not already present
        let ext: DeclSyntax =
            """
            extension \(type.trimmed): AnalyticsEvent {}
            """

        return [ext.cast(ExtensionDeclSyntax.self)]
    }
}

// MARK: - Error Types

enum AnalyticsEventMacroError: Error, CustomStringConvertible {
    case notAStruct

    var description: String {
        switch self {
        case .notAStruct:
            return "@AnalyticsEvent can only be applied to structs"
        }
    }
}

// MARK: - String Extension for Snake Case

extension String {
    /// Converts a PascalCase or camelCase string to snake_case.
    /// Handles acronyms by keeping them together (e.g., "CPUUsage" -> "cpu_usage").
    func convertedToSnakeCase() -> String {
        guard !isEmpty else { return self }

        var result = ""
        var previousWasUppercase = false
        var previousWasUnderscore = false

        for (index, character) in enumerated() {
            let isUppercase = character.isUppercase

            if isUppercase {
                // Check if this uppercase letter ends an acronym (next char is lowercase)
                let isEndOfAcronym = previousWasUppercase && index + 1 < count && !self[self.index(startIndex, offsetBy: index + 1)].isUppercase

                if index > 0 && !previousWasUnderscore {
                    if !previousWasUppercase || isEndOfAcronym {
                        result.append("_")
                    }
                }
                result.append(character.lowercased())
                previousWasUppercase = true
            } else {
                result.append(character)
                previousWasUppercase = false
            }

            previousWasUnderscore = character == "_"
        }

        return result
    }
}

// MARK: - Plugin

@main
struct AnalyticsMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        AnalyticsEventMacro.self,
    ]
}
