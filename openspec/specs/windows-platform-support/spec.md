# Windows Platform Support

## Purpose

The system SHALL, on Windows, reproduce Switcher3way's N-way wrong-layout detection and correction behavior across English, Ukrainian, and Russian — observing keystrokes, rendering them through every installed layout, validating against bundled offline dictionaries, and switching/rewriting only on a single unambiguous winner — while adapting to Windows-specific input, layout, and distribution mechanisms. Implemented and shipping: a WinUI 3 application distributed as a direct-download MSI and submitted to the Microsoft Store. Where a requirement here is not yet met — notifications, for instance — the gap is recorded in the archived change that introduced it.
## Requirements
### Requirement: Observe keystrokes and buffer words globally
The Windows build SHALL observe keystrokes system-wide without requiring focus in the app, and SHALL buffer the current word and detect word boundaries so that finished words can be evaluated, mirroring the macOS keystroke buffer. The buffer SHALL retain punctuation and digit keys that produce letters in another installed layout as part of the token, and SHALL ignore the application's own synthesized keystrokes so a rewrite does not corrupt the buffer.

#### Scenario: Buffer a word up to a boundary
- **WHEN** the user types letters followed by a space or other word-boundary key in any foreground application
- **THEN** the system SHALL record the ordered keystrokes of the completed word and mark that a boundary occurred

#### Scenario: Reset the buffer on unsafe cursor movement
- **WHEN** the user moves the caret with arrows, clicks the mouse, or switches applications
- **THEN** the system SHALL discard the current keystroke buffer so a later rewrite cannot delete unrelated text

#### Scenario: Keep punctuation keys that are letters in another layout
- **WHEN** the user types a key that is punctuation in the current layout but a letter in another installed layout (for example the `,` key, which is `б` on a Ukrainian/Russian layout)
- **THEN** the system SHALL keep that key in the current word's buffer rather than treating it as a word boundary or reset

#### Scenario: Ignore the app's own synthesized input
- **WHEN** the application synthesizes keystrokes to rewrite text (backspaces and Unicode characters)
- **THEN** the system SHALL not let those synthesized events alter the keystroke buffer

### Requirement: Enumerate installed layouts and their languages
The Windows build SHALL enumerate the installed keyboard layouts and determine each layout's language so that conversion decisions can be made against the available layouts.

#### Scenario: Resolve available layouts at runtime
- **WHEN** the system needs to evaluate or switch layouts
- **THEN** the system SHALL inspect the currently installed keyboard layouts and their language identifiers

#### Scenario: Ignore layouts without a usable language
- **WHEN** an installed layout does not map to a language usable for validation
- **THEN** the system SHALL exclude that layout from language-based detection

### Requirement: Render buffered keystrokes through each candidate layout
The Windows build SHALL render the buffered keystrokes into text as each candidate layout would produce it, so the input can be validated in every layout's language.

#### Scenario: Produce per-layout renderings
- **WHEN** the system evaluates a completed word against the installed layouts
- **THEN** the system SHALL produce, for each candidate layout, the character string those keystrokes would yield in that layout

#### Scenario: Preserve dead-key and live-typing state
- **WHEN** the system renders keystrokes through a layout that uses dead keys
- **THEN** the rendering SHALL NOT corrupt the user's in-progress keyboard state or subsequent keystrokes

### Requirement: Validate words offline against bundled dictionaries
The Windows build SHALL validate candidate words against dictionaries bundled with the application, without a network connection and without depending on optional operating-system language features.

#### Scenario: Validate without installed OS language packs
- **WHEN** the target language's operating-system spellcheck feature is not installed
- **THEN** the system SHALL still validate words for that language using the bundled dictionaries

