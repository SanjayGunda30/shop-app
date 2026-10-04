# Ledgerly POS web demo notes

- This is a Netlify-hosted Flutter Web demo with no backend or external authentication provider.
- Keep POS state in browser-local storage; do not describe local role previews as authentication or security.
- Run `flutter analyze` from `client` when Flutter is installed.
- Netlify deploys are published by `.github/workflows/deploy-netlify.yml` using GitHub Actions secrets.
