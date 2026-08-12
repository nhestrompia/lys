# @lys/testkit

Small semantic test contracts for Expo and React Native apps tested with Lys. Add stable props to
real controls, declare bounded flows, and export `.lys/contract.json`; Lys performs physical input
and deterministic verification outside the app.

Declare guaranteed bootstrap/restoration screens and reuse shared screen/action objects in both UI
and export code. Contract export rejects missing guaranteed paths and copied string IDs, then adds
every other declared screen that can safely reach each flow start. A restored app therefore resumes
from its observed route instead of failing on a manually maintained entry whitelist.

See the repository's `LYS_SDK.md` for Swift/Expo examples and authenticated-session guidance.