### Requirement: Preserve N-way precision-first detection semantics
The Windows build SHALL reproduce the application's N-way detection behavior: validate the word's
letter core, convert when the input is valid in exactly one alternative language, re-render the whole
token (including punctuation keys) in the target layout, and apply the same short-word and code-like
safety gates. When the input is valid in **more than one** alternative language (uk↔ru ambiguity),
the Windows build SHALL resolve it to the *preferred ambiguity language* — the phrase's locked
language if the current phrase is locked, otherwise the configured preference — rather than leaving
it unchanged, unless the preference is "do not convert". Input already valid in the current language
SHALL be left unchanged. The Windows build SHALL track the words typed since the last hard reset as a
phrase and, when a later word is valid in exactly one language, re-convert earlier words that were
defaulted to a *different* language in a single replacement together with that word; a phrase locked
to a conflicting language SHALL NOT be re-converted (precision-first).

#### Scenario: Switch to a single unambiguous winner
- **WHEN** the buffered word's letter core is valid in exactly one alternative language and passes the safety gates
- **THEN** the system SHALL switch to that language's layout and rewrite the word in it

#### Scenario: Resolve an ambiguous word to the preferred language
- **WHEN** the word's letter core is valid in more than one language, the preference is a language (not "do not convert"), and no phrase lock overrides it
- **THEN** the system SHALL convert the word to the preferred language's layout and mark it internally as a defaulted conversion

#### Scenario: Preference "do not convert" leaves ambiguous input unchanged
- **WHEN** the word is ambiguous and the ambiguity preference is "do not convert"
- **THEN** the system SHALL leave the text and layout unchanged

#### Scenario: Phrase self-corrects when disambiguated later
- **WHEN** the phrase contains words defaulted to one language and the user then types a word valid only in another language in the wrong layout, with no conflicting lock
- **THEN** the system SHALL replace the segment from the first defaulted word through the current word so all of them render in the newly established language, and SHALL switch to that layout

#### Scenario: Contradictory phrase is left untouched
- **WHEN** the phrase already contains a word valid only in one language and the user then types a word valid only in a conflicting language
- **THEN** the system SHALL convert only the current word per the single-word rule and SHALL NOT re-convert earlier words

#### Scenario: Convert words with attached punctuation
- **WHEN** a convertible word carries leading or trailing punctuation
- **THEN** the system SHALL validate only the letter core and rewrite the whole token — punctuation included — in the target layout

### Requirement: Switch the foreground application's layout
The Windows build SHALL change the active keyboard layout of the foreground application,
accounting for the per-thread nature of the Windows input language, and SHALL confirm the
change took effect rather than assuming a single switch mechanism always succeeds.

#### Scenario: Change the layout of the active window
- **WHEN** the system decides to convert a word to another language
- **THEN** the system SHALL activate the corresponding layout for the foreground application so continued typing uses that layout

#### Scenario: Confirm the switch and fall back when it does not take effect
- **WHEN** the system requests a foreground-layout change through its primary mechanism
- **THEN** the system SHALL determine whether the active layout actually changed, and SHALL attempt an alternative switch mechanism when the primary request did not take effect

### Requirement: Rewrite typed text in place
The Windows build SHALL replace the mistyped word with its converted form by erasing the original
characters and inserting the corrected Unicode text, with a clipboard-based fallback for selected
text. When a real (user-originated, non-synthetic) keystroke is detected while a replacement is in
progress, the Windows build SHALL abort the replacement, restore any characters it has already
erased, and record no conversion — so that neither a single-word rewrite nor a multi-word phrase
correction can leave the on-screen text partially deleted.

The Windows build SHALL inject the erase and insert streams at a rate the target application can
consume. Above a threshold length it SHALL insert the replacement as a single clipboard paste rather
than as one event per character, because per-character injection of long text is both slow and the form
the target mis-renders. Where it borrows the clipboard it SHALL restore the previous text afterwards,
and only once the paste has been observed on screen.

The Windows build SHALL NOT report a replacement as successful on the strength of the input events
having been accepted. It SHALL compare the text that landed against the text it intended to produce,
and where they differ it SHALL report the replacement as failed, restore the text to its pre-rewrite
state where it can, and record the intended and landed text so the discrepancy is diagnosable.

