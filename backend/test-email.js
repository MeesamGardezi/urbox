const nodemailer = require('nodemailer');

console.log('Nodemailer type:', typeof nodemailer);
console.log('Nodemailer keys:', Object.keys(nodemailer));
console.log('createTransporter type:', typeof nodemailer.createTransporter);

try {
    const transporter = nodemailer.createTransporter({
        host: 'test',
        port: 587
    });
    console.log('Transporter created successfully');
} catch (e) {
    console.error('Error creating transporter:', e);
}
