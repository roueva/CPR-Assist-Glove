const Brevo = require('@getbrevo/brevo');

const client = Brevo.ApiClient.instance;
client.authentications['api-key'].apiKey = process.env.BREVO_API_KEY;

const transactionalApi = new Brevo.TransactionalEmailsApi();

async function sendPasswordResetEmail(toEmail, resetToken) {
    const resetLink = `cpr-assist://reset-password?token=${resetToken}`;
    await transactionalApi.sendTransacEmail({
        sender: { name: 'CPR Assist', email: process.env.EMAIL_FROM },
        to: [{ email: toEmail }],
        subject: 'Reset your CPR Assist password',
        htmlContent: `
            <p>You requested a password reset.</p>
            <p>Tap the link below in your phone to reset it. It expires in 1 hour.</p>
            <a href="${resetLink}">${resetLink}</a>
            <p>If you didn't request this, ignore this email.</p>
        `,
    });
}

async function sendUsernameReminderEmail(toEmail, username) {
    await transactionalApi.sendTransacEmail({
        sender: { name: 'CPR Assist', email: process.env.EMAIL_FROM },
        to: [{ email: toEmail }],
        subject: 'Your CPR Assist username',
        htmlContent: `<p>Your username is: <strong>${username}</strong></p>`,
    });
}

module.exports = { sendPasswordResetEmail, sendUsernameReminderEmail };