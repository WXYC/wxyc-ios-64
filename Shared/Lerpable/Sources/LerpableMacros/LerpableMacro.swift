//
//  LerpableMacro.swift
//  LerpableMacros
//
//  Macro implementation that generates Lerpable conformance by inspecting
//  stored properties and generating a lerp function that interpolates each.
//
//  Created by Jake Bromberg on 01/15/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftCompilerPlugin

public struct LerpableMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Only works on structs
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw LerpableMacroError.notAStruct
        }

        // Extract stored properties
        let storedProperties = structDecl.memberBlock.members.compactMap { member -> StoredProperty? in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  varDecl.bindingSpecifier.tokenKind == .keyword(.var),
                  let binding = varDecl.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                  !hasComputedAccessor(binding)
            else {
                return nil
            }

            return StoredProperty(
                name: identifier.identifier.text,
                type: binding.typeAnnotation?.type
            )
        }

        guard !storedProperties.isEmpty else {
            throw LerpableMacroError.noStoredProperties
        }

        // Generate the lerp function body
        let propertyLerps = storedProperties.map { prop in
            "\(prop.name): .lerp(a.\(prop.name), b.\(prop.name), t: t)"
        }.joined(separator: ",\n                ")

        let extensionDecl: DeclSyntax = """
            extension \(type.trimmed): Lerpable {
                public static func lerp(_ a: Self, _ b: Self, t: Double) -> Self {
                    Self(
                        \(raw: propertyLerps)
                    )
                }
            }
            """

        return [extensionDecl.cast(ExtensionDeclSyntax.self)]
    }

    private static func hasComputedAccessor(_ binding: PatternBindingSyntax) -> Bool {
        guard let accessor = binding.accessorBlock else {
            return false
        }

        switch accessor.accessors {
        case .getter:
            return true
        case .accessors(let accessorList):
            // If it has get with a body, it's computed
            for accessor in accessorList {
                if accessor.accessorSpecifier.tokenKind == .keyword(.get),
                   accessor.body != nil {
                    return true
                }
            }
            return false
        }
    }
}

private struct StoredProperty {
    let name: String
    let type: TypeSyntax?
}

enum LerpableMacroError: Error, CustomStringConvertible {
    case notAStruct
    case noStoredProperties

    var description: String {
        switch self {
        case .notAStruct:
            "@Lerpable can only be applied to structs"
        case .noStoredProperties:
            "@Lerpable requires at least one stored property"
        }
    }
}

// MARK: - Plugin Entry Point

@main
struct LerpablePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        LerpableMacro.self,
    ]
}
