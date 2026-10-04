# Ledgerly POS

A free-resource retail point-of-sale and inventory starter for Flutter Android/Web, Express, SQLite, PostgreSQL/Supabase, and Firebase Authentication. The client includes a dashboard, stock editor, checkout, payment modes, PDF tax invoice, sales history, and shop profile. Demo mode works without Firebase; API demo roles are accepted only outside production.

## Local setup

Prerequisites: Node.js 20+, Flutter stable with Android and Web toolchains, and (optionally) a Firebase project.

1. Generate Flutter platform scaffolding once:

   ```powershell
   cd client
   flutter create --platforms=android,web .
   flutter pub get
   ```

2. Start the API in another terminal:

   ```powershell
   cd backend
   Copy-Item .env.example .env
   npm install
   npm run dev
   ```

   SQLite creates `backend/ledgerly.sqlite` automatically. Local development accepts the `x-demo-role` header; do not set `NODE_ENV=development` in production.

3. Run the app in a browser:

   ```powershell
   cd client
   flutter run -d chrome --dart-define=API_URL=http://localhost:3000
   ```

   For Firebase email/password sign-in, enable Email/Password in Firebase Authentication and pass `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`, and `FIREBASE_PROJECT_ID` using `--dart-define`. Set `FIREBASE_SERVICE_ACCOUNT` on the API to the service-account JSON string. Set Firebase custom claims `role` to `admin`, `cashier`, or `viewer`; run `npm run set-role -- cashier@example.com cashier` from `backend` to assign a role to an existing Firebase user. The server grants admin item/profile management, cashier checkout, and viewer read access.

## API and data

The API is under `/api`: `/health`, `/items`, `/sales`, `/reports/summary`, `/shop`, and `/team`. Checkout validates available stock and writes sale, lines, and stock decrements in one database transaction. SQLite is used when `DATABASE_URL` is empty; set `DATABASE_URL` to a PostgreSQL connection string to use Supabase. Set `DATABASE_SSL=true` for hosted PostgreSQL. Run `npm test` from `backend` for role, checkout, stock, and reporting coverage.

Images are stored as item image URLs, keeping the starter free of a paid file-storage dependency. GST is calculated from each item's configured rate. Invoices include financial-year sequence numbers, item HSN/SAC, place of supply, and an intra-state CGST/SGST or inter-state IGST split. Before issuing statutory invoices, configure and verify supplier GSTIN/address, product tax rates and codes, recipient details where required, place-of-supply selection, and applicable state rules with a qualified tax professional. Do not treat demo values as valid tax details.

## Deploy

- **Supabase:** create a PostgreSQL project and copy its connection string into Render's `DATABASE_URL`; keep SSL enabled.
- **Render:** create a Node web service using `render.yaml` (or root directory `backend`, build `npm install`, start `npm start`). Set `NODE_ENV=production`, `DATABASE_URL`, `DATABASE_SSL=true`, `FIREBASE_SERVICE_ACCOUNT`, and `CORS_ORIGIN` to the deployed frontend origin.
- **Netlify:** connect the repository to a Netlify site and add GitHub repository secrets `NETLIFY_AUTH_TOKEN`, `NETLIFY_SITE_ID`, `API_URL`, `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`, and `FIREBASE_PROJECT_ID`. The GitHub Actions workflow at `.github/workflows/deploy-netlify.yml` builds Flutter on a hosted runner and deploys on pushes to `main` (or manual dispatch). Configure the Render API's `CORS_ORIGIN` to the Netlify site origin.
- **Vercel:** use `vercel.json`, set `API_URL`, and configure the build environment with Flutter stable. Output is `client/build/web`.
- **Android / Play Console:** build with `flutter build appbundle --release` after setting the same `--dart-define` values and configuring Android signing in `client/android`. Upload the generated `.aab` through Play Console internal testing before production release; an APK can be generated with `flutter build apk --release`.

Free tiers and their limits change. Firebase, Render, Supabase, Netlify/Vercel, Android signing, and Play Console accounts are separate services; no credentials or billing are included here.