Where the landed text cannot be read at all, the Windows build SHALL record the replacement as
unverified and SHALL treat it as applied: it SHALL NOT repair the text, SHALL NOT present a failure to
the user, and SHALL allow a cycle to continue. An unreadable target is an absence of evidence, not
evidence of failure — several applications, including Chromium-based ones, expose no readable text
until an accessibility client has asked once, and treating that as a fault would put an error in front
of conversions that demonstrably worked.

#### Scenario: Rewrite a buffered word
- **WHEN** a conversion is applied to a buffered word
- **THEN** the system SHALL erase the original characters and insert the converted text, preserving any trailing spaces

#### Scenario: Abort and restore on concurrent typing
- **WHEN** the user types a real key while a single-word or multi-word segment replacement is being injected
- **THEN** the system SHALL stop injecting, restore the characters it already erased, leave the layout unchanged, and treat the conversion as not having happened

#### Scenario: Surface protected targets rather than failing silently
- **WHEN** the foreground window cannot receive synthesized input because it runs at a higher integrity level
- **THEN** the system SHALL NOT report a successful conversion and SHALL make the limitation observable

#### Scenario: A replacement that lands mangled is not a success
- **WHEN** every injected event is accepted but the text that lands differs from the text the replacement intended
- **THEN** the system SHALL report the replacement as failed, SHALL NOT show feedback claiming a conversion, and SHALL record both the intended and the landed text

#### Scenario: A large replacement is not corrupted by its own injection rate
- **WHEN** a replacement erases and reinserts a selection of at least fifty characters
- **THEN** the text that lands SHALL match the text intended, character for character

#### Scenario: A long replacement borrows the clipboard and gives it back
- **WHEN** a replacement longer than the paste threshold is applied while the user has text on the clipboard
- **THEN** the replacement SHALL be inserted as one paste, and the user's previous clipboard text SHALL be on the clipboard again afterwards

#### Scenario: A short replacement leaves the clipboard alone
- **WHEN** a replacement at or below the paste threshold is applied
- **THEN** it SHALL be typed rather than pasted, and the clipboard SHALL NOT be touched

#### Scenario: A replacement across a change of script is not corrupted
- **WHEN** a replacement switches the layout from one script to another immediately before inserting its characters
- **THEN** the text that lands SHALL match the text intended, character for character

#### Scenario: An unreadable result is recorded, not treated as a failure
- **WHEN** the target application exposes no way to read back the text that landed
- **THEN** the system SHALL record the replacement as unverified, SHALL NOT repair the text, SHALL NOT show the user a failure, and SHALL allow a cycle to continue from it

### Requirement: Provide manual conversion and undo
The Windows build SHALL let the user convert the last word or selection on demand via a configurable
trigger, cycle through candidate layouts on repeated invocations, and restore the original text and
pre-conversion layout when the cycle completes. When the word is ambiguous, the first candidate
offered SHALL be the preferred ambiguity language (when it is one of the candidates), so a single
trigger invocation yields the same result automatic conversion would. The same trigger SHALL also
cancel an automatic conversion: an auto-fix seeds a single-candidate cycle whose candidate is
already on screen, so the first trigger invocation after it restores the original text and layout.

A cycle SHALL NOT continue from text the build has established is wrong. When a step of the cycle is
reported as failed, the Windows build SHALL end the cycle rather than advance it, so that a corrupted
result is never used as the input to a further conversion. A step that merely could not be read back
SHALL NOT end the cycle.

#### Scenario: Convert on explicit trigger
- **WHEN** the user invokes the manual trigger after typing a word
- **THEN** the system SHALL convert the word to the best candidate layout even if automatic detection would have left it unchanged

#### Scenario: Ambiguous word offers the preferred language first
- **WHEN** the user invokes the manual trigger on a word valid in more than one language and the preference names one of them
- **THEN** the first candidate applied SHALL be the preferred ambiguity language

#### Scenario: Cycle and restore
- **WHEN** the user repeatedly invokes the trigger with no typing in between
- **THEN** the system SHALL advance through the remaining candidate layouts and, after the last one, restore the original text and the layout active before the first conversion

