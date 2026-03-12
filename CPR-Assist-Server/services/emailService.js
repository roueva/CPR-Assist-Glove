const axios = require('axios');

async function sendPasswordResetEmail(toEmail, resetToken) {
    const resetLink = `cpr-assist://reset-password?token=${resetToken}`;
    await axios.post('https://api.brevo.com/v3/smtp/email', {
        sender: { name: 'CPR Assist', email: process.env.EMAIL_FROM },
        to: [{ email: toEmail }],
        subject: 'Reset your CPR Assist password',
        htmlContent: `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin:0;padding:0;background-color:#F4F7FB;font-family:Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#F4F7FB;padding:40px 16px;">
    <tr><td align="center">
      <table width="100%" style="max-width:480px;" cellpadding="0" cellspacing="0">

        <!-- HEADER — matches primaryGradientCard -->
        <tr>
          <td style="background:linear-gradient(135deg,#194E9D 0%,#355CA9 100%);border-radius:16px 16px 0 0;padding:40px 32px 32px;">

            <!-- Icon circle — matches AppDecorations.iconCircle -->
            <div style="width:64px;height:64px;background:rgba(255,255,255,0.15);border-radius:50%;margin:0 0 16px;display:inline-flex;align-items:center;justify-content:center;">
              <span style="font-size:28px;line-height:64px;display:block;text-align:center;">🔒</span>
            </div>

            <h1 style="margin:0 0 4px;color:#FFFFFF;font-size:26px;font-weight:700;letter-spacing:-0.5px;">CPR Assist</h1>
            <p style="margin:0;color:rgba(255,255,255,0.75);font-size:14px;">Password Reset Request</p>
          </td>
        </tr>

        <!-- BODY — white card -->
        <tr>
          <td style="background:#FFFFFF;padding:32px;">

            <h2 style="margin:0 0 8px;color:#111827;font-size:20px;font-weight:700;">Reset your password</h2>
            <p style="margin:0 0 28px;color:#4B5563;font-size:15px;line-height:1.6;">
              We received a request to reset the password for your account.
              Tap the button below to choose a new one. This link expires in <strong>1 hour</strong>.
            </p>

            <!-- CTA Button — matches ElevatedButton style -->
            <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:28px;">
              <tr>
                <td align="center">
                  <a href="${resetLink}"
                     style="display:inline-block;background:linear-gradient(135deg,#194E9D,#355CA9);color:#FFFFFF;text-decoration:none;font-size:16px;font-weight:700;padding:16px 48px;border-radius:12px;letter-spacing:0.2px;">
                    Reset Password
                  </a>
                </td>
              </tr>
            </table>

            <!-- Info box — matches AppDecorations.primaryCard / primaryLight bg -->
            <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:24px;">
              <tr>
                <td style="background:#EDF4F9;border-radius:10px;padding:16px 20px;">
                  <p style="margin:0 0 4px;color:#194E9D;font-size:13px;font-weight:700;">⏱ Link expires in 1 hour</p>
                  <p style="margin:0;color:#4B5563;font-size:13px;line-height:1.5;">
                    If it expires, open the app and request a new reset link from the login screen.
                  </p>
                </td>
              </tr>
            </table>

            <p style="margin:0;color:#9CA3AF;font-size:13px;line-height:1.6;">
              If you didn't request a password reset, you can safely ignore this email.
              Your password will not be changed.
            </p>
          </td>
        </tr>

        <!-- FOOTER -->
        <tr>
          <td style="background:#F4F7FB;border-radius:0 0 16px 16px;padding:20px 32px;text-align:center;border-top:1px solid #EEF2F7;">
            <p style="margin:0;color:#9CA3AF;font-size:12px;">© 2026 CPR Assist · Helping save lives</p>
          </td>
        </tr>

      </table>
    </td></tr>
  </table>
</body>
</html>`,
    }, {
        headers: {
            'api-key': process.env.BREVO_API_KEY,
            'Content-Type': 'application/json',
        },
    });
}

async function sendUsernameReminderEmail(toEmail, username) {
    await axios.post('https://api.brevo.com/v3/smtp/email', {
        sender: { name: 'CPR Assist', email: process.env.EMAIL_FROM },
        to: [{ email: toEmail }],
        subject: 'Your CPR Assist username',
        htmlContent: `
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body style="margin:0;padding:0;background-color:#F4F7FB;font-family:Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#F4F7FB;padding:40px 0;">
    <tr><td align="center">
      <table width="480" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,0.08);">
        <tr>
          <td style="background:linear-gradient(135deg,#194E9D,#355CA9);padding:40px 32px;text-align:center;">
            <h1 style="margin:0;color:#ffffff;font-size:24px;font-weight:700;">CPR Assist</h1>
            <p style="margin:8px 0 0;color:rgba(255,255,255,0.75);font-size:14px;">Username Reminder</p>
          </td>
        </tr>
        <tr>
          <td style="padding:40px 32px;">
            <h2 style="margin:0 0 8px;color:#111827;font-size:20px;font-weight:700;">Your username</h2>
            <p style="margin:0 0 24px;color:#4B5563;font-size:15px;">Here's the username associated with this email address:</p>
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr>
                <td style="background:#EDF4F9;border-radius:10px;padding:20px;text-align:center;">
                  <p style="margin:0;color:#194E9D;font-size:22px;font-weight:700;">${username}</p>
                </td>
              </tr>
            </table>
            <p style="margin:24px 0 0;color:#9CA3AF;font-size:13px;">If you didn't request this, you can safely ignore this email.</p>
          </td>
        </tr>
        <tr>
          <td style="background:#F4F7FB;padding:24px 32px;text-align:center;border-top:1px solid #EEF2F7;">
            <p style="margin:0;color:#9CA3AF;font-size:12px;">© 2026 CPR Assist. Helping save lives.</p>
          </td>
        </tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`,
    }, {
        headers: {
            'api-key': process.env.BREVO_API_KEY,
            'Content-Type': 'application/json',
        },
    });
}

module.exports = { sendPasswordResetEmail, sendUsernameReminderEmail };