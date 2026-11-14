## MODIFIED Requirements

### Requirement: Display active layout as status icon
The system SHALL display an emoji flag in the menu bar representing the currently active keyboard layout, resolved from the layout's language code rather than from substrings of its identifier.

The status icon SHALL also distinguish the states in which the app is not correcting text, because its working state produces nothing on screen and is therefore indistinguishable from a broken one. Those states are: **paused or disabled** by the user, and **not working** because a required permission or the event tap has been lost. A deliberate choice and a fault SHALL NOT look the same.

#### Scenario: Layout with a known language code
- **WHEN** the active layout's language code maps to a flag
- **THEN** that flag is shown as the status-bar icon

#### Scenario: Paused or disabled by the user
- **WHEN** the user has paused or disabled the app
- **THEN** the status icon SHALL indicate that deliberate state alongside the layout flag

#### Scenario: Not working through a fault
- **WHEN** monitoring has stopped because a permission was revoked or the event tap cannot run
- **THEN** the status icon SHALL indicate a fault, distinguishably from the paused and disabled states

### Requirement: Conditional permissions menu item
The "Check Permissions…" item SHALL appear in the menu whenever a required permission is missing — whether it was never granted or has since been revoked — and SHALL open the onboarding checklist window. When a permission has been lost while the app was running, the menu SHALL additionally say plainly that the app has stopped working and name what is missing, rather than relying on the user noticing an item that is merely present.

#### Scenario: Permissions healthy
- **WHEN** both required permissions are granted
- **THEN** the menu SHALL NOT contain a permissions item

#### Scenario: Permissions broken
- **WHEN** a required permission is missing
- **THEN** the menu SHALL contain the permissions item and selecting it SHALL open the onboarding window

#### Scenario: Permission revoked while running
- **WHEN** a permission is withdrawn while the app is running
- **THEN** the menu SHALL state that the app has stopped correcting text and name the missing permission, in a form that is legible rather than a disabled grey label
