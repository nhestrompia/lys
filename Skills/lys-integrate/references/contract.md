# Contract modeling

The canonical file is `.lys/contract.json`, schema version 2.

## Model

- `routes`: stable observable screens; use one or more predicates. Mark result screens `terminal`.
- `app.entryRoutes`: real bootstrap/attachment routes such as Home or signed-out login.
- `capabilities`: real UI actions with a stable selector, optional source/result route, parameters,
  and risk (`readOnly`, `reversible`, `destructive`, `external`).
- `contexts`: deterministic preparation plus `readyWhen`. Use `uiFlow` or `authenticatedSession`.
- `flows`: the bounded outcome, `startRoute`, supported `entryRoutes`, optional parameters and
  `requiredSecrets`, steps, and acceptance.

Every guaranteed entry route must reach the start route through non-destructive capabilities that
declare both `route` and `resultsIn`. The SDK and host expand each flow's runtime entries with every
additional known route that has such a safe path. This lets a restored app continue from its actual
screen without turning a manually maintained entry list into a brittle whitelist. The host executes
that route path before the flow body. Contract export must fail if a guaranteed path is missing.
When a path control is below or above the viewport, the host resolves its stable semantic selector,
uses native scroll-to-visible activation, and falls back to bounded scrolling on the largest page
scroll surface. Keep viewport mechanics out of product flow declarations.
The SDK also symbolically executes the flow and rejects an action
whose declared route does not equal the route reached by preceding steps. Never rely on the app
already showing the start screen.
For a flow without a normalizing context, `flow.entryRoutes` must include every app entry route.
This prevents a contract from claiming “independently startable” by listing only the flow's own
start screen. UI preparation contexts cover app entries themselves; authenticated contexts may
normalize to their route-based `readyWhen` through a protected relaunch.
UI contexts with `prepare` steps follow the same rule so login/logout preparation is independent of
the screen left open by the user. Authenticated-session contexts relaunch through the host fixture
and do not need UI entry navigation unless they also declare preparation steps.

Supported actions: `tap`, `doubleTap`, `longPress`, `type`, `clear`, `toggle`, `select`, `scrollUp`,
`scrollDown`, `swipe`, `drag`, `setSlider`, `dismiss`, and `back`.

Supported predicates: `route`, `visible`, `absent`, `enabled`, `selected`, `value`, `text`,
`progressComplete`, `appIdle`, and `noCrash`.

Steps are `navigate`, `invoke`, `assert`, or `repeatUntil`. A repeat requires `until`, non-empty
nested steps, and `maximumIterations` from 1 through 1000.

## Auth rules

- Use `authenticatedSession` only as setup. Declare environment values as `literal`, `parameter`, or
  logical `secret`; list injected secrets in the context's `requiredSecrets`.
- Use `uiFlow` to test the actual login interface. Put email/password secret IDs in the flow's
  `requiredSecrets` and use them as sensitive action arguments.
- Never place a secret value in the contract, agent prompt, command arguments, evidence, or logs.

## Completion rules

A trusted green result requires the declared flow to finish, every current-generation acceptance
criterion to pass, no unacknowledged crash, and required launch/screenshot evidence. Exploratory
runs without a contract cannot produce trusted verification. An agent ending its turn is not a test
result.

A partial contract is valid but must remain visibly partial. If the requested goal does not uniquely
match a declared flow, Lys may explore host-discovered UI actions, but the result cannot be reported
as deterministic or complete. Add the missing flow when the outcome needs trusted verification.
