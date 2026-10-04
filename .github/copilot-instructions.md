# Ledgerly POS contributor notes

- Keep checkout stock changes atomic across SQLite and PostgreSQL.
- Never allow demo-role headers when `NODE_ENV=production`; production identity comes from Firebase ID tokens and custom role claims.
- Keep API validation in Zod schemas and Flutter API calls under `PosApi`.
- Run `npm test` from `backend` after API changes. Run `flutter analyze` from `client` when Flutter is installed.
- Never commit Firebase service-account JSON, `.env` values, Android signing keys, or local database files.
