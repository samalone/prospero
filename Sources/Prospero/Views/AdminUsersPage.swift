import Foundation
import Plot
import PlotHTMX

struct AdminUserViewModel: Sendable {
    var id: UUID
    var displayName: String
    var email: String
    var isAdmin: Bool
    var createdAt: Date?
}

struct AdminUsersPage {
    var users: [AdminUserViewModel]
    var pageContext: PageContext

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    var html: HTML {
        PageLayout(title: "Users", pageContext: pageContext) {
            H1("Users")

            Element(name: "table") {
                Element(name: "thead") {
                    Element(name: "tr") {
                        Element(name: "th") { Text("Name") }
                        Element(name: "th") { Text("Email") }
                        Element(name: "th") { Text("Role") }
                        Element(name: "th") { Text("Joined") }
                        Element(name: "th") { Text("Actions") }
                    }
                }
                Element(name: "tbody") {
                    for user in users {
                        Element(name: "tr") {
                            Element(name: "td") { Text(user.displayName) }
                            Element(name: "td") { Text(user.email) }
                            Element(name: "td") {
                                Element(name: "span") {
                                    Text(user.isAdmin ? "Admin" : "User")
                                }
                                .class(user.isAdmin ? "role-badge role-admin" : "role-badge")
                            }
                            Element(name: "td") {
                                Text(user.createdAt.map { Self.dateFormatter.string(from: $0) } ?? "")
                            }
                            Element(name: "td") {
                                Div {
                                    if user.isAdmin {
                                        Element(name: "form") {
                                            Node.input(.type(.hidden), .name("role"), .value("user"))
                                            Element(name: "button") { Text("Remove admin") }
                                                .type("submit")
                                                .class("button small secondary")
                                        }
                                        .attribute(named: "method", value: "POST")
                                        .attribute(named: "action", value: "/admin/users/\(user.id)/role")
                                    } else {
                                        Element(name: "form") {
                                            Node.input(.type(.hidden), .name("role"), .value("admin"))
                                            Element(name: "button") { Text("Make admin") }
                                                .type("submit")
                                                .class("button small secondary")
                                        }
                                        .attribute(named: "method", value: "POST")
                                        .attribute(named: "action", value: "/admin/users/\(user.id)/role")
                                    }
                                }
                                .class("table-actions")
                            }
                        }
                    }
                }
            }
            .class("data-table")
        }.html
    }
}
