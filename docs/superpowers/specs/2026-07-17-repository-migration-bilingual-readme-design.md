# Repository Migration and Bilingual README Design

## Goal

Move CC FLOW's user-facing repository, feedback, release-update, and project documentation links to `kilig947-alt/cc-flow`, then document the newly added productivity features in complete Chinese and English READMEs.

## Repository and Update Links

- Keep Sparkle as the in-app update mechanism.
- Configure release builds to use `https://github.com/kilig947-alt/cc-flow/releases/latest/download/appcast.xml`.
- Make the Settings GitHub action open `https://github.com/kilig947-alt/cc-flow`.
- Update current support and privacy-policy Issue links to the new repository.
- Update project-owned clone, release, badge, image, and documentation links when they still reference the previous repository.
- Do not rewrite third-party acknowledgements, historical references, or independently owned repositories such as a Homebrew tap unless they incorrectly identify the CC FLOW source repository.

## README Structure

- Keep `README.md` as the Simplified Chinese primary document.
- Add `README.en.md` as a complete English counterpart.
- Add a language switch at the top of both files.
- Keep both documents structurally aligned so installation, permissions, privacy boundaries, and feature coverage do not diverge.

## Feature Documentation

Both languages will describe:

- independently enabled, selected, and ordered Flow Island left features;
- File Watch, including authorized-folder-only search and File Card metadata boundaries;
- Downloads and Documents default authorization prompts;
- download monitoring and browser resource capture for Chrome, Edge, and Safari;
- browser pairing launchers, heartbeat-backed connection status, and proactive download/resource notifications;
- macOS Mail local signals and verification-code assistance;
- calendar, holidays, overdue/today reminders, completion, and repeated reminder behavior;
- GitHub authentication with `gh` and Personal Access Token fallback, responsive contributions, and repository links;
- AI HOT, productivity connections, permission/data-source controls, and user-confirmed file organization actions.

## Safety and Compatibility

- README text must state that File Watch only searches authorized directories and indexed metadata fields.
- File organization suggestions never execute without user confirmation.
- Browser pairing tokens remain local and are copied for explicit user entry into extension settings.
- Mail and reminders use local macOS permissions and APIs.
- Existing release signing and Sparkle verification behavior remains unchanged apart from the feed repository.

## Validation

- Scan tracked user-facing files for stale `ccsonicc333/trae-flow` links and review every remaining match.
- Validate Markdown links and language-switch targets locally.
- Validate browser-extension manifests and shared JavaScript.
- Run the focused productivity tests and an unsigned Debug build/test slice.
- Review the final diff for secrets, unrelated generated output, and repository-link mistakes before committing and pushing `main` to the configured `fork` remote.