#### Scenario: Cancel an automatic conversion with the trigger
- **WHEN** the user invokes the trigger immediately after an automatic conversion, with no typing in between
- **THEN** the system SHALL restore the original text and the layout that was active before the automatic conversion

#### Scenario: A failed step ends the cycle instead of compounding
- **WHEN** a step of the cycle is reported as failed
- **THEN** the system SHALL end the cycle, and a subsequent trigger invocation SHALL start afresh from what is on screen rather than continue from the failed step's assumptions

#### Scenario: An unverified step does not interrupt cycling
- **WHEN** a step of the cycle lands in a target whose text cannot be read back
- **THEN** the system SHALL continue the cycle on the next trigger invocation, so that cycling works in applications that expose no readable text

### Requirement: Apply exclusion and exception policy
The Windows build SHALL suppress automatic conversion in excluded applications and secure input contexts, and SHALL honor user-configured never-convert and always-convert word lists.

#### Scenario: Skip an excluded application
- **WHEN** the foreground application matches the denied-apps list or is a credential/password context
- **THEN** the system SHALL not perform automatic conversion in that context

#### Scenario: Honor word exception lists
- **WHEN** the typed or converted word matches a configured never-convert or always-convert rule
- **THEN** the system SHALL respectively prevent or force the conversion for that word

### Requirement: Present a tray-based status and control surface
The Windows build SHALL provide a system-tray presence whose flyout shows a live status header — the
foreground window's current layout and whether conversion is on or paused — and offers the core
controls: enable/disable, auto-fix toggle, remember-layout-per-app toggle, pause with selectable
durations, open Settings, open Help, and check for updates. The check-for-updates control SHALL show a
busy state while a check runs. Debug logging and opening the log folder SHALL NOT appear in the tray;
they live in the Settings window's Advanced section. The tray icon itself SHALL continue to indicate
the current layout and a dimmed/paused state.

#### Scenario: Show status and toggles in the tray
- **WHEN** the user opens the tray icon's flyout
- **THEN** the system SHALL display the current layout and enabled/paused state and provide controls to toggle conversion, toggle auto-fix, pause it for a chosen duration, and open Settings and Help

#### Scenario: Diagnostics controls are not in the tray
- **WHEN** the user opens the tray flyout
- **THEN** neither "Debug logging" nor "Open log folder" SHALL appear there — both are reached from Settings → Advanced

#### Scenario: Update check reflects progress
- **WHEN** an update check is running
- **THEN** the check-for-updates control SHALL show a busy/disabled state until it completes

### Requirement: Distribute as a signed, offline application
The Windows build SHALL be distributed through the Microsoft Store as a packaged application signed
by the Store, and MAY additionally be offered as a direct-download installer. It SHALL operate
entirely offline for detection, validation and conversion. A packaged build SHALL NOT update itself —
the Store services updates — and SHALL register "start with Windows" through its package startup task
rather than a startup-folder shortcut. A direct-download build MAY check for and install updates
itself, and SHALL state plainly what is missing if a runtime it depends on is absent, rather than
failing silently. A packaged build SHALL carry every runtime it needs that its manifest cannot declare
as a dependency, so that installing it from the Store is sufficient to run it.

#### Scenario: Store distribution is signed without a developer certificate
- **WHEN** the app is submitted to the Microsoft Store
- **THEN** the Store SHALL sign the package, so installing it shows no "unknown publisher" warning

#### Scenario: Packaged builds defer updates to the Store
- **WHEN** an update check runs in a packaged build
- **THEN** the app SHALL NOT download or install an update itself, and SHALL indicate that updates come from the Store

#### Scenario: Start with Windows in a packaged build
- **WHEN** the user enables "start with Windows" in a packaged build
- **THEN** the app SHALL enable its package startup task, which stays visible in Windows' startup-apps settings

#### Scenario: A missing runtime is explained
- **WHEN** a direct-download build starts on a PC without the Windows App Runtime it depends on
- **THEN** the app SHALL name the required runtime instead of exiting with no message

