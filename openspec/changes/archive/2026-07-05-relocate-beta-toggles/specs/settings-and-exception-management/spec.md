## ADDED Requirements

### Requirement: Auto-fix master toggle without a beta badge
The Auto-fix tab's master toggle ("Fix layout automatically as I type") SHALL be presented without a beta badge. Toggling it SHALL persist the automatic-conversion preference exactly as before.

#### Scenario: Master toggle shows no beta badge
- **WHEN** the user opens Settings ▸ Auto-fix
- **THEN** the "Fix layout automatically as I type" row SHALL display its title and description without a "BETA" badge
- **AND** toggling the switch SHALL persist the automatic-conversion preference and start/stop auto-conversion exactly as it did before

### Requirement: Experimental toggles live at the top of the Advanced tab
The "Show layout flag at the cursor" toggle and the "Remote Desktop mode" toggle SHALL be presented at the top of the Advanced tab, above the debug-logging controls, and SHALL NOT appear in the Auto-fix tab. Each SHALL keep its beta labeling, its persisted preference key, and its behavior. The remote-desktop toggle SHALL continue to appear only when its beta flag is enabled.

#### Scenario: Advanced tab shows the relocated toggles first
- **WHEN** the user opens Settings ▸ Advanced
- **THEN** the "Show layout flag at the cursor" toggle (with its BETA badge) SHALL appear at the top, followed by the "Remote Desktop mode (beta)" toggle when its beta flag is enabled, above the debug-logging toggle, path, and reveal button
- **AND** toggling either control SHALL persist and apply exactly as before

#### Scenario: Auto-fix tab no longer shows the experimental toggles
- **WHEN** the user opens Settings ▸ Auto-fix
- **THEN** the tab SHALL show only the master toggle and the unified exceptions list
- **AND** neither the caret-flag toggle nor the remote-desktop toggle SHALL appear on the Auto-fix tab

#### Scenario: Remote-desktop toggle stays gated
- **WHEN** the remote-desktop beta flag is not enabled
- **THEN** the Advanced tab SHALL NOT show the "Remote Desktop mode" toggle, while still showing the caret-flag and debug-logging controls
