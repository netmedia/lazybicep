# LazyBicep

A project's Azure infrastructure from one map, with a terminal UI. The kit is `infra/` (`infra/LAZYBICEP.md` is
its reference); `initintoproject.ps1` puts it into a project. Work goes to `develop` through pull requests.

## Documents

- **The developer guide:** `docs/DEVELOPER-GUIDE.md` is the source. Its Word edition,
  `docs/LazyBicep-Developer-Guide.docx`, is built with the netmedia-document plugin from `docs/documents.json`
  (title, version from `infra/kit.json`, history) by `docs/build-documents.ps1` (`-Pdf` for a PDF too). Rebuild it
  after changing the guide, and add a history row in `docs/documents.json` for a new version.
- **The screenshots:** `docs/tools/screenshots.ps1` makes the guide's UI screenshots from the Contoso Shop demo
  (`docs/images/`), with the signed-in account and the subscriptions replaced by demo values.
- **The Knowledge Base:** every rebuilt document that is company knowledge also goes to the Knowledge Base with its
  Markdown sources and images (DP 5.8, netmedia-document:knowledge-base); its commands come after this
  repository's.
