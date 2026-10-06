# Persian (fa-IR) prompt pack

Installed to `/var/lib/asterisk/sounds/<prompt_root>/` (default `custom/ccbs/fa/`). In the dialplan the names omit `.wav`.

| File | Purpose | Suggested Persian script |
|---|---|---|
| `busy.wav` | Busy announcement | «داخلی مورد نظر شما در حال مکالمه است.» |
| `offer.wav` | Consent / DTMF 1 | «چنانچه مایل هستید پس از آزاد شدن داخلی، تماس با شما برقرار شود، عدد یک را فشار دهید.» |
| `accepted.wav` | Request accepted | «درخواست تماس مجدد شما ثبت شد. پس از آزاد شدن داخلی، با شما تماس گرفته خواهد شد.» |
| `cancelled.wav` | No consent | «درخواست تماس مجدد ثبت نشد.» |
| `failed.wav` | CCSS failure | «امکان ثبت درخواست تماس مجدد وجود ندارد. لطفاً بعداً دوباره تلاش کنید.» |

## Recording guidance
Dry, mono, no long silence. Target: WAV PCM 16-bit 8 kHz mono. Keep `busy` + `offer` short: `offer_timer` (default 30 s) must be longer than both prompts plus `input_timeout`; the installer warns otherwise.

## Replacing prompts
```bash
sudo bash scripts/normalize-prompts.sh /path/to/my-prompts /tmp/ccbs-prompts   # needs SoX
sudo cp /tmp/ccbs-prompts/*.wav /var/lib/asterisk/sounds/custom/ccbs/fa/
sudo chown asterisk:asterisk /var/lib/asterisk/sounds/custom/ccbs/fa/*.wav
sudo chmod 0644 /var/lib/asterisk/sounds/custom/ccbs/fa/*.wav
issabel-ccbs-check
```
For another language set e.g. `prompt_root=custom/ccbs/en` in `/etc/asterisk/issabel-ccbs.conf`, run `install.sh` (it creates the directory), then overwrite the five files in it with your recordings.
