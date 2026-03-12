const axios = require('axios');

async function sendPasswordResetEmail(toEmail, resetToken) {
    const resetLink = `cpr-assist://reset-password?token=${resetToken}`;
    await axios.post('https://api.brevo.com/v3/smtp/email', {
        sender: { name: 'CPR Assist', email: process.env.EMAIL_FROM },
        to: [{ email: toEmail }],
        subject: 'Reset your CPR Assist password',
        htmlContent: `
            <p>You requested a password reset.</p>
            <p>Tap the link below in your phone to reset it. It expires in 1 hour.</p>
            <a href="${resetLink}">${resetLink}</a>
            <p>If you didn't request this, ignore this email.</p>
        `,
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
        htmlContent: `<p>Your username is: <strong>${username}</strong></p>`,
    }, {
        headers: {
            'api-key': process.env.BREVO_API_KEY,
            'Content-Type': 'application/json',
        },
    });
}

module.exports = { sendPasswordResetEmail, sendUsernameReminderEmail };