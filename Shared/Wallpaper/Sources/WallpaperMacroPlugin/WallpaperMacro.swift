//
//  WallpaperMacro.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/19/25.
//

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

public enum WallpaperMacro: MemberMacro {
    // MARK: - MemberMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            context.diagnose(Diagnostic(
                node: node,
                message: WallpaperMacroDiagnostic.notAClass
            ))
            return []
        }

        // Check if class already has an init()
        let hasExistingInit = classDecl.memberBlock.members.contains { member in
            guard let initDecl = member.decl.as(InitializerDeclSyntax.self) else {
                return false
            }
            // Check for parameterless init
            return initDecl.signature.parameterClause.parameters.isEmpty
        }

        if hasExistingInit {
            context.diagnose(Diagnostic(
                node: node,
                message: WallpaperMacroDiagnostic.hasExistingInit
            ))
            return []
        }

        let typeName = classDecl.name.text

        return [
            """
            private static let _registered: Bool = {
                WallpaperProvider.shared.registerType(\(raw: typeName).self)
                return true
            }()
            """,
            """
            public init() {
                _ = Self._registered
                self.configure()
            }
            """
        ]
    }

}

enum WallpaperMacroDiagnostic: String, DiagnosticMessage {
    case notAClass
    case hasExistingInit

    var severity: DiagnosticSeverity { .error }

    var message: String {
        switch self {
        case .notAClass:
            return "@Wallpaper can only be applied to a class"
        case .hasExistingInit:
            return "@Wallpaper generates init() - remove your init() and use configure() instead"
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "WallpaperMacro", id: rawValue)
    }
}
