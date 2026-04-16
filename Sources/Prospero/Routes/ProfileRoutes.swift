import FluentKit
import Hummingbird
import HummingbirdAuth
import Plot

func addProfileRoutes(
    to router: RouterGroup<AuthedContext>,
    db: Database
) {
    router.get("/profile") { _, context -> HTML in
        ProfilePage(
            displayName: context.user.displayName,
            email: context.user.email,
            pageContext: PageContext(from: context)
        ).html
    }

    router.post("/profile") { request, context -> HTML in
        struct ProfileInput: Decodable {
            var display_name: String
            var email: String
        }

        let input = try await URLEncodedFormDecoder().decode(
            ProfileInput.self, from: request, context: context
        )

        let user = context.user
        user.displayName = input.display_name.trimmingCharacters(in: .whitespacesAndNewlines)
        user.email = input.email.trimmingCharacters(in: .whitespacesAndNewlines)
        try await user.save(on: db)

        return ProfilePage(
            displayName: user.displayName,
            email: user.email,
            savedMessage: "Profile updated.",
            pageContext: PageContext(from: context)
        ).html
    }
}
