# Contract modeling

The canonical file is `.lys/contract.json`, schema version 1.

## Model

- `routes`: stable observable screens; use one or more predicates. Mark result screens `terminal`.
- `capabilities`: real UI actions with a stable selector, optional source/result route, parameters,
  and risk (`readOnly`, `reversible`, `destructive`, `external`).
- `contexts`: deterministic preparation plus `readyWhen`. Use `uiFlow` or `authenticatedSession`.
- `flows`: the bounded outcome, optional parameters and `requiredSecrets`, steps, and acceptance.

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
