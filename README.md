# Ledgerly POS Web Demo

A Netlify-hosted, web-only retail POS demo built with Flutter Web. It includes a dashboard, item and stock management, a cart, payment mode selection, PDF invoices, sales history, and a shop profile. It does not use Firebase or a separate API/backend.

## Data and roles

Items, completed sales, invoice numbering, and shop settings are saved in browser storage on the current device/browser. They are not shared across browsers or devices and can be erased by clearing browser data. The admin/cashier/viewer selector is only a UI preview; there is no sign-in or access control. Do not use this demo for shared or production sales records.

Images use URLs rather than uploaded files. Invoice calculations and GST fields are provided for demonstration only, not as a guarantee of statutory compliance. Verify applicable tax details and rules before issuing real invoices.

## Run locally

Prerequisites: Flutter stable with the Web toolchain.

```powershell
cd client
flutter create --platforms=web .
flutter pub get
flutter run -d chrome
```

## Deploy to Netlify

The GitHub Actions workflow at `.github/workflows/deploy-netlify.yml` builds Flutter Web on a hosted runner and publishes `client/build/web` on pushes to `main` or manual dispatch. Add only these repository Actions secrets:

- `NETLIFY_AUTH_TOKEN`: Netlify user settings → Applications → Personal access tokens.
- `NETLIFY_SITE_ID`: Netlify site configuration → General → Site details → API ID.

No API URL, Firebase configuration, database, or other hosting credentials are used by this demo. Free-plan limits are set by Netlify and may change.
