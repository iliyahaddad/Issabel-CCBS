# Test Plan (staging, two test extensions A=101, B=102, chan_sip)

| ID | Scenario | Expected |
|---|---|---|
| T01 | A calls free B | Normal call; no CC prompt |
| T02 | A calls busy B, presses 2 / nothing | Busy + offer prompt, then "cancelled"; Issabel's normal busy handling follows (busy tone or voicemail); `cc report status` empty |
| T03 | A calls busy B, presses 1 | "accepted" prompt, call ends; `cc report status` shows 1 request; AMI `UserEvent CCBSRequest` Result=SUCCESS |
| T04 | B becomes free | A's phone rings (within `cc_recall_timer`) |
| T05 | A answers recall | B rings, call completes, `ccbs-callback` visible in log |
| T06 | A ignores recall | CCBS ends after the recall timer |
| T07 | Request expires (`ccbs_available_timer`) | No later call is generated |
| T08 | External caller (trunk) reaches busy extension | No CCBS prompt, call is NOT answered; normal busy handling |
| T09 | B has voicemail-on-busy; A declines CCBS | Voicemail still works |
| T10 | `issabel-ccbs-ctl disable`, repeat T03 | No offer; behaviour as without CCBS. `enable` restores it |
| T11 | Press 1 while the global CC limit is exhausted | "failed" prompt, `CC_REQUEST_REASON` logged |
| T12 | Apply Changes in Issabel GUI | Hook and policies still present (`issabel-ccbs-check`) |
| T13 | `asterisk -rx 'core restart gracefully'` | Pending requests are gone (CCSS is in-memory); no stale calls |
| T14 | Re-run `install.sh` | No changes (idempotent), no duplicate blocks |
| T15 | `uninstall.sh` | Blocks, prompts and tools removed; user content in the config files untouched |

Automated (no PBX needed): `bash tests/static_test.sh && bash tests/install_test.sh`
