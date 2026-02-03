require('dotenv').config();
const admin = require('firebase-admin');

try {
    const serviceAccount = require('../firebase-service-account.json');
    console.log(`Using project ID: ${serviceAccount.project_id}`);
    console.log(`FIRESTORE_EMULATOR_HOST: ${process.env.FIRESTORE_EMULATOR_HOST}`);

    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
        projectId: serviceAccount.project_id,
    });
    console.log('Firebase Admin initialized');
    console.log('Project ID: ', serviceAccount.project_id);
    console.log('Service Account: ', serviceAccount);


    const db = admin.firestore();

    async function test() {
        console.log('Attempting to fetch collections...');
        try {
            const collections = await db.listCollections();
            console.log(`Request succeeded. Found ${collections.length} collections.`);
            collections.forEach(c => console.log(` - ${c.id}`));

            console.log('Attempting to fetch pendingInvites...');
            const snapshot = await db.collection('pendingInvites').get();
            console.log(`Fetch succeeded. Documents: ${snapshot.size}`);
        } catch (e) {
            console.error('Fetch failed!');
            console.error('Error code:', e.code);
            console.error('Error message:', e.message);
            console.error(e);
        }
    }

    test();
} catch (e) {
    console.error('Setup failed:', e);
}
