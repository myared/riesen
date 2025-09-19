# Repository Guidelines

## Project Structure & Module Organization
- Rails app. Key dirs: `app/models`, `app/controllers`, `app/views`, `app/jobs`, `app/assets`, `app/javascript` (Stimulus controllers), `config/`, `db/migrate/`, `test/`.
- Seeds live in `db/seeds.rb` and `db/seeds/*.rb`. Deployment/config: `.kamal/`, `Dockerfile`, `Procfile`, `railway.json`.
- Service objects in `app/services/`. Initializers in `config/initializers/`.

## Build, Test, and Development Commands
- Setup: `bin/setup` (installs gems, creates DB). If needed: `bundle install`.
- Run app (dev): `bin/dev` (Rails + assets) or `bin/rails s`.
- DB tasks: `bin/rails db:setup`, `bin/rails db:migrate`, `bin/rails db:seed`.
- Tests: `bin/rails test` or `bin/rails test test/models/patient_test.rb`.
- Lint: `bin/rubocop`. Security scan: `bin/brakeman`.

## Coding Style & Naming Conventions
- Ruby: 2‑space indentation, no tabs. Follow RuboCop (`.rubocop.yml`).
- Naming: Classes `CamelCase`, methods/vars `snake_case`. Rails files mirror class/module names (e.g., `app/models/patient.rb → Patient`).
- Views: ERB with partials prefixed `_` (e.g., `app/views/dashboard/_floor_view.html.erb`).
- JS: Stimulus controllers in `app/javascript/controllers/*_controller.js`; register in `index.js`.

## Testing Guidelines
- Framework: Minitest. Tests under `test/` with `*_test.rb` naming.
- Use fixtures in `test/fixtures/` for models like `patients.yml`, `rooms.yml`.
- Keep tests isolated/deterministic; prefer fast unit tests. Ensure CI (`.github/workflows/ci.yml`) passes.

## Commit & Pull Request Guidelines
- Commits: Imperative present tense (“Add…”, “Fix…”), concise subject, include context in body. Reference issues (`#123`) when applicable.
- PRs: Provide a clear summary, rationale, and testing notes. Include screenshots for UI changes. Call out DB migrations and any config changes.

## Security & Configuration Tips
- Do not commit secrets. Use Rails credentials (`config/credentials.yml.enc`) and env vars. `.kamal/secrets` handles deploy secrets.
- Respect Content Security Policy (`config/initializers/content_security_policy.rb`).

## Agent‑Specific Notes
- Keep changes minimal and aligned with Rails conventions; avoid renaming files unless required.
- Run `bin/rubocop` and `bin/rails test` before proposing a PR. Document any migration or seed updates.


- don't commit changes without me seeing the changes first
