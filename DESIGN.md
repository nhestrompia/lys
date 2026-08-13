---
name: "Lys"
description: "A luminous native macOS studio that keeps agent intent, the running app, and machine-recorded proof in one view."
colors:
  primary: "#0A63F2"
  primary-soft: "#E8F2FF"
  canvas: "#F6F7F8"
  surface: "#FFFFFF"
  raised: "#F4F5F7"
  label: "rgba(0, 0, 0, 0.85)"
  label-secondary: "#6E6E73"
  label-tertiary: "#98989D"
  separator: "rgba(0, 0, 0, 0.085)"
  success: "#52B361"
  warning: "#FF9500"
  danger: "#FF3B30"
  device-shell: "#141618"
typography:
  headline:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif"
    fontSize: "21px"
    fontWeight: 700
    lineHeight: 1.24
    letterSpacing: "normal"
  title:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif"
    fontSize: "18px"
    fontWeight: 700
    lineHeight: 1.25
    letterSpacing: "normal"
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.35
    letterSpacing: "normal"
  label:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif"
    fontSize: "11px"
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: "normal"
  mono:
    fontFamily: "ui-monospace, 'SF Mono', Menlo, monospace"
    fontSize: "10px"
    fontWeight: 500
    lineHeight: 1.3
    letterSpacing: "normal"
rounded:
  control: "8px"
  selection: "9px"
  field: "10px"
  group: "12px"
  panel: "14px"
  pill: "999px"
spacing:
  tight: "4px"
  compact: "8px"
  standard: "12px"
  control: "16px"
  panel: "20px"
  section: "24px"
  workspace: "32px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.surface}"
    typography: "{typography.label}"
    rounded: "{rounded.control}"
    padding: "0 18px"
    height: "44px"
  toolbar-control:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.label}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "0 12px"
    height: "36px"
  panel:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.label}"
    rounded: "{rounded.panel}"
    padding: "20px"
  prompt-field:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.label}"
    typography: "{typography.body}"
    rounded: "{rounded.field}"
    padding: "0 12px"
    height: "44px"
  nav-item-active:
    backgroundColor: "{colors.primary-soft}"
    textColor: "{colors.primary}"
    typography: "{typography.label}"
    rounded: "{rounded.selection}"
    size: "38px 34px"
---

# Design System: Lys

## Overview

**Creative North Star: "The Luminous Native Studio"**

The workbench is a bright, exacting macOS instrument built around one thesis: the running iOS app is the center of work, while agent intent and verification remain visibly adjacent. It should feel like a first-party desktop utility—quiet, crisp, and operational—not an IDE-dark dashboard, a chat window with tools attached, or a decorative card canvas.

White working surfaces sit on a cool luminous canvas. System blue identifies selection, control, and forward action; green is deliberately scarce and appears only when the machine has recorded success. Density is compact but never cramped: hierarchy comes from stable regions, grouped lists, hairline separators, and disciplined type rather than oversized headings or ornamental chrome.

The signature composition keeps the developer's causal story legible without changing views: open a repository, delegate in an isolated worktree, watch the app, inspect fresh generation-scoped evidence, then review and apply or discard. The interface stays transparent and recoverable at every boundary.

**FORM provenance.** The shipped form is a direct native reproduction of the user-supplied approved reference at `/var/folders/nx/yjq006696mz0bdbbjl96t8g00000gn/T/codex-clipboard-41a70dfc-90f7-44b2-97b1-2a75e13ab85e.png` (1536 × 1024 viewport; SHA-256 `a0147fa507a0f01639a54b67801528fefdf4ea7090895348237d795d6b1981ab`). This exact reference is the visual authority for composition and form when documentation or derivative screens drift.

**Key Characteristics:**

- Luminous light-only native macOS surfaces with restrained cool-gray tonal layering.
- A central app stage with the phone top-weighted beneath its toolbar, flanked by agent intent on the left and verification truth on the right.
- Compact San Francisco typography and SF Symbols throughout the interface.
- Fourteen-point structural corners, smaller continuous corners for controls, and capsule geometry only for compact state selectors.
- System blue for interaction; green only for fresh machine-recorded success.
- Quiet one-pixel separators and low ambient shadows rather than gradients, glass, or decorative texture.

