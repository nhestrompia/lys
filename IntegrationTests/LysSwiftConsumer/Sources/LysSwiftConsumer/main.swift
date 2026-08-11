import Foundation
import Lys

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/lys-contract.json")

Lys.configure(.init(bundleIdentifier: "com.example.consumer", displayName: "Consumer"))
Lys.registry.register(LysScreen(id: "home", title: "Home"))
Lys.registry.register(LysScreen(id: "done", title: "Done", terminal: true))
Lys.registry.register(
  LysAction(id: "finish", title: "Finish", route: "home", resultsIn: "done"))
Lys.register(
  .authenticated(
    id: "authenticated.user", title: "Authenticated user",
    tokenEnvironmentKey: "LYS_TEST_SESSION_TOKEN", tokenSecret: "test.session",
    readyWhen: [.route("home")]))
Lys.register(
  LysFlow(
    id: "flow.finish", title: "Finish", context: "authenticated.user", startRoute: "home",
    steps: [.init(id: "finish", title: "Finish", kind: .invoke, capability: "finish")],
    acceptance: [.route("done"), .init(.noCrash)]))

try Lys.exportContract(to: output)
let decoded = try JSONDecoder().decode(LysContract.self, from: Data(contentsOf: output))
guard decoded.flows.map(\.id) == ["flow.finish"] else {
  throw LysContractValidationError("Consumer export produced the wrong flow")
}
print("Lys Swift consumer exported a validated contract")
