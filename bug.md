## 2026-05-17 — ShadTheme batch corruption (FIXED in 78c6cce)

### Root cause
The Python batch script used `read_file` → replace → `write_file` to do 307 ShadColors replacements.
`read_file` returns content with `NNN|` line-number prefixes embedded. `write_file` wrote those
prefixes back into the actual .dart files, causing every line to start with `1|1|`, `    1039|`, etc.
Dart compiler saw random numbers and `|` operators where code was expected → 300+ errors.

### Fix
1. `git checkout 768fb2c~1 -- lib/` — revert to clean state before batch corruption
2. `sed` to strip all embedded line-number prefixes from 15 files
3. `sed` to re-apply ShadColors → ShadTheme.of(context) replacements (no write_file)
4. `sed` to remove `const` from 96+ lines containing ShadTheme.of(context)
5. Fixed app.dart _buildTheme back to ShadColors (not ShadTheme) since it has isDark parameter

### Result
- 14 widget/screen files: all ShadColors → ShadTheme.of(context)
- app.dart: ShadTheme class + _buildTheme with ShadColors (correct, no circular ref)
- Zero const issues
- Zero embedded line-number prefixes
