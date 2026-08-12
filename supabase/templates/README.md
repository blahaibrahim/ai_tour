# Auth email templates

Paste-ready bodies for the two emails the OTP signup flow sends. They are not
applied by any migration — Supabase keeps email templates in project config, not
in the database, so they have to be set in the dashboard:

**Authentication → Emails → Templates**

| Template in the dashboard | File | Subject |
| --- | --- | --- |
| Change email address | `otp_change_email.html` | `{{ .Token }} is your Massar code` |
| Confirm sign up | `otp_confirm_signup.html` | `{{ .Token }} is your Massar code` |
| Reset password | `otp_reset_password.html` | `{{ .Token }} is your Massar code` |

Paste the file contents into the **Message body** field and the subject line into
**Subject heading**, for all three.

The other three templates in that list — *Invite user*, *Magic link or OTP*,
*Reauthentication* — are not used by this app and should be left alone. **Magic
link or OTP** is the trap: its name suggests it serves the one-time codes, and
it does not. It backs `signInWithOtp`, which nothing here calls.

## Why all three

| Flow | Template | Called from |
| --- | --- | --- |
| Signing up (the normal case) | Change email address | `updateUser(email:)` — an *upgrade* of the anonymous session, so `auth.uid()` and everything keyed to it survive |
| Signing up with no session to upgrade | Confirm sign up | `signUp` — the fallback in `AuthBloc._onSignUp` when launch-time sign-in failed or the traveller had signed out |
| Forgotten password | Reset password | `resetPasswordForEmail` |

Setting only some of them leaves flows that silently send the wrong mail.

## `{{ .Token }}` is the point

Supabase's stock templates use `{{ .ConfirmationURL }}` — a magic link. The app
asks for a one-time code, so the body must contain `{{ .Token }}`. **Until these
are pasted in, `OtpVerificationScreen` will sit waiting for a code that was never
sent.**

## Code length

**Authentication → Sign In / Providers → Email → Email OTP Length** sets how many
digits `{{ .Token }}` contains — 6 to 10, and this project is on **6**.

Whatever it is set to, `otpCodeLength` in
`lib/screens/auth/otp_verification_screen.dart` has to match. The input stops
accepting characters at that count and submits itself there, so a value below the
real length makes it impossible to enter a valid code at all. The screen sizes
its boxes to fit whatever the constant says, so only the number needs changing.

Do not add `{{ .ConfirmationURL }}` back alongside the code. Offering both means
the link and the code race each other, and a link opened on a desktop browser
completes the verification somewhere the phone holding the form never learns
about. This is what keeps the password reset finishing **in the app**: the
recovery code grants a session, `SetNewPasswordScreen` spends it on
`updateUser(password:)`, and no deep link or redirect allowlist is involved
anywhere.

## `{{ .NewEmail }}`, not `{{ .Email }}`

The Change Email template names the address in its body. It has to use
`{{ .NewEmail }}`: this mail fires for a user who is attaching an address for the
first time, and an anonymous user has no *current* email, so `{{ .Email }}`
renders as an empty string and the sentence loses its object.

## Design notes

Straight from `lib/theme.dart`, so the mail matches the app it came from:

| Role | Token | Hex |
| --- | --- | --- |
| Page ground | `bg` | `#FCF6EC` |
| Card | `surface` / `divider` | `#FFFFFF` on `#E6DCC9` |
| Top rule, wordmark | `compassBlue` | `#2F549A` |
| Headings, digits | `deepNavy` | `#14254A` |
| Code chip | `secondarySoft` on `sand` | `#FAEBD5` / `#F8D59B` |
| Secondary text | `textSecondary` | `#6E7A93` |

Constraints worth keeping if you edit them:

- **No external assets.** No images, no web fonts, no CDN. Many clients block
  remote content by default, and a logo that fails to load is worse than a
  typographic wordmark that cannot. The app's Plus Jakarta Sans is not usable
  here for the same reason — the stack falls back to system fonts.
- **Tables and inline styles**, not divs and a stylesheet. Outlook's Word
  rendering engine ignores most of the latter.
- **`border-radius` degrades to square corners in Outlook.** That is the intended
  fallback, not a bug to work around with VML.
- **The code is not in the preheader.** The inbox list is the one place it would
  be readable without unlocking the device.
- The subject leads with the code because it makes the message scannable and
  helps iOS surface it for autofill. If you would rather it not appear on a lock
  screen, `Your Massar verification code` works as a subject and costs only that
  convenience.

## Checking a change

The dashboard's preview does not substitute `{{ .Token }}`. To see the real
thing, trigger a signup from the app against a real inbox — and check it on a
phone, since that is where every one of these is read.
