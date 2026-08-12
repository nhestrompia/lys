import Foundation
import Lys

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/lys-contract.json")

let home = LysScreen(id: "home", title: "Home")
let done = LysScreen(id: "done", title: "Done", terminal: true)
let finish = LysAction(id: "finish", title: "Finish", route: home, resultsIn: done)
Lys.configure(
  .init(
    bundleIdentifier: "com.example.consumer", displayName: "Consumer",
    entryRoutes: [home]))
Lys.register(home)
Lys.register(done)
Lys.register(finish)
Lys.register(
  .authenticated(
    id: "authenticated.user", title: "Authenticated user",
    tokenEnvironmentKey: "LYS_TEST_SESSION_TOKEN", tokenSecret: "test.session",
    readyWhen: [.route(home)]))
Lys.register(
  LysFlow(
    id: "flow.finish", title: "Finish", context: "authenticated.user", startRoute: home,
    entryRoutes: [home],
    steps: [.invoke(id: "finish", title: "Finish", action: finish)],
    acceptance: [.route(done), .init(.noCrash)]))

try Lys.exportContract(to: output)
let decoded = try JSONDecoder().decode(LysContract.self, from: Data(contentsOf: output))
guard decoded.flows.map(\.id) == ["flow.finish"] else {
  throw LysContractValidationError("Consumer export produced the wrong flow")
}
print("Lys Swift consumer exported a validated contract")
