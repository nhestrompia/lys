# @lys/testkit

Small semantic test contracts for Expo and React Native apps tested with Lys. Add stable props to
real controls, declare bounded flows, and export `.lys/contract.json`; Lys performs physical input
and deterministic verification outside the app.

Declare guaranteed bootstrap/restoration screens and reuse shared screen/action objects in both UI
and export code. Contract export rejects missing guaranteed paths and copied string IDs, then adds
every other declared screen that can safely reach each flow start. A restored app therefore resumes
from its observed route instead of failing on a manually maintained entry whitelist.

See the repository's `LYS_SDK.md` for Swift/Expo examples and authenticated-session guidance.

Independent flow contexts use `isolation: "relaunch"` by default. Before the next flow, the host
relaunches the app with `-LysReset -LysContext <id>` while preserving app data. Use
`testSession.resetRequestedFor(id)` in the app's own router/session setup to establish the
context's `readyWhen` route. Choose `isolation: "preserve"` only for intentionally chained flows.
The host owns `-LysTesting`, `-LysReset`, and `-LysContext`; session `arguments` must not redeclare
them.
