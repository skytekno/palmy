# Palmy — coverage inventory

Audit date: 26 September 2026, Asia/Jakarta. Source: authenticated [Seruma](https://seruma.app/) Chrome session. 163 scenario rows; 160 in scope. Counts represent the finite inventory below, not all possible behavior.

| Status | Rows |
|---|---:|
| BLOCKED | 16 |
| EXCLUDED | 3 |
| FAIL | 6 |
| INSPECTED | 41 |
| NOT_RUN | 7 |
| PASS | 90 |

PASS means the stated check produced the observed result; it does not certify every branch of the feature. FAIL includes confirmed defects and clearly labeled product gaps. INSPECTED means the UI was reviewed without full execution. BLOCKED names an environmental, authorization, or unavailable-test-context boundary. NOT_RUN is an explicit execution gap. EXCLUDED follows the user's scope.

See [coverage.csv](coverage.csv) for the full traceable inventory and [QA report](QA-report.md) for findings, retained fixtures, and remaining gates.
