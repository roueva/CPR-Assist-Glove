const nodemailer = require('nodemailer');

const transporter = nodemailer.createTransport({
    host: process.env.EMAIL_HOST,
    port: parseInt(process.env.EMAIL_PORT || '587'),
    secure: false,
    auth: {
        user: process.env.EMAIL_USER,
        pass: process.env.EMAIL_PASS,
    },
});

async function sendPasswordResetEmail(toEmail, resetToken) {
    const resetLink = `cpr-assist://reset-password?token=${resetToken}`;
    await transporter.sendMail({
        from: `"CPR Assist" <${process.env.EMAIL_USER}>`,
        to: toEmail,
        subject: 'Reset your CPR Assist password',
        html: `
            <p>You requested a password reset.</p>
            <p>Tap the link below in your phone to reset it. It expires in 1 hour.</p>
            <a href="${resetLink}">${resetLink}</a>
            <p>If you didn't request this, ignore this email.</p>
        `,
    });
}

async function sendUsernameReminderEmail(toEmail, username) {
    await transporter.sendMail({
        from: `"CPR Assist" <${process.env.EMAIL_USER}>`,
        to: toEmail,
        subject: 'Your CPR Assist username',
        html: `<p>Your username is: <strong>${username}</strong></p>`,
    });
}

module.exports = { sendPasswordResetEmail, sendUsernameReminderEmail };