#### Scenario: No runtime network dependency
- **WHEN** the application performs detection, validation, or conversion
- **THEN** it SHALL do so without any network access

#### Scenario: A packaged build needs no prerequisite
- **WHEN** a packaged build is installed from the Store onto a PC with no .NET runtime installed
- **THEN** the application SHALL start and function, because the package carries the runtime

#### Scenario: An installed build can open its windows
- **WHEN** any shipped installer or package is installed and the user opens Settings, Help or the
  welcome flow
- **THEN** the window SHALL appear — a build whose interface resources are missing SHALL NOT be
  publishable, and the build SHALL fail rather than produce one

### Requirement: Remain running with no window open
The application SHALL continue running when no window of its own is open, since its normal state is a
notification-area icon with no main window. Closing a window, or finishing the first-run flow, SHALL NOT
end the process; only an explicit Quit SHALL.

#### Scenario: Finishing first-run setup leaves the app running
- **WHEN** the user completes the welcome flow on a fresh install
- **THEN** the application SHALL remain running in the notification area

#### Scenario: Closing Settings does not quit
- **WHEN** the user closes the Settings window
- **THEN** the application SHALL remain running, and its tray icon SHALL stay available

### Requirement: Present the interface in the user's language
Every string the interface displays SHALL be resolved through the localization layer rather than
hard-coded, and SHALL follow the interface language the user has chosen. English, Ukrainian and Russian
— the languages the application converts between — SHALL be translated in full. Where a language is
incomplete the application SHALL fall back to English and SHALL identify that language as incomplete
where it is chosen, rather than presenting a partial translation as a complete one. Names of physical
keys MAY remain untranslated, since they label the keyboard.

#### Scenario: Choosing a fully translated language
- **WHEN** the user selects Ukrainian or Russian as the interface language
- **THEN** every string in Settings, the tray flyout and the welcome flow SHALL appear in that language,
  excluding names of physical keys and names Windows itself supplies

#### Scenario: Choosing an incomplete language
- **WHEN** the user opens the interface-language picker
- **THEN** languages that lack translations for some strings SHALL be identified as incomplete, and
  selecting one SHALL show English for the missing strings rather than blank or untranslated keys

#### Scenario: Language change does not clip the layout
- **WHEN** the interface language changes to one whose text is longer than English
- **THEN** the affected text SHALL remain fully readable — wrapped or given more room — rather than
  truncated

### Requirement: Apply settings changes immediately
The Windows build SHALL commit each settings change to persistent storage at the moment the control
changes, without a separate Save or Cancel step. Surfaces that share the settings (tray flyout, status
card, Settings window) SHALL reflect a change made in any one of them without needing to be reopened.
Closing the Settings window SHALL NOT discard or defer any change.

#### Scenario: A toggled setting persists immediately
- **WHEN** the user flips a setting in the Settings window
- **THEN** the system SHALL write it to storage right away, and the change SHALL survive closing the window without any Save action

#### Scenario: Change reflected across surfaces
- **WHEN** the user toggles conversion or auto-fix from the tray flyout while the Settings window is open
- **THEN** the Settings window SHALL show the new value without being reopened, and vice versa

#### Scenario: Interface language applies in place
- **WHEN** the user changes the interface language in Settings
- **THEN** the open window SHALL re-render in the new language without an app restart

### Requirement: Give feedback on a successful conversion
The Windows build SHALL indicate a successful automatic conversion with a transient, non-focus-stealing
indicator shown near the corrected text that presents the original keystrokes and the converted word
and how to undo the fix. The indicator SHALL disappear on its own, SHALL NOT block or steal focus from
typing, and SHALL NOT post a persistent entry to the notification centre. A conversion that changes
nothing SHALL NOT show it.

#### Scenario: Success shows a transient indicator
- **WHEN** an automatic conversion successfully rewrites a word
- **THEN** the system SHALL briefly show, near the caret, the original and converted forms and an undo hint, then dismiss it automatically

