Caesium Portable - read-only trace audit v1.1

Place the PowerShell and CMD files next to your CaesiumPortable.exe. Run the CMD,
exercise Caesium, fully exit, and find the report ZIP in Data\Diagnostics.

IMPROVED: compares registry value contents privately, not only value names and
types. A random keyed fingerprint is kept only in memory for this run. No
registry values, hashes, or file contents are included in the report.

The report is limited to likely Caesium/Qt directories and keys. It does NOT
delete anything and does NOT establish ownership of pre-existing entries.
NEVER remove a shared QtProject key based on the report alone.
