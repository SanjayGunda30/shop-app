import 'dotenv/config';
import admin from 'firebase-admin';

const [email, role] = process.argv.slice(2);
if (!email || !['admin', 'cashier', 'viewer'].includes(role)) {
  console.error('Usage: FIREBASE_SERVICE_ACCOUNT="..." node scripts/set-role.js <email> <admin|cashier|viewer>');
  process.exit(1);
}
if (!process.env.FIREBASE_SERVICE_ACCOUNT) throw new Error('FIREBASE_SERVICE_ACCOUNT is required');
admin.initializeApp({ credential: admin.credential.cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT)) });
const user = await admin.auth().getUserByEmail(email);
await admin.auth().setCustomUserClaims(user.uid, { ...user.customClaims, role });
console.log(`Assigned ${role} to ${email}. Ask the user to sign in again to refresh their token.`);
await admin.app().delete();
