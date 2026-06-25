# Workspace Rules for Khataman 2026

## 🔒 Security & Credentials Prevention
* **Never hardcode secrets**: Do not put any API keys, Supabase credentials (url, anon key, service role key), database passwords, or user credentials inside source code, test files, or configuration files.
* **Use Environment Variables**: Always load keys from environment variables (e.g., using `flutter_dotenv` via `.env` file).
* **Git Safety**: 
  * Ensure that the `.env` file and any temporary test/debug scripts (such as `test_*.dart`) are explicitly listed in `.gitignore`.
  * Never commit or push any file containing raw secrets to git tracking.
  * Always verify `git status` and git diffs before staging changes to prevent credential leakage.