#### Scenario: Undo hint follows the configured trigger
- **WHEN** the feedback indicator is shown
- **THEN** the undo hint SHALL name the currently configured trigger (for example the double-tap key when that is selected)

#### Scenario: No indicator when nothing changed
- **WHEN** detection results in no rewrite (kept, or already correct)
- **THEN** the system SHALL NOT show the conversion indicator

### Requirement: Surface errors and prompts as actionable notifications
The Windows build SHALL present the "cannot change text in this window" case as an actionable system
notification that persists in the notification centre and explains the likely elevation cause, replacing
the transient balloon tip. Where the product offers to remember a word after a fix, the notification
SHALL provide actions to undo the fix and to add the word to the never-convert list. The system SHALL
NOT raise a notification for each successful conversion.

#### Scenario: Protected-target error is actionable and persistent
- **WHEN** the foreground window cannot receive synthesized input because it runs at higher integrity
- **THEN** the system SHALL raise a persistent notification stating it cannot change text there and that the app may need to run as administrator

#### Scenario: Remember-word action updates the never-convert list
- **WHEN** the user chooses "Never convert this" on a conversion prompt
- **THEN** the system SHALL add that word to the never-convert list

#### Scenario: Success does not spam the notification centre
- **WHEN** conversions succeed normally
- **THEN** the system SHALL NOT post a notification-centre entry per fix

### Requirement: Guide first-run setup
On first launch the Windows build SHALL show a one-time setup flow that introduces what the app does,
lists the detected keyboard layouts with each language's dictionary readiness, and lets the user choose
the trigger key with a live preview that runs the real detector on what they type. The flow SHALL offer
to start the app with Windows, SHALL require no operating-system permission grants, and SHALL persist a
completion flag so it does not appear on subsequent launches.

#### Scenario: Onboarding appears once
- **WHEN** the app launches and first-run setup has not been completed
- **THEN** the system SHALL show the setup flow, and SHALL NOT show it again after it is completed

#### Scenario: Detected layouts and readiness are shown
- **WHEN** the user reaches the layouts step
- **THEN** the system SHALL list the installed layouts and, for each, whether its dictionary is available

#### Scenario: Trigger preview runs the real detector
- **WHEN** the user types a wrong-layout word in the trigger step's try-it field
- **THEN** the system SHALL show the conversion the real detector would produce

### Requirement: Manage exception apps visually
The Windows build SHALL let users add excluded applications by selecting from currently running
applications or by supplying an executable file, rather than typing an executable name. Each listed app
SHALL be shown with its icon and friendly name alongside its executable file name. Protected apps (the
built-in password managers) SHALL be shown as locked and SHALL NOT be removable. The never-convert and
always-convert word lists SHALL remain editable in place.

#### Scenario: Add an app from the running-apps picker
- **WHEN** the user opens the add-app picker
- **THEN** the system SHALL list currently running apps (excluding already-listed ones) and add the selected ones to the excluded list

#### Scenario: Protected apps cannot be removed
- **WHEN** the user views a protected password-manager entry
- **THEN** it SHALL be shown as locked with no remove action

#### Scenario: Apps show icon and friendly name
- **WHEN** the excluded-apps list is shown
- **THEN** each row SHALL display the app's icon and friendly name in addition to its executable file name

### Requirement: Render release notes and help as formatted content
The Windows build SHALL render update release notes as formatted text (headings and bullet points) and
SHALL NOT display raw markup. The Help window SHALL present a navigable table of contents derived from
the user guide's sections plus an in-app language switch, and SHALL open external links in the default
browser.

#### Scenario: Release notes render formatted
- **WHEN** an update is offered with release notes
- **THEN** the notes SHALL be shown as headings and bullets, not as raw markup characters

#### Scenario: Help has a working table of contents
- **WHEN** the user opens Help and selects a section
- **THEN** the corresponding section of the guide SHALL be shown, and the in-app language switch SHALL change the guide language without leaving the window

