const nodemailer = require('nodemailer');

class EmailService {
    constructor() {
        this.transporter = null;
        this.initialize();
    }

    initialize() {
        // Only initialize if credentials are provided
        if (process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS) {
            this.transporter = nodemailer.createTransport({
                host: process.env.SMTP_HOST,
                port: parseInt(process.env.SMTP_PORT || '587'),
                secure: process.env.SMTP_SECURE === 'true', // true for 465, false for other ports
                auth: {
                    user: process.env.SMTP_USER,
                    pass: process.env.SMTP_PASS
                }
            });
            console.log('[EmailService] SMTP transporter initialized');
        } else {
            console.warn('[EmailService] SMTP credentials missing. Email sending disabled.');
        }
    }

    async sendEmail({ to, subject, html, text }) {
        if (!this.transporter) {
            console.warn(`[EmailService] Skipping email to ${to} (SMTP not configured)`);
            return false;
        }

        try {
            const info = await this.transporter.sendMail({
                from: `"${process.env.SMTP_FROM_NAME || 'URBox'}" <${process.env.SMTP_USER}>`,
                to,
                subject,
                text: text || html.replace(/<[^>]*>?/gm, ''), // Fallback plain text
                html
            });

            console.log(`[EmailService] Email sent to ${to}: ${info.messageId}`);
            return true;
        } catch (error) {
            console.error('[EmailService] Send error:', error);
            return false;
        }
    }

    /**
     * Send a team invitation email
     */
    async sendTeamInvitation({ to, inviterName, companyName, inviteLink, inboxCount }) {
        const subject = `${inviterName} invited you to join ${companyName} on URBox`;

        const inboxText = inboxCount > 0
            ? `You'll have access to <strong>${inboxCount} shared inbox${inboxCount > 1 ? 'es' : ''}</strong> immediately upon joining.`
            : 'You can be assigned to shared inboxes after you join.';

        const html = `
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Team Invitation</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; background-color: #f9fafb; }
        .container { max-width: 600px; margin: 40px auto; background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1); }
        .header { background: linear-gradient(135deg, #6366f1 0%, #a855f7 100%); padding: 32px; text-align: center; color: white; }
        .header h1 { margin: 0; font-size: 24px; font-weight: 700; }
        .content { padding: 32px; }
        .inviter-badge { display: inline-block; background: #eef2ff; color: #4f46e5; padding: 4px 12px; border-radius: 9999px; font-weight: 500; font-size: 14px; margin-bottom: 16px; }
        .button { display: inline-block; background: #4f46e5; color: white; padding: 12px 24px; border-radius: 8px; text-decoration: none; font-weight: 600; margin-top: 24px; margin-bottom: 24px; text-align: center; }
        .button:hover { background: #4338ca; }
        .footer { background: #f3f4f6; padding: 24px; text-align: center; font-size: 12px; color: #6b7280; }
        .link-text { word-break: break-all; color: #6b7280; margin-top: 8px; font-size: 13px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Join the team!</h1>
        </div>
        <div class="content">
            <div class="inviter-badge">Invitation from ${inviterName}</div>
            <h2 style="margin-top: 0;">You've been invited to join ${companyName}</h2>
            
            <p><strong>${inviterName}</strong> has invited you to collaborate on their team using URBox.</p>
            
            <p>${inboxText}</p>
            
            <div style="text-align: center;">
                <a href="${inviteLink}" class="button">Accept Invitation</a>
            </div>
            
            <p style="font-size: 14px; color: #6b7280; text-align: center;">
                or copy and paste this link into your browser:<br>
                <div class="link-text">${inviteLink}</div>
            </p>
        </div>
        <div class="footer">
            <p>This invitation expires in 7 days.</p>
            <p>&copy; ${new Date().getFullYear()} URBox. All rights reserved.</p>
        </div>
    </div>
</body>
</html>
        `;

        return this.sendEmail({ to, subject, html });
    }

    /**
     * Send notification when a user is removed from a team
     */
    async sendMemberRemovedNotification({ to, companyName }) {
        const subject = `Access revoked from ${companyName}`;
        const html = `
            <div style="font-family: sans-serif; max-width: 600px; margin: 0 auto;">
                <h2>Access Update</h2>
                <p>Your access to the team <strong>${companyName}</strong> on URBox has been revoked.</p>
                <p>If you believe this is a mistake, please contact the team owner.</p>
            </div>
        `;
        return this.sendEmail({ to, subject, html });
    }
}

module.exports = new EmailService();