## Colors

The palette is a native cool-neutral field with one clear action blue and tightly governed semantic state colors.

### Primary

- **Workbench Blue** (#0A63F2): Drives primary actions, selected navigation, active plan state, interactive labels, and focus-bearing controls.
- **Selection Mist** (#E8F2FF): Carries blue selection into low-emphasis backgrounds without turning whole panels blue.

### Secondary

- **Recorded Green** (#52B361): Marks only passed verification, completed plan steps, detected-ready integrations, and other machine-recorded success.

### Tertiary

- **System Orange** (#FF9500): Communicates blocked compatibility, recoverable warnings, and apply conflicts.
- **System Red** (#FF3B30): Communicates failed verification and destructive change status.

### Neutral

- **Studio Canvas** (#F6F7F8): The cool page field behind the three primary work areas.
- **Working White** (#FFFFFF): The opaque surface for toolbars, rails, panels, grouped rows, and the review bar.
- **Raised Control** (#F4F5F7): A slightly darker neutral for toolbar controls, the task prompt, and evidence thumbnails.
- **Primary Label** (rgba(0, 0, 0, 0.85)): The portable light-appearance equivalent of the native high-contrast foreground for task titles and essential values.
- **Secondary Label** (#6E6E73): The portable light-appearance equivalent of AppKit's secondary label for descriptions, timestamps, inactive states, and metadata.
- **Tertiary Label** (#98989D): The portable light-appearance equivalent of AppKit's tertiary label for placeholders and unavailable controls.
- **Hairline Separator** (rgba(0, 0, 0, 0.085)): A low-alpha black divider that organizes dense native lists without boxing every row.
- **Device Shell** (#141618): The near-black frame reserved for the central iPhone preview.

### Named Rules

**The Blue Means Agency Rule.** Blue means the user can act, a control is selected, or work is currently active; it is not decorative fill.

**The Green Is Recorded Truth Rule.** Green appears only after a machine-observed success. Agent prose, optimistic status, and mere availability never earn it.

**The Semantic Neutral Rule.** Native label roles remain semantic in SwiftUI so contrast and accessibility behavior come from AppKit; the portable frontmatter values describe the shipped light appearance.

## Typography

**Display Font:** San Francisco via the macOS system font
**Body Font:** San Francisco via the macOS system font
**Label/Mono Font:** San Francisco for interface labels; SF Mono only for code, paths, identifiers, change kinds, generations, times, and tabular counts

**Character:** The typography is compact, native, and information-forward. Weight and color establish hierarchy inside fixed regions; size changes are modest so the running app remains the visual anchor.

### Hierarchy

- **Headline** (bold, 21pt, 1.24): The task prompt or primary empty-state question inside the Agent panel.
- **Title** (bold, 18pt, 1.25): The window identity, verification summary, and change-review title.
- **Body** (regular, 12pt, 1.35): Descriptions, task activity, toolbar values, and most operational copy.
- **Label** (semibold, 11pt, 1.25): Section labels, compact controls, statuses, and row headings; select row titles step up to 12–13pt when they carry the scan path.
- **Mono** (medium, 10pt, 1.3): Generations, timestamps, file-change kinds, file paths, and numeric evidence metadata only.

### Named Rules

**The Compact Hierarchy Rule.** Create hierarchy with weight, semantic color, and placement before increasing type size; operational UI should not compete with the app under test.

**The Monospace Earns Its Place Rule.** Use monospaced treatment only when alignment or literal identity matters, never as a broad developer-aesthetic texture.

## Layout

The application is a desktop-first macOS workbench with a minimum window of 1180 × 680pt and a default size of 1440 × 860pt. Restored windows are clamped to the current display's visible frame so neither the title region nor the review boundary can open behind the menu bar, notch, or Dock. A 68pt toolbar spans the top, an 88pt persistent navigation rail owns the left edge, and a 76pt review bar anchors the bottom. These three pieces have layout priority over the scrollable work area and never scroll away.

The Agent first viewport uses a fixed 380pt intent panel, a flexible center app stage, and a fixed 420pt verification ledger. The regions sit in a 12pt gap with a 12pt outer inset. The phone preview remains horizontally centered but is top-weighted directly beneath the stage toolbar; intent and proof are adjacent context, not alternate destinations. Inside panels, recurring horizontal insets are 20–22pt, grouped rows are 64–70pt tall, and toolbars are 48–52pt tall.

The rail switches between Develop, Code, Deploy, and Settings workspaces. Develop is the primary operating surface; Code retains repository context, Deploy owns TestFlight distribution, and Settings uses grouped native lists. Change review remains available from the persistent decision bar instead of duplicating another rail destination. Fixed side widths yield before the center stage does: do not compress the device preview into a thumbnail or hide verification behind a transient overlay.

**The Center-of-Work Rule.** The running app occupies the horizontal center and starts directly beneath the stage toolbar; agent activity and evidence flank it in the same viewport.

**The Decision-Boundary Rule.** Changed-file count, discard, review, and apply stay in the persistent bottom bar so the transition from work to acceptance is always visible.

### Apps/Docs Web Surface

`Apps/Docs` uses the approved composition B: a vertical proof ledger whose connected trail carries readers through installation, instrumentation, export, and verified execution. It extends the luminous studio into a light-only web surface with a cool-gray canvas, opaque white working surfaces, native blue reserved for agency, compact system typography, a narrow prose measure, and primary touch targets of at least 44px. The proof trail remains connected and readable responsively as secondary navigation condenses.

Agent-facing access is stable at `/agent-skill`, `/llms.txt`, `/llms-full.txt`, and each page's `.mdx` route. SDK documentation must reflect repository truth; never invent release URLs or package behavior that the repository does not establish.

## Elevation & Depth

The system is softly layered, not flat and not theatrical. White panels separate from the cool canvas with low-opacity ambient shadows; hairline dividers carry most internal structure. Toolbar controls use the shallowest lift, primary panels use a broad quiet lift, floating palettes use a slightly stronger compact shadow, and the phone hardware alone receives pronounced depth. There are no gradients, translucent glass layers, or shadow stacks.

### Shadow Vocabulary

- **Control Lift** (`0 2px 5px rgba(0, 0, 0, 0.035)`): Toolbar selectors and compact raised controls.
- **Panel Lift** (`0 7px 16px rgba(0, 0, 0, 0.035–0.045)`): Agent, App, Verify, Evidence, and grouped Settings surfaces.
- **Floating Tool Lift** (`0 5px 12px rgba(0, 0, 0, 0.055–0.07)`): Appearance controls and the disabled interaction palette.
- **Device Lift** (`0 9px 18px rgba(0, 0, 0, 0.22)`): The iPhone shell only, reinforcing that the running product is the object under inspection.

### Named Rules

**The Quiet Layering Rule.** Use tonal contrast and separators first; add one ambient shadow only when a surface must lift from the canvas.

**The Device Gets the Weight Rule.** The strongest shadow belongs to the app under test, never to surrounding dashboards or calls to action.

## Shapes

Continuous rounded rectangles define the form language. Structural panels use a calm 14pt radius; standard toolbar and primary-action controls use 8pt; compact selections use 9pt; the prompt uses 10pt; grouped Settings containers use 12pt. Capsules are reserved for segmented appearance choices and compact status badges. The phone shell's 52pt outer, 47pt inner, and 43pt screenshot radii are hardware geometry, not reusable application corners.

Borders are rare. Use single-pixel separators inside grouped lists and a subtle highlight stroke around the device screen; do not outline every panel or row. Rectangular layout regions stay optically aligned even when their surfaces have rounded corners.

**The Fourteen-Point Structure Rule.** Use 14pt continuous corners for the primary studio panels and floating tool palette; smaller controls step down instead of inheriting the structural radius.

**The Capsule Is a State Rule.** Capsule geometry signals a compact status or segmented choice, never a generic container or large action.

## Components

### Buttons

- **Shape:** Continuous 8pt corners for primary Run, Review, and Apply controls; native bordered styling for secondary actions.
- **Primary:** Workbench Blue with white semibold text, 44pt decision-bar height, and a split affordance when a related menu is available.
- **Hover / Focus:** Retain native macOS pointer, focus-ring, disabled, and menu behavior. Disabled primary buttons lower blue opacity rather than changing semantic role.
- **Secondary / Ghost:** Native bordered buttons carry reversible secondary actions; plain icon buttons use blue only when enabled or selected.

### Chips

- **Style:** Compact capsules with a low-opacity semantic fill, matching semantic text, and a 24pt height.
- **State:** Use for task status and appearance selection. A dot or SF Symbol accompanies text so state is never color-only.

### Cards / Containers

- **Corner Style:** Calm continuous structural corners (14pt), with 12pt for Settings groups.
- **Background:** Opaque Working White on Studio Canvas.
- **Shadow Strategy:** One ambient Panel Lift; internal rows rely on Hairline Separators.
- **Border:** None around the outer panel; one-pixel semantic separators between rows and zones.
- **Internal Padding:** 20–22pt for major content, 16–20pt for compact groups.

### Inputs / Fields

- **Style:** Borderless Raised Control fill, 10pt continuous corners, 44pt minimum height, and 12pt horizontal inset.
- **Focus:** Use the native macOS text focus behavior and Workbench Blue tint.
- **Error / Disabled:** Disable send when the task is empty or isolation is unavailable; explain the blocking condition in adjacent copy instead of coloring the field red.

### Navigation

- **Style:** An 88pt persistent rail with 68 × 66pt item hit areas. Each item combines an SF Symbol and a 10pt medium label.
- **Default:** Secondary Label icon and text on Working White.
- **Active:** Workbench Blue foreground with a 38 × 34pt Selection Mist icon well; the whole item's position and label remain stable.

### App Stage

The flexible center panel keeps an iPhone preview horizontally centered and top-weighted directly beneath the stage toolbar against Studio Canvas. Its maximum is 306 × 650pt at the reference viewport; at shorter window heights it scales proportionally down to preserve the 68pt top toolbar, 76pt review bar, appearance control, and device aspect ratio. At the 1512 × 884pt MacBook 14-inch viewport the phone is approximately 264 × 560pt. A small floating capsule below owns appearance and orientation. The interaction palette sits adjacent to the device and remains visibly disabled while the compatibility gate is closed. Evidence rows scroll inside their own ledger when vertical space is constrained rather than enlarging the window.

### Verification Ledger

Verification is a grouped list, not a celebratory scorecard. A 42pt summary glyph leads the current generation status, followed by 70pt rows for Build, Launch, UI interaction, and Screenshot. Every row includes text status and detail; fresh, failed, waiting, blocked, and stale states remain distinguishable without relying on color alone.

### Review Bar

The fixed 76pt bottom bar carries changed-file count at left and the reversible decision pair at right. Review Changes becomes Apply Changes only after a baseline-relative change set exists; Discard Task remains secondary and disabled when no isolated worktree exists.

## Do's and Don'ts

### Do:

- **Do** keep the running iOS app centered while agent intent and verification remain visible beside it.
- **Do** preserve the 88pt rail, 380pt Agent panel, flexible app stage, 420pt Verify panel, 12pt work-area gaps, and 76pt review bar in the primary desktop viewport; scale the device preview before sacrificing the structural bars.
- **Do** use native SwiftUI controls, AppKit semantic label colors, SF Symbols, native menus, focus behavior, and accessibility labels.
- **Do** tie verification presentation to the current mutation generation and label stale, waiting, blocked, failed, and fresh states in text.
- **Do** reserve green for machine-recorded success and blue for selection, action, and active work.
- **Do** keep advanced toolchain details available in secondary workspaces and status copy rather than crowding the primary operating path.

### Don't:

- **Don't** revive the blueprint-blue selected workspace, graphite chrome, dark IDE framing, or segmented top-level dashboard from the superseded direction.
- **Don't** turn agent prose, an idle-ready state, or an available integration into green success.
- **Don't** hide verification behind a tab, modal, or drawer while the agent is working.
- **Don't** embed or imitate Simulator chrome as if it were live control; keep the adjacent device preview and explicit Open in Simulator action truthful.
- **Don't** use gradients, glass effects, decorative texture, floating-card grids, or multiple competing shadows.
- **Don't** replace grouped native lists with oversized cards, or use pill geometry for ordinary buttons and containers.
