# Interface Localization

## Purpose

Localizes all user-facing interface strings (menu items, settings, alerts) into 16 languages, with English as the guaranteed fallback. The interface language follows the system locale by default but can be forced independently by the user.

## Requirements

### Requirement: Localize UI strings from an in-app catalog
The system SHALL resolve every user-facing string through a typed localization catalog covering 16 languages.

#### Scenario: Supported system language
- **WHEN** a UI string is requested and the current interface language has a translation for it
- **THEN** the translated string for that language is returned

### Requirement: Fall back to English for missing translations
When a string key has no translation in the current interface language, the system SHALL return the English string; when the key is absent from the English catalog as well, the system SHALL return the raw key.

#### Scenario: Key missing in current language
- **WHEN** a string key exists in English but not in the current interface language
- **THEN** the English string is returned

#### Scenario: Key missing everywhere
- **WHEN** a string key exists in no catalog
- **THEN** the raw key itself is returned

### Requirement: Resolve interface language from override or system locale
The system SHALL use a user-forced interface language when one is set, and otherwise SHALL derive the interface language from the system's preferred languages.

#### Scenario: User forces a language
- **WHEN** an interface-language override is stored in settings
- **THEN** that language is used regardless of the system locale

#### Scenario: No override set
- **WHEN** no interface-language override is stored
- **THEN** the language is derived from the system's preferred-languages list

### Requirement: Re-localize UI on language change
When the interface language changes, the system SHALL rebuild localized UI surfaces (such as the status-bar menu) so they reflect the new language without requiring an app restart.

#### Scenario: Language switched in settings
- **WHEN** the user selects a different interface language
- **THEN** the status-bar menu is rebuilt with strings in the new language
