import Foundation
import Plot
import PlotHTMX

struct AdminInvitationViewModel: Sendable {
    var id: UUID
    var email: String?
    var token: String
    var expiresAt: Date
    var createdAt: Date?
    var isConsumed: Bool
}

struct AdminInvitationsPage {
    var invitations: [AdminInvitationViewModel]
    var baseURL: String
    var pageContext: PageContext

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy h:mm a"
        return f
    }()

    var html: HTML {
        PageLayout(title: "Invitations", pageContext: pageContext) {
            H1("Invitations")

            // Create form
            Element(name: "form") {
                Div {
                    FormField(label: "Email (optional)", name: "email", type: "email",
                              placeholder: "invitee@example.com")
                    FormField(label: "Expires in (days)", name: "expires_days", type: "number",
                              value: "7", min: "1", max: "30")
                }
                .class("form-row")
                Element(name: "button") { Text("Create Invitation") }
                    .type("submit")
                    .class("button primary")
            }
            .attribute(named: "method", value: "POST")
            .attribute(named: "action", value: "/admin/invitations")
            .class("invite-form")

            if !invitations.isEmpty {
                Element(name: "table") {
                    Element(name: "thead") {
                        Element(name: "tr") {
                            Element(name: "th") { Text("Email") }
                            Element(name: "th") { Text("URL") }
                            Element(name: "th") { Text("Expires") }
                            Element(name: "th") { Text("Status") }
                            Element(name: "th") { Text("Actions") }
                        }
                    }
                    Element(name: "tbody") {
                        for inv in invitations {
                            Element(name: "tr") {
                                Element(name: "td") { Text(inv.email ?? "Anyone") }
                                Element(name: "td") {
                                    let url = "\(baseURL)/invite/\(inv.token)"
                                    Element(name: "code") { Text(String(inv.token.prefix(12))) }
                                        .title(url)
                                    Text(" ")
                                    Element(name: "button") { Text("Copy") }
                                        .type("button")
                                        .class("button small secondary")
                                        .on("click", "navigator.clipboard.writeText('\(url)');this.textContent='Copied!'")
                                }
                                Element(name: "td") {
                                    Text(Self.dateFormatter.string(from: inv.expiresAt))
                                }
                                Element(name: "td") {
                                    Text(inv.isConsumed ? "Used" : "Pending")
                                }
                                Element(name: "td") {
                                    if !inv.isConsumed {
                                        Element(name: "form") {
                                            Element(name: "button") { Text("Delete") }
                                                .type("submit")
                                                .class("button small danger")
                                        }
                                        .attribute(named: "method", value: "POST")
                                        .attribute(named: "action", value: "/admin/invitations/\(inv.id)/delete")
                                    }
                                }
                            }
                        }
                    }
                }
                .class("data-table")
            }
        }.html
    }
}
